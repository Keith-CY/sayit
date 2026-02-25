import Foundation

public protocol STTProvider: Sendable {
    var id: String { get }
    func startStreaming(config: STTStreamConfig) async throws -> AsyncThrowingStream<STTEvent, Error>
    func transcribeFile(url: URL, config: STTFileConfig) async throws -> [TranscriptSegment]
}
