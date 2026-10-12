import AVFoundation
import CoreAudio
import Foundation

/// Captures the microphone for Live Captions, reading the input device directly so it
/// doesn't share an engine with dictation. Uses the same device dictation does: the
/// preferred input when SayIt manages devices itself, otherwise the system default
/// (and follows changes to it).
final class MicrophoneCapture: CaptionAudioSource {
    enum CaptureError: LocalizedError {
        case noInputDevice
        case formatUnavailable(OSStatus)
        case deviceStartFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .noInputDevice: return "No microphone is available."
            case let .formatUnavailable(status): return "Couldn’t read the microphone format (\(status))."
            case let .deviceStartFailed(status): return "Couldn’t start the microphone (\(status))."
            }
        }
    }

    private let converter: CaptureConverter
    private let queue = DispatchQueue(label: "com.sayit.livecaptions.microphone", qos: .userInitiated)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var inputObserver: DefaultDeviceObserver?

    /// - Parameter onSamples: Called on a background queue with each converted chunk.
    init(onSamples: @escaping @Sendable ([Float]) -> Void) {
        self.converter = CaptureConverter(onSamples: onSamples)
    }

    func start() throws {
        let (device, followsDefault) = Self.inputDevice()
        guard let device else { throw CaptureError.noInputDevice }
        try self.startDevice(device)
        if followsDefault {
            self.inputObserver = DefaultDeviceObserver(kAudioHardwarePropertyDefaultInputDevice) { [weak self] in
                self?.restartForNewInput()
            }
        }
    }

    func stop() {
        self.inputObserver?.cancel()
        self.inputObserver = nil
        self.stopDevice()
    }

    private func startDevice(_ device: AudioObjectID) throws {
        var streamDescription = AudioStreamBasicDescription()
        var status = CaptionAudio.read(
            kAudioDevicePropertyStreamFormat,
            of: device,
            scope: kAudioDevicePropertyScopeInput,
            into: &streamDescription
        )
        guard status == noErr, let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw CaptureError.formatUnavailable(status)
        }
        let converter = self.converter
        self.queue.sync { converter.configure(for: format) }

        var ioProcID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, device, self.queue) { @Sendable _, inputData, _, _, _ in
            converter.convert(inputData, firstBufferOnly: true)
        }
        guard status == noErr, let ioProcID else { throw CaptureError.deviceStartFailed(status) }
        status = AudioDeviceStart(device, ioProcID)
        guard status == noErr else {
            AudioDeviceDestroyIOProcID(device, ioProcID)
            throw CaptureError.deviceStartFailed(status)
        }
        self.deviceID = device
        self.ioProcID = ioProcID
        DebugLogger.shared.info(
            "MicrophoneCapture: started (\(Int(format.sampleRate)) Hz, \(format.channelCount) ch, \(CaptionAudio.uid(of: device) ?? "?"))",
            source: "MicrophoneCapture"
        )
    }

    private func stopDevice() {
        if self.deviceID != kAudioObjectUnknown, let ioProcID = self.ioProcID {
            AudioDeviceStop(self.deviceID, ioProcID)
            AudioDeviceDestroyIOProcID(self.deviceID, ioProcID)
        }
        self.ioProcID = nil
        self.deviceID = AudioObjectID(kAudioObjectUnknown)
        let converter = self.converter
        self.queue.sync { converter.configure(for: nil) }
    }

    private func restartForNewInput() {
        guard self.inputObserver != nil, let device = CaptionAudio.defaultDevice(kAudioHardwarePropertyDefaultInputDevice) else {
            return
        }
        DebugLogger.shared.info("MicrophoneCapture: default input changed, restarting", source: "MicrophoneCapture")
        self.stopDevice()
        do {
            try self.startDevice(device)
        } catch {
            DebugLogger.shared.error("MicrophoneCapture: restart failed: \(error)", source: "MicrophoneCapture")
        }
    }

    /// Dictation's input device, and whether it is the system default (so changes to the
    /// default should be followed).
    private static func inputDevice() -> (AudioObjectID?, followsDefault: Bool) {
        let settings = SettingsStore.shared
        if !settings.syncAudioDevicesWithSystem, let uid = settings.preferredInputDeviceUID, !uid.isEmpty,
           let device = AudioDevice.getInputDevice(byUID: uid) {
            return (device.id, false)
        }
        return (CaptionAudio.defaultDevice(kAudioHardwarePropertyDefaultInputDevice), true)
    }
}
