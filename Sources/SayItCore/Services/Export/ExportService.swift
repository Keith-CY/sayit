import Foundation

public final class ExportService: @unchecked Sendable {
    private let repository: HistoryRepository

    public init(repository: HistoryRepository) {
        self.repository = repository
    }

    public func export(sessionID: UUID, format: ExportFormat, to outputURL: URL) async throws -> ExportRecord {
        let segments = try repository.listSegments(sessionID: sessionID)
        let content = try buildContent(sessionID: sessionID, segments: segments, format: format)
        try content.write(to: outputURL, atomically: true, encoding: .utf8)

        let record = ExportRecord(sessionID: sessionID, format: format, path: outputURL.path)
        try repository.saveExportRecord(record)
        return record
    }

    private func buildContent(sessionID: UUID, segments: [TranscriptSegment], format: ExportFormat) throws -> String {
        switch format {
        case .txt:
            return segments.map(\.finalText).joined(separator: "\n")
        case .md:
            let lines = segments.map { "- [\($0.sequence)] \($0.finalText)" }
            return ["# Session \(sessionID.uuidString)", "", lines.joined(separator: "\n")].joined(separator: "\n")
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let payload = ExportPayload(sessionID: sessionID, segments: segments)
            let data = try encoder.encode(payload)
            guard let text = String(data: data, encoding: .utf8) else {
                throw SayItError.storage("Failed to encode json export")
            }
            return text
        }
    }
}

private struct ExportPayload: Codable {
    let sessionID: UUID
    let segments: [TranscriptSegment]
}
