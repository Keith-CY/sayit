import AVFoundation
import CoreAudio
import Foundation

/// A Live Captions audio input: delivers 16 kHz mono Float32 chunks on a background queue.
protocol CaptionAudioSource: AnyObject {
    func start() throws
    func stop()
}

/// Shared format and Core Audio helpers for Live Captions capture.
enum CaptionAudio {
    nonisolated static let sampleRate: Double = 16000
    // A constant, valid PCM format; this initializer only fails for invalid parameters.
    // swiftlint:disable force_unwrapping
    nonisolated static let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: CaptionAudio.sampleRate,
        channels: 1,
        interleaved: false
    )!
    // swiftlint:enable force_unwrapping

    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func read<T>(
        _ selector: AudioObjectPropertySelector,
        of object: AudioObjectID,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        into value: inout T
    ) -> OSStatus {
        var address = self.address(selector, scope: scope)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
    }

    static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        let status = self.read(selector, of: AudioObjectID(kAudioObjectSystemObject), into: &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    static func uid(of device: AudioObjectID) -> String? {
        var uid: Unmanaged<CFString>?
        guard self.read(kAudioDevicePropertyDeviceUID, of: device, into: &uid) == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }
}

/// Calls `onChange` on the main queue when a system default device (input or output)
/// changes, until `cancel()`.
final class DefaultDeviceObserver {
    private let selector: AudioObjectPropertySelector
    private var listener: AudioObjectPropertyListenerBlock?

    init(_ selector: AudioObjectPropertySelector, onChange: @escaping @MainActor () -> Void) {
        self.selector = selector
        var address = CaptionAudio.address(selector)
        let listener: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async { onChange() }
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, nil, listener) == noErr {
            self.listener = listener
        }
    }

    func cancel() {
        guard let listener = self.listener else { return }
        var address = CaptionAudio.address(self.selector)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, nil, listener)
        self.listener = nil
    }
}

/// Converts device audio to 16 kHz mono and hands it on in 100 ms chunks. Used only on
/// the capture queue that runs the IO callback.
nonisolated final class CaptureConverter: @unchecked Sendable {
    private static let chunkSamples = Int(CaptionAudio.sampleRate / 10)
    private let onSamples: @Sendable ([Float]) -> Void
    private var format: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var pending: [Float] = []

    init(onSamples: @escaping @Sendable ([Float]) -> Void) {
        self.onSamples = onSamples
    }

    /// Prepares for audio in `format`, or drops all state when nil.
    func configure(for format: AVAudioFormat?) {
        self.format = format
        self.converter = format.flatMap { AVAudioConverter(from: $0, to: CaptionAudio.outputFormat) }
        self.converter?.downmix = true
        self.pending.removeAll()
    }

    /// - Parameter firstBufferOnly: Read only the first stream of a multi-stream device.
    func convert(_ inputData: UnsafePointer<AudioBufferList>, firstBufferOnly: Bool = false) {
        guard firstBufferOnly, inputData.pointee.mNumberBuffers > 1 else {
            return self.convertList(inputData)
        }
        var first = AudioBufferList(mNumberBuffers: 1, mBuffers: inputData.pointee.mBuffers)
        withUnsafePointer(to: &first) { self.convertList($0) }
    }

    private func convertList(_ inputData: UnsafePointer<AudioBufferList>) {
        guard let format = self.format, let converter = self.converter,
              let input = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inputData, deallocator: nil),
              input.frameLength > 0
        else { return }

        let ratio = CaptionAudio.sampleRate / format.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: CaptionAudio.outputFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, output.frameLength > 0, let channel = output.floatChannelData?[0] else { return }
        self.pending.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        guard self.pending.count >= Self.chunkSamples else { return }
        let chunk = self.pending
        self.pending.removeAll(keepingCapacity: true)
        self.onSamples(chunk)
    }
}

/// Captures what the Mac is playing — every app except SayIt — through a Core Audio
/// process tap.
///
/// The tap feeds a private aggregate device whose clock comes from the default output
/// device; when the user switches output (speakers → AirPods), capture restarts on the
/// new device.
@available(macOS 14.2, *)
final class SystemAudioCapture: CaptionAudioSource {
    enum CaptureError: LocalizedError {
        case tapUnavailable(OSStatus)
        case outputDeviceUnavailable
        case deviceStartFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case let .tapUnavailable(status): return "Couldn’t tap system audio (\(status))."
            case .outputDeviceUnavailable: return "No audio output device is available."
            case let .deviceStartFailed(status): return "Couldn’t start system audio capture (\(status))."
            }
        }
    }

    private let converter: CaptureConverter
    private let queue = DispatchQueue(label: "com.sayit.livecaptions.system-audio", qos: .userInitiated)

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var outputObserver: DefaultDeviceObserver?

    /// - Parameter onSamples: Called on a background queue with each converted chunk.
    init(onSamples: @escaping @Sendable ([Float]) -> Void) {
        self.converter = CaptureConverter(onSamples: onSamples)
    }

    func start() throws {
        try self.startDevice()
        self.outputObserver = DefaultDeviceObserver(kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
            self?.restartForNewOutput()
        }
    }

    func stop() {
        self.outputObserver?.cancel()
        self.outputObserver = nil
        self.stopDevice()
    }

    // MARK: - Device lifecycle

    private func startDevice() throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: Self.ownAudioProcesses())
        description.uuid = UUID()
        description.name = "SayIt Live Captions"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw CaptureError.tapUnavailable(status) }
        self.tapID = tapID

        var streamDescription = AudioStreamBasicDescription()
        status = CaptionAudio.read(kAudioTapPropertyFormat, of: tapID, into: &streamDescription)
        guard status == noErr, let tapFormat = AVAudioFormat(streamDescription: &streamDescription) else {
            self.stopDevice()
            throw CaptureError.tapUnavailable(status)
        }

        guard let output = CaptionAudio.defaultDevice(kAudioHardwarePropertyDefaultOutputDevice),
              let outputUID = CaptionAudio.uid(of: output)
        else {
            self.stopDevice()
            throw CaptureError.outputDeviceUnavailable
        }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SayIt Live Captions",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else {
            self.stopDevice()
            throw CaptureError.deviceStartFailed(status)
        }
        self.aggregateID = aggregateID

        let converter = self.converter
        self.queue.sync { converter.configure(for: tapFormat) }

        var ioProcID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, self.queue) { @Sendable _, inputData, _, _, _ in
            converter.convert(inputData)
        }
        guard status == noErr, let ioProcID else {
            self.stopDevice()
            throw CaptureError.deviceStartFailed(status)
        }
        self.ioProcID = ioProcID

        status = AudioDeviceStart(aggregateID, ioProcID)
        guard status == noErr else {
            self.stopDevice()
            throw CaptureError.deviceStartFailed(status)
        }
        DebugLogger.shared.info(
            "SystemAudioCapture: started (tap \(Int(tapFormat.sampleRate)) Hz, \(tapFormat.channelCount) ch, output \(outputUID))",
            source: "SystemAudioCapture"
        )
    }

    private func stopDevice() {
        if self.aggregateID != kAudioObjectUnknown {
            if let ioProcID = self.ioProcID {
                AudioDeviceStop(self.aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(self.aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(self.aggregateID)
        }
        if self.tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(self.tapID)
        }
        self.ioProcID = nil
        self.aggregateID = AudioObjectID(kAudioObjectUnknown)
        self.tapID = AudioObjectID(kAudioObjectUnknown)
        // Wait out an IO callback that may still be running before dropping its state.
        let converter = self.converter
        self.queue.sync { converter.configure(for: nil) }
    }

    private func restartForNewOutput() {
        guard self.outputObserver != nil else { return }
        DebugLogger.shared.info("SystemAudioCapture: default output changed, restarting", source: "SystemAudioCapture")
        self.stopDevice()
        do {
            try self.startDevice()
        } catch {
            DebugLogger.shared.error("SystemAudioCapture: restart failed: \(error)", source: "SystemAudioCapture")
        }
    }

    /// SayIt's own audio process object, so its sounds never become captions.
    private static func ownAudioProcesses() -> [AudioObjectID] {
        var address = CaptionAudio.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = ProcessInfo.processInfo.processIdentifier
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &pid,
            &size,
            &object
        )
        return status == noErr && object != kAudioObjectUnknown ? [object] : []
    }
}
