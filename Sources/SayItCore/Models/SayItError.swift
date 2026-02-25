import Foundation

public enum SayItError: Error, LocalizedError, Sendable {
    case notImplemented(String)
    case invalidConfiguration(String)
    case network(String)
    case authentication(String)
    case storage(String)
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case let .notImplemented(message):
            return "Not implemented: \(message)"
        case let .invalidConfiguration(message):
            return "Invalid configuration: \(message)"
        case let .network(message):
            return "Network error: \(message)"
        case let .authentication(message):
            return "Authentication error: \(message)"
        case let .storage(message):
            return "Storage error: \(message)"
        case let .unavailable(message):
            return "Unavailable: \(message)"
        }
    }
}
