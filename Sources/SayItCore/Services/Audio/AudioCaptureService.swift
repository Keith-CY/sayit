@preconcurrency import AVFoundation
import Foundation

public final class AudioCaptureService: NSObject, @unchecked Sendable {
    private var recorder: AVAudioRecorder?

    public override init() {
        super.init()
    }

    public func recordFor(seconds: TimeInterval = 3.0) async throws -> URL {
        try await ensureMicrophonePermission()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sayit-capture-\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        recorder = try AVAudioRecorder(url: url, settings: settings)
        guard let recorder else {
            throw SayItError.unavailable("Failed to initialize audio recorder")
        }

        recorder.prepareToRecord()
        guard recorder.record(forDuration: seconds) else {
            throw SayItError.unavailable("Failed to start audio recording")
        }

        while recorder.isRecording {
            do {
                try await Task.sleep(nanoseconds: 100_000_000)
            } catch is CancellationError {
                // Graceful stop: keep the partially recorded chunk so upper layer can still transcribe.
                recorder.stop()
                break
            }
        }

        self.recorder = nil
        return url
    }

    public func stop() {
        recorder?.stop()
        recorder = nil
    }

    private func ensureMicrophonePermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { access in
                    continuation.resume(returning: access)
                }
            }
            guard granted else {
                throw SayItError.authentication("Microphone permission denied")
            }
        case .restricted, .denied:
            throw SayItError.authentication("Microphone permission is restricted or denied")
        @unknown default:
            throw SayItError.authentication("Unknown microphone authorization status")
        }
    }
}
