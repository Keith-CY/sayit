import Foundation

public struct AppConfig: Codable, Sendable {
    public struct STTConfig: Codable, Sendable {
        public var primary: String
        public var localDefault: String

        public init(primary: String = "faster_whisper", localDefault: String = "faster_whisper") {
            self.primary = primary
            self.localDefault = localDefault
        }
    }

    public struct RefineConfig: Codable, Sendable {
        public var primary: String
        public var fallback: String

        public init(primary: String = "codex_oauth", fallback: String = "openai_api") {
            self.primary = primary
            self.fallback = fallback
        }
    }

    public struct TTSConfig: Codable, Sendable {
        public var primary: String
        public var fallback: String

        public init(primary: String = "openai_tts", fallback: String = "system_tts") {
            self.primary = primary
            self.fallback = fallback
        }
    }

    public struct ExportConfig: Codable, Sendable {
        public var formats: [String]

        public init(formats: [String] = ["txt", "md", "json"]) {
            self.formats = formats
        }
    }

    public struct PipelineConfig: Codable, Sendable {
        public var defaultID: UUID?

        public init(defaultID: UUID? = nil) {
            self.defaultID = defaultID
        }

        enum CodingKeys: String, CodingKey {
            case defaultID
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            defaultID = try container.decodeIfPresent(UUID.self, forKey: .defaultID)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let defaultID {
                try container.encode(defaultID, forKey: .defaultID)
            } else {
                try container.encodeNil(forKey: .defaultID)
            }
        }
    }

    public struct HotkeyConfig: Codable, Sendable {
        public var keyCode: UInt32
        public var modifiers: UInt32

        public init(keyCode: UInt32 = 49, modifiers: UInt32 = 768) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }
    }

    public var stt: STTConfig
    public var refine: RefineConfig
    public var tts: TTSConfig
    public var pipeline: PipelineConfig
    public var hotkey: HotkeyConfig
    public var locale: String
    public var export: ExportConfig
    public var fallbackPolicy: FallbackPolicy

    enum CodingKeys: String, CodingKey {
        case stt
        case refine
        case tts
        case pipeline
        case hotkey
        case locale
        case export
        case fallbackPolicy
    }

    public init(
        stt: STTConfig = .init(),
        refine: RefineConfig = .init(),
        tts: TTSConfig = .init(),
        pipeline: PipelineConfig = .init(),
        hotkey: HotkeyConfig = .init(),
        locale: String = "zh-Hans",
        export: ExportConfig = .init(),
        fallbackPolicy: FallbackPolicy = .init()
    ) {
        self.stt = stt
        self.refine = refine
        self.tts = tts
        self.pipeline = pipeline
        self.hotkey = hotkey
        self.locale = locale
        self.export = export
        self.fallbackPolicy = fallbackPolicy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stt = try container.decodeIfPresent(STTConfig.self, forKey: .stt) ?? .init()
        refine = try container.decodeIfPresent(RefineConfig.self, forKey: .refine) ?? .init()
        tts = try container.decodeIfPresent(TTSConfig.self, forKey: .tts) ?? .init()
        pipeline = try container.decodeIfPresent(PipelineConfig.self, forKey: .pipeline) ?? .init()
        hotkey = try container.decodeIfPresent(HotkeyConfig.self, forKey: .hotkey) ?? .init()
        locale = try container.decodeIfPresent(String.self, forKey: .locale) ?? "zh-Hans"
        export = try container.decodeIfPresent(ExportConfig.self, forKey: .export) ?? .init()
        fallbackPolicy = try container.decodeIfPresent(FallbackPolicy.self, forKey: .fallbackPolicy) ?? .init()
    }
}
