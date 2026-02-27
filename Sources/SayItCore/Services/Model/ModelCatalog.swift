import Foundation

public enum LocalModelEngine: String, Codable, Sendable, CaseIterable {
    case whisper
    case parakeet
    case moonshine
}

public struct LocalModelDescriptor: Codable, Sendable, Identifiable {
    public var id: String { "\(engine.rawValue):\(name)" }
    public var engine: LocalModelEngine
    public var name: String
    public var remoteURL: URL
    public var sha256: String
    public var sizeBytes: Int64

    public init(engine: LocalModelEngine, name: String, remoteURL: URL, sha256: String, sizeBytes: Int64) {
        self.engine = engine
        self.name = name
        self.remoteURL = remoteURL
        self.sha256 = sha256
        self.sizeBytes = sizeBytes
    }
}

public enum ModelCatalog {
    public static func defaults() -> [LocalModelDescriptor] {
        []
    }
}
