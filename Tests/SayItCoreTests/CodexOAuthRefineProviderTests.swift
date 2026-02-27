import Foundation
@testable import SayItCore
import XCTest

final class CodexOAuthRefineProviderTests: XCTestCase {
    func testIngestSSELineParsesDeltaAndDone() throws {
        var state = CodexSSEParseState()

        try CodexOAuthRefineProvider.ingestSSELine(
            #"data: {"type":"response.output_text.delta","delta":"Hello"}"#,
            state: &state
        )
        try CodexOAuthRefineProvider.ingestSSELine(
            #"data: {"type":"response.output_text.delta","delta":" world"}"#,
            state: &state
        )
        try CodexOAuthRefineProvider.ingestSSELine(
            #"data: {"type":"response.output_text.done","text":"Hello world"}"#,
            state: &state
        )

        XCTAssertEqual(state.deltaText, "Hello world")
        XCTAssertEqual(state.doneText, "Hello world")
        XCTAssertFalse(state.didComplete)
        XCTAssertEqual(
            CodexOAuthRefineProvider.finalizedRefineText(from: state, fallback: "fallback"),
            "Hello world"
        )
    }

    func testIngestSSELineParsesCompletedEventText() throws {
        var state = CodexSSEParseState()
        let completedLine = #"data: {"type":"response.completed","response":{"output":[{"type":"reasoning","summary":[]},{"type":"message","content":[{"type":"output_text","text":"Completed text"}]}]}}"#

        try CodexOAuthRefineProvider.ingestSSELine(completedLine, state: &state)

        XCTAssertTrue(state.didComplete)
        XCTAssertEqual(state.completedText, "Completed text")
        XCTAssertEqual(
            CodexOAuthRefineProvider.finalizedRefineText(from: state, fallback: "fallback"),
            "Completed text"
        )
    }

    func testIngestSSELineThrowsOnErrorEvent() {
        var state = CodexSSEParseState()

        XCTAssertThrowsError(
            try CodexOAuthRefineProvider.ingestSSELine(
                #"data: {"type":"error","error":{"message":"bad token"}}"#,
                state: &state
            )
        ) { error in
            let message = "\(error)"
            XCTAssertTrue(message.contains("bad token"), "Expected error message to include payload detail")
        }
    }

    func testCredentialCacheReadsOnceUntilRefresh() async throws {
        let counter = LockedCounter()
        let cache = CodexAuthFileCredentialCache {
            let current = counter.incrementAndGet()
            return CodexAuthSnapshot(
                openAIAPIKey: nil,
                codexAccessToken: "token-\(current)",
                codexRefreshToken: nil,
                codexAccountID: "acc-1",
                sourcePath: "/tmp/auth.json"
            )
        }

        let first = try await cache.current()
        let second = try await cache.current()
        XCTAssertEqual(first.accessToken, second.accessToken)
        XCTAssertEqual(counter.value(), 1)

        let refreshed = try await cache.refresh()
        XCTAssertEqual(counter.value(), 2)
        XCTAssertNotEqual(refreshed.accessToken, first.accessToken)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private var count = 0
    private let lock = NSLock()

    func incrementAndGet() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    func value() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
