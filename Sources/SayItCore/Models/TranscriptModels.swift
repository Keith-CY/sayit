import Foundation

public struct STTStreamConfig: Codable, Sendable {
    public var sessionID: UUID
    public var sampleRate: Int
    public var channelCount: Int
    public var locale: String
    public var initialPrompt: String?
    public var archiveChunks: Bool

    public init(
        sessionID: UUID = UUID(),
        sampleRate: Int = 24_000,
        channelCount: Int = 1,
        locale: String = "zh-Hans",
        initialPrompt: String? = nil,
        archiveChunks: Bool = false
    ) {
        self.sessionID = sessionID
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.locale = locale
        self.initialPrompt = initialPrompt
        self.archiveChunks = archiveChunks
    }

    enum CodingKeys: String, CodingKey {
        case sessionID
        case sampleRate
        case channelCount
        case locale
        case initialPrompt
        case archiveChunks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decodeIfPresent(UUID.self, forKey: .sessionID) ?? UUID()
        sampleRate = try container.decodeIfPresent(Int.self, forKey: .sampleRate) ?? 24_000
        channelCount = try container.decodeIfPresent(Int.self, forKey: .channelCount) ?? 1
        locale = try container.decodeIfPresent(String.self, forKey: .locale) ?? "zh-Hans"
        initialPrompt = try container.decodeIfPresent(String.self, forKey: .initialPrompt)
        archiveChunks = try container.decodeIfPresent(Bool.self, forKey: .archiveChunks) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(sampleRate, forKey: .sampleRate)
        try container.encode(channelCount, forKey: .channelCount)
        try container.encode(locale, forKey: .locale)
        try container.encodeIfPresent(initialPrompt, forKey: .initialPrompt)
        try container.encode(archiveChunks, forKey: .archiveChunks)
    }
}

public struct STTFileConfig: Codable, Sendable {
    public var locale: String
    public var enablePunctuation: Bool
    public var initialPrompt: String?

    public init(locale: String = "zh-Hans", enablePunctuation: Bool = true, initialPrompt: String? = nil) {
        self.locale = locale
        self.enablePunctuation = enablePunctuation
        self.initialPrompt = initialPrompt
    }
}

public enum STTEventKind: String, Codable, Sendable {
    case started
    case partial
    case final
    case ended
}

public struct STTEvent: Codable, Sendable {
    public var kind: STTEventKind
    public var text: String
    public var segment: TranscriptSegment?
    public var timestamp: Date

    public init(kind: STTEventKind, text: String, segment: TranscriptSegment? = nil, timestamp: Date = Date()) {
        self.kind = kind
        self.text = text
        self.segment = segment
        self.timestamp = timestamp
    }
}

public struct TranscriptSession: Codable, Sendable {
    public var id: UUID
    public var source: String
    public var appBundleID: String?
    public var locale: String
    public var startedAt: Date
    public var endedAt: Date?

    public init(
        id: UUID = UUID(),
        source: String,
        appBundleID: String? = nil,
        locale: String = "zh-Hans",
        startedAt: Date = Date(),
        endedAt: Date? = nil
    ) {
        self.id = id
        self.source = source
        self.appBundleID = appBundleID
        self.locale = locale
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public struct SessionSummary: Codable, Sendable, Identifiable {
    public var session: TranscriptSession
    public var segmentCount: Int
    public var previewText: String?

    public var id: UUID { session.id }

    public init(session: TranscriptSession, segmentCount: Int, previewText: String?) {
        self.session = session
        self.segmentCount = segmentCount
        self.previewText = previewText
    }
}

public struct TranscriptSegment: Codable, Sendable, Identifiable {
    public var id: UUID
    public var sessionID: UUID
    public var sequence: Int
    public var startMs: Int
    public var endMs: Int
    public var rawText: String
    public var finalText: String
    public var provider: String
    public var latencyMs: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        sequence: Int,
        startMs: Int,
        endMs: Int,
        rawText: String,
        finalText: String,
        provider: String,
        latencyMs: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.sequence = sequence
        self.startMs = startMs
        self.endMs = endMs
        self.rawText = rawText
        self.finalText = finalText
        self.provider = provider
        self.latencyMs = latencyMs
        self.createdAt = createdAt
    }
}

public struct AudioAssetRecord: Codable, Sendable, Identifiable {
    public var id: UUID
    public var sessionID: UUID
    public var path: String
    public var durationMs: Int
    public var sampleRate: Int
    public var createdAt: Date

    public var fileName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        path: String,
        durationMs: Int,
        sampleRate: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.path = path
        self.durationMs = durationMs
        self.sampleRate = sampleRate
        self.createdAt = createdAt
    }
}
