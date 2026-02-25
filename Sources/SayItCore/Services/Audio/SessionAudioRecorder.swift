@preconcurrency import AVFoundation
import Foundation

public final class SessionAudioRecorder: NSObject, @unchecked Sendable {
    private var recorder: AVAudioRecorder?
    private var outputURL: URL?

    public override init() {
        super.init()
    }

    public func startRecording() async throws -> URL {
        if let outputURL {
            return outputURL
        }

        try await ensureMicrophonePermission()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sayit-session-\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw SayItError.unavailable("Failed to start session audio recorder")
        }

        self.recorder = recorder
        self.outputURL = url
        return url
    }

    @discardableResult
    public func stopRecording() -> URL? {
        recorder?.stop()
        recorder = nil
        defer { outputURL = nil }
        return outputURL
    }

    public var isRecording: Bool {
        recorder?.isRecording == true
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
