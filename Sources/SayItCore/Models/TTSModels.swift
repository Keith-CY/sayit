import Foundation

public struct TTSRequest: Codable, Sendable {
    public var text: String
    public var voice: String
    public var locale: String
    public var speed: Double
    public var format: String

    public init(text: String, voice: String = "alloy", locale: String = "zh-Hans", speed: Double = 1.0, format: String = "mp3") {
        self.text = text
        self.voice = voice
        self.locale = locale
        self.speed = speed
        self.format = format
    }
}

public struct TTSAudio: Sendable {
    public var data: Data
    public var format: String
    public var durationMs: Int
    public var provider: String

    public init(data: Data, format: String, durationMs: Int, provider: String) {
        self.data = data
        self.format = format
        self.durationMs = durationMs
        self.provider = provider
    }
}
