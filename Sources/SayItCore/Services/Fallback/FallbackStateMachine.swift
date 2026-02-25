import Foundation

public final class FallbackStateMachine {
    private let policy: FallbackPolicy
    private var failureCount: Int = 0
    private var circuitOpenUntil: Date?
    private let lock = NSLock()

    public init(policy: FallbackPolicy) {
        self.policy = policy
    }

    public func execute<T: Sendable>(
        primaryProvider: String,
        fallbackProvider: String,
        operation: @Sendable () async throws -> T,
        fallback: @Sendable () async throws -> T
    ) async throws -> (result: T, event: FallbackEvent?) {
        if isCircuitOpen() {
            let started = Date()
            let value = try await fallback()
            let latency = Int(Date().timeIntervalSince(started) * 1000)
            let event = FallbackEvent(
                fromProvider: primaryProvider,
                toProvider: fallbackProvider,
                reason: "circuit_open",
                latencyMs: latency
            )
            return (value, event)
        }

        let maxAttempts = max(1, policy.retryCount + 1)

        for attempt in 1...maxAttempts {
            do {
                let value = try await operation()
                resetFailures()
                return (value, nil)
            } catch {
                let category = classify(error)
                if !category.shouldFallback && attempt < maxAttempts {
                    continue
                }

                if category.shouldFallback {
                    recordFailure()
                    let started = Date()
                    let value = try await fallback()
                    let latency = Int(Date().timeIntervalSince(started) * 1000)
                    let event = FallbackEvent(
                        fromProvider: primaryProvider,
                        toProvider: fallbackProvider,
                        reason: category.reason,
                        statusCode: category.statusCode,
                        latencyMs: latency
                    )
                    return (value, event)
                }

                throw error
            }
        }

        throw SayItError.unavailable("All provider attempts exhausted")
    }

    public func forceOpenCircuit(for seconds: Int) {
        lock.lock()
        defer { lock.unlock() }
        circuitOpenUntil = Date().addingTimeInterval(TimeInterval(seconds))
    }

    public func currentFailureCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return failureCount
    }

    public func circuitState() -> (isOpen: Bool, until: Date?) {
        lock.lock()
        defer { lock.unlock() }
        return (isCircuitOpenLocked(), circuitOpenUntil)
    }

    private func isCircuitOpen() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCircuitOpenLocked()
    }

    private func isCircuitOpenLocked() -> Bool {
        guard let circuitOpenUntil else {
            return false
        }

        if Date() >= circuitOpenUntil {
            self.circuitOpenUntil = nil
            self.failureCount = 0
            return false
        }

        return true
    }

    private func recordFailure() {
        lock.lock()
        defer { lock.unlock() }
        failureCount += 1
        if failureCount >= policy.circuitBreakerThreshold {
            circuitOpenUntil = Date().addingTimeInterval(TimeInterval(policy.circuitBreakerWindowSec))
        }
    }

    private func resetFailures() {
        lock.lock()
        defer { lock.unlock() }
        failureCount = 0
        circuitOpenUntil = nil
    }

    private func classify(_ error: Error) -> (shouldFallback: Bool, reason: String, statusCode: Int?) {
        if let httpError = error as? ProviderHTTPError {
            switch httpError.statusCode {
            case 401:
                return (true, "auth_401", 401)
            case 429:
                return (true, "rate_limit", 429)
            case 500...599:
                return (true, "server_error", httpError.statusCode)
            default:
                return (false, "http_\(httpError.statusCode)", httpError.statusCode)
            }
        }

        if error is ProviderTimeoutError {
            return (true, "timeout", nil)
        }

        if let sayItError = error as? SayItError {
            switch sayItError {
            case .authentication:
                return (true, "auth_unavailable", nil)
            case .network:
                return (true, "network", nil)
            case .storage:
                return (true, "storage", nil)
            case .unavailable:
                return (true, "provider_unavailable", nil)
            default:
                return (false, "internal", nil)
            }
        }

        return (false, "unknown", nil)
    }
}
