import Foundation
#if arch(arm64)
import MLX
import MLXAudioSTT
#endif

/// Local final transcription using the pinned MLX Qwen3-ASR 1.7B 8-bit model.
final class QwenASRProvider: TranscriptionProvider {
    let name = "Qwen3-ASR 1.7B (MLX 8bit)"
    private(set) var isReady = false
    private let store: QwenModelStore
    #if arch(arm64)
    private let runtime = QwenInferenceRuntime()
    #endif

    var isAvailable: Bool { CPUArchitecture.isAppleSilicon }

    init(modelDirectory: URL = QwenModelStore.defaultDirectory, session: URLSession = .shared) {
        self.store = QwenModelStore(directory: modelDirectory, session: session)
    }

    func download(progressHandler: ((Double) -> Void)?) async throws {
        guard self.isAvailable else { throw QwenModelError.unsupportedHardware }
        try await self.store.download(progressHandler: progressHandler)
    }

    func prepare(progressHandler: ((Double) -> Void)?) async throws {
        guard self.isAvailable else { throw QwenModelError.unsupportedHardware }
        guard !self.isReady else { return }
        try await self.download(progressHandler: progressHandler)
        try Task.checkCancellation()
        #if arch(arm64)
        try await self.runtime.load(from: self.store.directory)
        try Task.checkCancellation()
        self.isReady = true
        #endif
    }

    func modelsExistOnDisk() -> Bool { self.store.isInstalled }

    func clearCache() async throws {
        self.isReady = false
        #if arch(arm64)
        await self.runtime.unload()
        #endif
        try self.store.remove()
    }

    func transcribe(_ samples: [Float]) async throws -> ASRTranscriptionResult {
        guard self.isReady else { throw QwenModelError.notReady }
        guard samples.allSatisfy(\.isFinite) else { throw QwenModelError.invalidAudio }
        guard !samples.isEmpty, samples.contains(where: { $0 != 0 }) else {
            return ASRTranscriptionResult(text: "")
        }
        let mode = await MainActor.run { SettingsStore.shared.speechLanguageMode }
        #if arch(arm64)
        let text = try await self.runtime.transcribe(samples, language: Self.language(for: mode))
        return ASRTranscriptionResult(text: text)
        #else
        throw QwenModelError.unsupportedHardware
        #endif
    }

    static func language(for mode: SettingsStore.SpeechLanguageMode) -> String? {
        switch mode {
        case .auto: return nil
        case .chineseEnglishMixed, .chineseSimplified, .chineseTraditional: return "Chinese"
        case .english: return "English"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .french: return "French"
        case .german: return "German"
        case .spanish: return "Spanish"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        case .russian: return "Russian"
        }
    }
}

#if arch(arm64)
/// Keeps the mutable MLX model off the main thread and serializes inference.
private actor QwenInferenceRuntime {
    private var model: Qwen3ASRModel?

    func load(from directory: URL) async throws {
        guard self.model == nil else { return }
        // Bound reusable GPU buffers so switching away can return memory to the system.
        Memory.cacheLimit = 64 * 1024 * 1024
        let loaded = try await Qwen3ASRModel.fromModelDirectory(directory)
        try Task.checkCancellation()
        self.model = loaded
    }

    func unload() {
        self.model = nil
        Memory.clearCache()
    }

    func transcribe(_ samples: [Float], language: String?) throws -> String {
        guard let model = self.model else { throw QwenModelError.notReady }
        try Task.checkCancellation()
        let output = model.generate(
            audio: MLXArray(samples),
            maxTokens: 8192,
            temperature: 0,
            language: language,
            chunkDuration: 30
        )
        try Task.checkCancellation()
        return output.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
