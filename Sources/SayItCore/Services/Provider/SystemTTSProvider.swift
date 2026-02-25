import AppKit
import Foundation

public final class SystemTTSProvider: NSObject, TTSProvider, @unchecked Sendable {
    public let id = "system_tts"

    public override init() {
        super.init()
    }

    public func synthesize(_ request: TTSRequest) async throws -> TTSAudio {
        let synth = NSSpeechSynthesizer()
        synth.rate = Float(request.speed * 180.0)
        _ = synth.setVoice(NSSpeechSynthesizer.defaultVoice)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("sayit-tts-\(UUID().uuidString).aiff")
        let success = synth.startSpeaking(request.text, to: tempURL)
        guard success else {
            throw SayItError.unavailable("System TTS failed to start speaking")
        }

        // Poll until synth finishes writing.
        while synth.isSpeaking {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let data = (try? Data(contentsOf: tempURL)) ?? Data()
        return TTSAudio(data: data, format: "aiff", durationMs: 0, provider: id)
    }
}
