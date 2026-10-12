import AVFoundation
import CoreAudio
import Foundation

/// Captures what the Mac is playing — every app except SayIt — through a Core Audio
/// process tap, and delivers it as 16 kHz mono Float32 chunks on a background queue.
///
/// The tap feeds a private aggregate device whose clock comes from the default output
/// device; when the user switches output (speakers → AirPods), capture restarts on the
/// new device.
@available(macOS 14.2, *)
final class SystemAudioCapture {
    enum CaptureError: LocalizedError {
        case tapUnavailable(OSStatus)
        case outputDeviceUnavailable(OSStatus)
        case deviceStartFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case let .tapUnavailable(status): return "Couldn’t tap system audio (\(status))."
            case let .outputDeviceUnavailable(status): return "No audio output device is available (\(status))."
            case let .deviceStartFailed(status): return "Couldn’t start system audio capture (\(status))."
            }
        }
    }

    nonisolated static let sampleRate: Double = 16000
    // A constant, valid PCM format; this initializer only fails for invalid parameters.
    // swiftlint:disable force_unwrapping
    nonisolated static let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: SystemAudioCapture.sampleRate,
        channels: 1,
        interleaved: false
    )!
    // swiftlint:enable force_unwrapping

    private let onSamples: @Sendable ([Float]) -> Void
    private let queue = DispatchQueue(label: "com.sayit.livecaptions.capture", qos: .userInitiated)

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    // Touched only on `queue`, where the IO callback runs.
    private nonisolated(unsafe) var tapFormat: AVAudioFormat?
    private nonisolated(unsafe) var converter: AVAudioConverter?
    /// IO callbacks arrive every few milliseconds; samples are handed on in 100 ms chunks.
    private nonisolated(unsafe) var pending: [Float] = []
    private nonisolated static let chunkSamples = Int(SystemAudioCapture.sampleRate / 10)
    private var outputListener: AudioObjectPropertyListenerBlock?

    /// - Parameter onSamples: Called on a background queue with each converted chunk.
    init(onSamples: @escaping @Sendable ([Float]) -> Void) {
        self.onSamples = onSamples
    }

    func start() throws {
        try self.startDevice()
        self.observeDefaultOutput()
    }

    func stop() {
        self.stopObservingDefaultOutput()
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
        status = Self.read(kAudioTapPropertyFormat, of: tapID, into: &streamDescription)
        guard status == noErr, let tapFormat = AVAudioFormat(streamDescription: &streamDescription) else {
            self.stopDevice()
            throw CaptureError.tapUnavailable(status)
        }

        let outputUID: String
        do {
            outputUID = try Self.defaultOutputDeviceUID()
        } catch {
            self.stopDevice()
            throw error
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

        let converter = AVAudioConverter(from: tapFormat, to: Self.outputFormat)
        converter?.downmix = true
        self.queue.sync {
            self.tapFormat = tapFormat
            self.converter = converter
        }

        var ioProcID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, self.queue) { @Sendable [weak self] _, inputData, _, _, _ in
            self?.convertAndDeliver(inputData)
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
        self.queue.sync {
            self.tapFormat = nil
            self.converter = nil
            self.pending.removeAll()
        }
    }

    // MARK: - Conversion (on `queue`)

    private nonisolated func convertAndDeliver(_ inputData: UnsafePointer<AudioBufferList>) {
        guard let tapFormat = self.tapFormat, let converter = self.converter,
              let input = AVAudioPCMBuffer(pcmFormat: tapFormat, bufferListNoCopy: inputData, deallocator: nil),
              input.frameLength > 0
        else { return }

        let ratio = Self.sampleRate / tapFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: Self.outputFormat, frameCapacity: capacity) else { return }

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

    // MARK: - Output device changes

    private func observeDefaultOutput() {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.restartForNewOutput() }
        }
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, nil, listener)
        if status == noErr { self.outputListener = listener }
    }

    private func stopObservingDefaultOutput() {
        guard let listener = self.outputListener else { return }
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, nil, listener)
        self.outputListener = nil
    }

    private func restartForNewOutput() {
        guard self.outputListener != nil else { return }
        DebugLogger.shared.info("SystemAudioCapture: default output changed, restarting", source: "SystemAudioCapture")
        self.stopDevice()
        do {
            try self.startDevice()
        } catch {
            DebugLogger.shared.error("SystemAudioCapture: restart failed: \(error)", source: "SystemAudioCapture")
        }
    }

    // MARK: - Core Audio helpers

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func read<T>(_ selector: AudioObjectPropertySelector, of object: AudioObjectID, into value: inout T) -> OSStatus {
        var address = self.address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
    }

    /// SayIt's own audio process object, so its sounds never become captions.
    private static func ownAudioProcesses() -> [AudioObjectID] {
        var address = self.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
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

    private static func defaultOutputDeviceUID() throws -> String {
        var device = AudioObjectID(kAudioObjectUnknown)
        var status = self.read(kAudioHardwarePropertyDefaultOutputDevice, of: AudioObjectID(kAudioObjectSystemObject), into: &device)
        guard status == noErr, device != kAudioObjectUnknown else { throw CaptureError.outputDeviceUnavailable(status) }

        var uid: Unmanaged<CFString>?
        status = self.read(kAudioDevicePropertyDeviceUID, of: device, into: &uid)
        guard status == noErr, let uid else { throw CaptureError.outputDeviceUnavailable(status) }
        return uid.takeRetainedValue() as String
    }
}
