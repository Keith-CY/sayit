import Foundation
@testable import SayItCore
import XCTest

final class FallbackStateMachineTests: XCTestCase {
    func testFallsBackOn401() async throws {
        let machine = FallbackStateMachine(policy: .init(retryCount: 0))
        let (value, event) = try await machine.execute(
            primaryProvider: "openai",
            fallbackProvider: "whisper",
            operation: {
                throw ProviderHTTPError(providerID: "openai", statusCode: 401, message: "unauthorized")
            },
            fallback: {
                "fallback"
            }
        )

        XCTAssertEqual(value, "fallback")
        XCTAssertEqual(event?.reason, "auth_401")
        XCTAssertEqual(machine.currentFailureCount(), 1)
    }

    func testFallsBackOn429() async throws {
        let machine = FallbackStateMachine(policy: .init(retryCount: 0))
        let (_, event) = try await machine.execute(
            primaryProvider: "openai",
            fallbackProvider: "whisper",
            operation: {
                throw ProviderHTTPError(providerID: "openai", statusCode: 429, message: "rate")
            },
            fallback: {
                "ok"
            }
        )

        XCTAssertEqual(event?.reason, "rate_limit")
    }

    func testFallsBackOnAuthenticationError() async throws {
        let machine = FallbackStateMachine(policy: .init(retryCount: 0))
        let (value, event) = try await machine.execute(
            primaryProvider: "openai",
            fallbackProvider: "whisper",
            operation: {
                throw SayItError.authentication("missing key")
            },
            fallback: {
                "local"
            }
        )

        XCTAssertEqual(value, "local")
        XCTAssertEqual(event?.reason, "auth_unavailable")
    }

    func testCircuitBreakerOpensAfterThreshold() async throws {
        let machine = FallbackStateMachine(
            policy: .init(retryCount: 0, circuitBreakerThreshold: 2, circuitBreakerWindowSec: 60)
        )

        _ = try await machine.execute(
            primaryProvider: "openai",
            fallbackProvider: "whisper",
            operation: { throw ProviderTimeoutError(providerID: "openai") },
            fallback: { "a" }
        )

        _ = try await machine.execute(
            primaryProvider: "openai",
            fallbackProvider: "whisper",
            operation: { throw ProviderTimeoutError(providerID: "openai") },
            fallback: { "b" }
        )

        let state = machine.circuitState()
        XCTAssertTrue(state.isOpen)
    }

    func testCircuitOpenSkipsPrimary() async throws {
        let machine = FallbackStateMachine(policy: .init(circuitBreakerWindowSec: 60))
        machine.forceOpenCircuit(for: 60)

        let (value, event) = try await machine.execute(
            primaryProvider: "openai",
            fallbackProvider: "whisper",
            operation: {
                return "primary"
            },
            fallback: {
                "fallback"
            }
        )

        XCTAssertEqual(value, "fallback")
        XCTAssertEqual(event?.reason, "circuit_open")
    }
}
