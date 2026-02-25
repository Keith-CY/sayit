import Foundation

public enum ExportFormat: String, Codable, CaseIterable, Sendable {
    case txt
    case md
    case json
}

public struct ExportRecord: Codable, Sendable, Identifiable {
    public var id: UUID
    public var sessionID: UUID
    public var format: ExportFormat
    public var path: String
    public var createdAt: Date

    public init(id: UUID = UUID(), sessionID: UUID, format: ExportFormat, path: String, createdAt: Date = Date()) {
        self.id = id
        self.sessionID = sessionID
        self.format = format
        self.path = path
        self.createdAt = createdAt
    }
}
