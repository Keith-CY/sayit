import Foundation

public struct FallbackPolicy: Codable, Sendable {
    public var primarySTT: String
    public var localFallback: String
    public var retryCount: Int
    public var circuitBreakerThreshold: Int
    public var circuitBreakerWindowSec: Int

    public init(
        primarySTT: String = "openai",
        localFallback: String = "whisper",
        retryCount: Int = 1,
        circuitBreakerThreshold: Int = 3,
        circuitBreakerWindowSec: Int = 30
    ) {
        self.primarySTT = primarySTT
        self.localFallback = localFallback
        self.retryCount = retryCount
        self.circuitBreakerThreshold = circuitBreakerThreshold
        self.circuitBreakerWindowSec = circuitBreakerWindowSec
    }
}

public struct FallbackEvent: Codable, Sendable, Identifiable {
    public var id: UUID
    public var fromProvider: String
    public var toProvider: String
    public var reason: String
    public var statusCode: Int?
    public var latencyMs: Int
    public var timestamp: Date

    public init(
        id: UUID = UUID(),
        fromProvider: String,
        toProvider: String,
        reason: String,
        statusCode: Int? = nil,
        latencyMs: Int,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.fromProvider = fromProvider
        self.toProvider = toProvider
        self.reason = reason
        self.statusCode = statusCode
        self.latencyMs = latencyMs
        self.timestamp = timestamp
    }
}
