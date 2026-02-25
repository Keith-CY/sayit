import Foundation
@testable import SayItCore
import XCTest

final class PipelineStoreTests: XCTestCase {
    func testLoadSeedsDefaultsWhenMissing() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = base.appendingPathComponent("pipelines.json")
        let store = PipelineStore(url: url)

        let pipelines = try store.load()

        XCTAssertFalse(pipelines.isEmpty)
        XCTAssertEqual(pipelines.first?.id, DefaultPipelines.cleanID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testUpsertAndFind() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = base.appendingPathComponent("pipelines.json")
        let store = PipelineStore(url: url)
        _ = try store.load()

        let pipeline = TextPipeline(
            name: "Regex Demo",
            stages: [
                PipelineStage(type: .regexReplace, config: ["pattern": "foo", "replacement": "bar"])
            ]
        )

        try store.upsert(pipeline)

        let loaded = try store.find(id: pipeline.id)
        XCTAssertEqual(loaded?.name, "Regex Demo")
        XCTAssertEqual(loaded?.stages.first?.type, .regexReplace)
    }
}
