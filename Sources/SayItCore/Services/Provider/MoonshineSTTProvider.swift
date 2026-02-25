import Foundation

public struct MoonshineSTTProvider: STTProvider {
    public let id = "moonshine"

    public init() {}

    public func startStreaming(config: STTStreamConfig) async throws -> AsyncThrowingStream<STTEvent, Error> {
        LocalChunkedSTTStreamer.start(providerID: id, config: config) { url, fileConfig in
            try await transcribeFile(url: url, config: fileConfig)
        }
    }

    public func transcribeFile(url: URL, config: STTFileConfig) async throws -> [TranscriptSegment] {
        do {
            let segments = try await ParakeetEngineRuntime.shared.transcribe(
                fileURL: url,
                locale: config.locale,
                providerID: id
            )
            if !segments.isEmpty {
                return segments
            }
        } catch {
            // Continue to whisper fallback.
        }

        let whisperFallback = WhisperSTTProvider()
        let segments = try await whisperFallback.transcribeFile(url: url, config: config)
        return segments.enumerated().map { index, raw in
            var segment = raw
            segment.sequence = index
            segment.provider = id
            return segment
        }
    }
}
