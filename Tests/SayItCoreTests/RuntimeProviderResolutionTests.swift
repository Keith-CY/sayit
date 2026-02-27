import Foundation
@testable import SayItCore
import XCTest

final class RuntimeProviderResolutionTests: XCTestCase {
    func testProviderResolution() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let runtime = try SayItCoreRuntime(
            configURL: tempDir.appendingPathComponent("config.json"),
            databaseURL: tempDir.appendingPathComponent("history.sqlite")
        )

        XCTAssertEqual(runtime.sttProvider(for: "openai").id, "faster_whisper")
        XCTAssertEqual(runtime.sttProvider(for: "whisper").id, "whisper")
        XCTAssertEqual(runtime.sttProvider(for: "faster_whisper").id, "faster_whisper")
        XCTAssertEqual(runtime.sttProvider(for: "parakeet").id, "parakeet")
        XCTAssertEqual(runtime.sttProvider(for: "moonshine").id, "moonshine")

        XCTAssertEqual(runtime.refineProvider(for: "codex_oauth").id, "codex_oauth")
        XCTAssertEqual(runtime.refineProvider(for: "openai_api").id, "openai_api")

        XCTAssertEqual(runtime.ttsProvider(for: "openai_tts").id, "openai_tts")
        XCTAssertEqual(runtime.ttsProvider(for: "system_tts").id, "system_tts")
    }
}
