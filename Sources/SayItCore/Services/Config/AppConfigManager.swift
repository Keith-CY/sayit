import Foundation

public final class AppConfigManager {
    public static let configFileName = "config.json"
    private let configURL: URL

    public init(configURL: URL? = nil) {
        self.configURL = configURL ?? Self.defaultConfigURL()
    }

    public static func defaultConfigURL() -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("SayIt", isDirectory: true)
        return folder.appendingPathComponent(configFileName)
    }

    public func load() throws -> AppConfig {
        let fileManager = FileManager.default
        let folder = configURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        guard fileManager.fileExists(atPath: configURL.path) else {
            let config = AppConfig()
            try save(config)
            return config
        }

        let data = try Data(contentsOf: configURL)
        do {
            return try JSONDecoder.snakeCase.decode(AppConfig.self, from: data)
        } catch {
            let migrated = try migrateLegacyConfig(from: data)
            try save(migrated)
            return migrated
        }
    }

    public func save(_ config: AppConfig) throws {
        let fileManager = FileManager.default
        let folder = configURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let data = try JSONEncoder.pretty.encode(config)
        try data.write(to: configURL, options: .atomic)
    }

    public func path() -> URL {
        configURL
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var snakeCase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

private extension AppConfigManager {
    func migrateLegacyConfig(from data: Data) throws -> AppConfig {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SayItError.invalidConfiguration("Invalid config JSON format")
        }

        var config = AppConfig()

        if let stt = root.dictionary("stt") {
            config.stt.primary = stt.string("primary") ?? config.stt.primary
            config.stt.localDefault = stt.string("local_default") ?? stt.string("localDefault") ?? config.stt.localDefault
        }

        if let refine = root.dictionary("refine") {
            config.refine.primary = refine.string("primary") ?? config.refine.primary
            config.refine.fallback = refine.string("fallback") ?? config.refine.fallback
        }

        if let tts = root.dictionary("tts") {
            config.tts.primary = tts.string("primary") ?? config.tts.primary
            config.tts.fallback = tts.string("fallback") ?? config.tts.fallback
        }

        if let pipeline = root.dictionary("pipeline") {
            if let id = pipeline.string("default_id") ?? pipeline.string("defaultID"), let uuid = UUID(uuidString: id) {
                config.pipeline.defaultID = uuid
            }
        } else if let id = root.string("pipeline_default_id") ?? root.string("pipelineDefaultID"), let uuid = UUID(uuidString: id) {
            config.pipeline.defaultID = uuid
        }

        if let hotkey = root.dictionary("hotkey") {
            if let keyCode = hotkey.int("key_code") ?? hotkey.int("keyCode") {
                config.hotkey.keyCode = UInt32(keyCode)
            }
            if let modifiers = hotkey.int("modifiers") {
                config.hotkey.modifiers = UInt32(modifiers)
            }
        }

        config.locale = root.string("locale") ?? config.locale

        if let export = root.dictionary("export") {
            if let formats = export["formats"] as? [String], !formats.isEmpty {
                config.export.formats = formats
            }
        } else if let formats = root["export_formats"] as? [String], !formats.isEmpty {
            config.export.formats = formats
        }

        if let fallback = root.dictionary("fallback_policy") ?? root.dictionary("fallbackPolicy") {
            config.fallbackPolicy.primarySTT = fallback.string("primary_stt") ?? fallback.string("primarySTT") ?? config.fallbackPolicy.primarySTT
            config.fallbackPolicy.localFallback = fallback.string("local_fallback") ?? fallback.string("localFallback") ?? config.fallbackPolicy.localFallback
            config.fallbackPolicy.retryCount = fallback.int("retry_count") ?? fallback.int("retryCount") ?? config.fallbackPolicy.retryCount
            config.fallbackPolicy.circuitBreakerThreshold = fallback.int("circuit_breaker_threshold") ?? fallback.int("circuitBreakerThreshold") ?? config.fallbackPolicy.circuitBreakerThreshold
            config.fallbackPolicy.circuitBreakerWindowSec = fallback.int("circuit_breaker_window_sec") ?? fallback.int("circuitBreakerWindowSec") ?? config.fallbackPolicy.circuitBreakerWindowSec
        }

        return config
    }
}

private extension Dictionary where Key == String, Value == Any {
    func dictionary(_ key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }

    func string(_ key: String) -> String? {
        if let value = self[key] as? String {
            return value
        }
        if let value = self[key] as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    func int(_ key: String) -> Int? {
        if let value = self[key] as? Int {
            return value
        }
        if let value = self[key] as? NSNumber {
            return value.intValue
        }
        if let value = self[key] as? String {
            return Int(value)
        }
        return nil
    }
}
