import Foundation
@testable import SayItCore
import XCTest

final class CodexOAuthParserTests: XCTestCase {
    func testExtractDeviceChallenge() throws {
        let raw = """
        \u{001B}[94mhttps://auth.openai.com/codex/device\u{001B}[0m
        \u{001B}[94m0D7J-00KTP\u{001B}[0m
        """

        let stripped = CodexOAuthParser.stripANSI(raw)
        let url = CodexOAuthParser.firstURL(in: stripped)
        let code = CodexOAuthParser.oneTimeCode(in: stripped)

        XCTAssertEqual(url?.absoluteString, "https://auth.openai.com/codex/device")
        XCTAssertEqual(code, "0D7J-00KTP")
    }

    func testParseStatus() {
        XCTAssertTrue(CodexOAuthParser.isLoggedInStatus("Logged in using ChatGPT"))
        XCTAssertFalse(CodexOAuthParser.isLoggedInStatus("Not logged in"))
    }

    func testParseISO8601() {
        let date = CodexOAuthParser.parseISO8601("2026-02-17T16:25:55.993956Z")
        XCTAssertNotNil(date)
    }
}
