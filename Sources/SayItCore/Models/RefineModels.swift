import Foundation

public struct RefineRequest: Codable, Sendable {
    public var sessionID: UUID?
    public var text: String
    public var context: String?
    public var locale: String
    public var pipelineID: UUID?

    public init(sessionID: UUID? = nil, text: String, context: String? = nil, locale: String = "zh-Hans", pipelineID: UUID? = nil) {
        self.sessionID = sessionID
        self.text = text
        self.context = context
        self.locale = locale
        self.pipelineID = pipelineID
    }
}

public struct RefineResult: Codable, Sendable {
    public var text: String
    public var provider: String
    public var latencyMs: Int
    public var metadata: [String: String]

    public init(text: String, provider: String, latencyMs: Int, metadata: [String: String] = [:]) {
        self.text = text
        self.provider = provider
        self.latencyMs = latencyMs
        self.metadata = metadata
    }
}
