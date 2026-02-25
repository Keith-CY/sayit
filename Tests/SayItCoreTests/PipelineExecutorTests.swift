import Foundation
@testable import SayItCore
import XCTest

private struct MockRefineProvider: RefineProvider {
    let id = "mock"

    func refine(_ request: RefineRequest) async throws -> RefineResult {
        RefineResult(text: request.text.uppercased(), provider: id, latencyMs: 1)
    }
}

final class PipelineExecutorTests: XCTestCase {
    func testFillerRemovalAndPunctuation() async throws {
        let executor = PipelineExecutor()
        let pipeline = TextPipeline(
            name: "clean",
            stages: [
                PipelineStage(type: .fillerRemoval),
                PipelineStage(type: .smartPunctuation)
            ]
        )

        let result = try await executor.run(
            text: "嗯 我们今天发布版本",
            pipeline: pipeline,
            sessionID: UUID(),
            segmentID: UUID(),
            locale: "zh-Hans"
        )

        XCTAssertFalse(result.text.contains("嗯"))
        XCTAssertTrue(result.text.hasSuffix("。"))
        XCTAssertEqual(result.runs.count, 2)
    }

    func testRegexReplace() async throws {
        let executor = PipelineExecutor()
        let pipeline = TextPipeline(
            name: "regex",
            stages: [
                PipelineStage(type: .regexReplace, config: ["pattern": "foo", "replacement": "bar"])
            ]
        )

        let result = try await executor.run(
            text: "foo baz",
            pipeline: pipeline,
            sessionID: UUID(),
            segmentID: UUID(),
            locale: "en"
        )

        XCTAssertEqual(result.text, "bar baz")
    }

    func testLLMRewriteStage() async throws {
        let executor = PipelineExecutor(refineProvider: MockRefineProvider())
        let pipeline = TextPipeline(
            name: "llm",
            stages: [
                PipelineStage(type: .llmRewrite)
            ]
        )

        let result = try await executor.run(
            text: "hello world",
            pipeline: pipeline,
            sessionID: UUID(),
            segmentID: UUID(),
            locale: "en"
        )

        XCTAssertEqual(result.text, "HELLO WORLD")
    }
}
