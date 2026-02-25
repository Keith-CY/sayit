import Foundation
import SwiftWhisper

public struct WhisperSTTProvider: STTProvider {
    public let id = "whisper"

    public init() {}

    public func startStreaming(config: STTStreamConfig) async throws -> AsyncThrowingStream<STTEvent, Error> {
        LocalChunkedSTTStreamer.start(providerID: id, config: config) { url, fileConfig in
            try await transcribeFile(url: url, config: fileConfig)
        }
    }

    public func transcribeFile(url: URL, config: STTFileConfig) async throws -> [TranscriptSegment] {
        let segments = try await WhisperEngineRuntime.shared.transcribe(
            fileURL: url,
            locale: config.locale,
            providerID: id
        )
        guard !segments.isEmpty else {
            throw SayItError.unavailable("Whisper returned empty transcript")
        }
        return segments
    }
}

private final class WhisperEngineRuntime: @unchecked Sendable {
    static let shared = WhisperEngineRuntime()

    private let queue = DispatchQueue(label: "sayit.whisper.runtime")
    private var whisper: Whisper?
    private var loadedModelURL: URL?

    func transcribe(fileURL: URL, locale: String, providerID: String) async throws -> [TranscriptSegment] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: SayItError.unavailable("Whisper runtime unavailable"))
                    return
                }

                do {
                    let modelURL = try Self.resolveModelURL()
                    let engine = try self.loadEngine(modelURL: modelURL)
                    engine.params.language = Self.mapLocale(locale)
                    let audioFrames = Self.withLeadingSilencePadding(
                        try AudioPCM16Converter.loadMono16kFloatPCM(from: fileURL)
                    )
                    guard !audioFrames.isEmpty else {
                        continuation.resume(returning: [])
                        return
                    }

                    engine.transcribe(audioFrames: audioFrames) { result in
                        switch result {
                        case .success(let segments):
                            var output: [TranscriptSegment] = []
                            output.reserveCapacity(segments.count)
                            var sequence = 0
                            for segment in segments {
                                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !text.isEmpty else { continue }
                                output.append(
                                    TranscriptSegment(
                                        sessionID: UUID(),
                                        sequence: sequence,
                                        startMs: max(0, segment.startTime),
                                        endMs: max(segment.startTime, segment.endTime),
                                        rawText: text,
                                        finalText: text,
                                        provider: providerID,
                                        latencyMs: 10
                                    )
                                )
                                sequence += 1
                            }
                            continuation.resume(returning: output)
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func resolveModelURL() throws -> URL {
        let env = ProcessInfo.processInfo.environment
        if let override = env["SAYIT_WHISPER_MODEL_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            return URL(fileURLWithPath: override)
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let appSupport else {
            throw SayItError.unavailable("Failed to resolve Application Support directory for whisper model")
        }

        let modelFolder = appSupport
            .appendingPathComponent("SayIt", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("whisper", isDirectory: true)
        let fileManager = FileManager.default

        for candidate in Self.modelCandidatesInPriorityOrder {
            let candidateURL = modelFolder.appendingPathComponent(candidate)
            if fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        // Preserve a deterministic default path for first-run and clearer error output.
        return modelFolder.appendingPathComponent("ggml-base.bin")
    }

    private func loadEngine(modelURL: URL) throws -> Whisper {
        if let whisper, loadedModelURL == modelURL {
            return whisper
        }

        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw SayItError.unavailable(
                "Whisper model not found at \(modelURL.path). Download ggml-small.bin or ggml-base.bin in Settings > Local Models, or set SAYIT_WHISPER_MODEL_PATH."
            )
        }

        let params = WhisperParams(strategy: .beamSearch)
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.no_context = true
        params.suppress_blank = true
        params.suppress_non_speech_tokens = true
        params.temperature = 0
        params.temperature_inc = 0
        params.n_threads = Int32(max(2, ProcessInfo.processInfo.activeProcessorCount - 1))
        params.offset_ms = 0

        let whisper = Whisper(fromFileURL: modelURL, withParams: params)
        self.whisper = whisper
        self.loadedModelURL = modelURL
        return whisper
    }

    private static func mapLocale(_ locale: String) -> WhisperLanguage {
        if locale.hasPrefix("zh") {
            return .chinese
        }
        if locale.hasPrefix("ja") {
            return .japanese
        }
        if locale.hasPrefix("en") {
            return .english
        }
        let shortCode = locale.split(separator: "-").first.map(String.init) ?? locale
        return WhisperLanguage(rawValue: shortCode) ?? .auto
    }

    private static let modelCandidatesInPriorityOrder: [String] = [
        "ggml-medium.bin",
        "ggml-small.bin",
        "ggml-base.bin"
    ]

    private static func withLeadingSilencePadding(_ frames: [Float]) -> [Float] {
        guard !frames.isEmpty else { return frames }
        let silenceFrames = Int(16_000 * 0.25)
        return Array(repeating: 0, count: silenceFrames) + frames
    }
}
