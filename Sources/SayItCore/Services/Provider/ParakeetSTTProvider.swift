import Foundation
import FluidAudio

extension AsrManager: @retroactive @unchecked Sendable {}

public struct ParakeetSTTProvider: STTProvider {
    public let id = "parakeet"

    public init() {}

    public func startStreaming(config: STTStreamConfig) async throws -> AsyncThrowingStream<STTEvent, Error> {
        LocalChunkedSTTStreamer.start(providerID: id, config: config) { url, fileConfig in
            try await transcribeFile(url: url, config: fileConfig)
        }
    }

    public func transcribeFile(url: URL, config: STTFileConfig) async throws -> [TranscriptSegment] {
        let segments = try await ParakeetEngineRuntime.shared.transcribe(
            fileURL: url,
            locale: config.locale,
            providerID: id
        )
        guard !segments.isEmpty else {
            throw SayItError.unavailable("Parakeet returned empty transcript")
        }
        return segments
    }
}

actor ParakeetEngineRuntime {
    static let shared = ParakeetEngineRuntime()

    private var manager: AsrManager?

    func transcribe(fileURL: URL, locale: String, providerID: String) async throws -> [TranscriptSegment] {
        let started = Date()
        let manager = try await ensureManager(locale: locale)

        let result: ASRResult
        do {
            result = try await manager.transcribe(fileURL, source: .system)
        } catch {
            throw SayItError.unavailable("Parakeet inference failed: \(error.localizedDescription)")
        }

        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        let durationMs = max(0, Int(result.duration * 1000))
        let latencyMs = max(1, Int(Date().timeIntervalSince(started) * 1000))
        return [
            TranscriptSegment(
                sessionID: UUID(),
                sequence: 0,
                startMs: 0,
                endMs: durationMs,
                rawText: text,
                finalText: text,
                provider: providerID,
                latencyMs: latencyMs
            )
        ]
    }

    private func ensureManager(locale: String) async throws -> AsrManager {
        if let manager {
            return manager
        }

        let version = modelVersion(for: locale)
        let models: AsrModels

        if let manualPath = Self.manualModelPath(), FileManager.default.fileExists(atPath: manualPath.path) {
            models = try await AsrModels.load(from: manualPath, version: version)
        } else {
            models = try await AsrModels.downloadAndLoad(version: version)
        }

        let manager = AsrManager(config: .default)
        try await manager.initialize(models: models)
        self.manager = manager
        return manager
    }

    private func modelVersion(for locale: String) -> AsrModelVersion {
        // v2 has better English recall; v3 offers multilingual coverage.
        locale.hasPrefix("en") ? .v2 : .v3
    }

    private static func manualModelPath() -> URL? {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["SAYIT_PARAKEET_COREML_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: raw)
    }
}
