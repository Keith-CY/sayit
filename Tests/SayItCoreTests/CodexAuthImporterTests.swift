import Foundation
@testable import SayItCore
import XCTest

final class CodexAuthImporterTests: XCTestCase {
    func testImportFromAuthFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let file = tempDir.appendingPathComponent("auth.json")

        let payload: [String: Any] = [
            "OPENAI_API_KEY": "sk-test",
            "tokens": [
                "access_token": "at-test",
                "refresh_token": "rt-test",
                "account_id": "acc-test",
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: file)

        let snapshot = try CodexAuthImporter.importFrom(path: file)
        XCTAssertEqual(snapshot.openAIAPIKey, "sk-test")
        XCTAssertEqual(snapshot.codexAccessToken, "at-test")
        XCTAssertEqual(snapshot.codexRefreshToken, "rt-test")
        XCTAssertEqual(snapshot.codexAccountID, "acc-test")
        XCTAssertEqual(snapshot.sourcePath, file.path)
    }
}
