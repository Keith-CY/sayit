import Foundation

public struct TextPipeline: Codable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var enabled: Bool
    public var stages: [PipelineStage]

    public init(id: UUID = UUID(), name: String, enabled: Bool = true, stages: [PipelineStage]) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.stages = stages
    }
}

public struct PipelineStage: Codable, Sendable, Identifiable {
    public var id: UUID
    public var type: PipelineStageType
    public var enabled: Bool
    public var config: [String: String]

    public init(id: UUID = UUID(), type: PipelineStageType, enabled: Bool = true, config: [String: String] = [:]) {
        self.id = id
        self.type = type
        self.enabled = enabled
        self.config = config
    }
}

public enum PipelineStageType: String, Codable, Sendable, CaseIterable {
    case smartPunctuation
    case fillerRemoval
    case whitespaceNormalize
    case regexReplace
    case templateApply
    case codeCommentTemplate
    case llmRewrite
}

public struct PipelineRunRecord: Codable, Sendable, Identifiable {
    public var id: UUID
    public var sessionID: UUID
    public var segmentID: UUID
    public var stageID: UUID
    public var stageType: PipelineStageType
    public var beforeText: String
    public var afterText: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        segmentID: UUID,
        stageID: UUID,
        stageType: PipelineStageType,
        beforeText: String,
        afterText: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.segmentID = segmentID
        self.stageID = stageID
        self.stageType = stageType
        self.beforeText = beforeText
        self.afterText = afterText
        self.createdAt = createdAt
    }
}
