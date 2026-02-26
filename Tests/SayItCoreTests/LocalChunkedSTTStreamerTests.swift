import Foundation
@testable import SayItCore
import XCTest

final class LocalChunkedSTTStreamerTests: XCTestCase {
    func testResolvedChunkSecondsUsesDefaultAndBounds() {
        XCTAssertEqual(LocalChunkedSTTStreamer.resolvedChunkSeconds(environment: [:]), 2.5, accuracy: 0.001)
        XCTAssertEqual(
            LocalChunkedSTTStreamer.resolvedChunkSeconds(environment: ["SAYIT_LOCAL_STREAM_CHUNK_SEC": "0.1"]),
            1.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            LocalChunkedSTTStreamer.resolvedChunkSeconds(environment: ["SAYIT_LOCAL_STREAM_CHUNK_SEC": "20"]),
            10.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            LocalChunkedSTTStreamer.resolvedChunkSeconds(environment: ["SAYIT_LOCAL_STREAM_CHUNK_SEC": "3.2"]),
            3.2,
            accuracy: 0.001
        )
    }

    func testTranscribeChunkDetachesWhenCaptureAlreadyCancelled() async throws {
        let expected = TranscriptSegment(
            sessionID: UUID(),
            sequence: 0,
            startMs: 0,
            endMs: 1000,
            rawText: "hello",
            finalText: "hello",
            provider: "test",
            latencyMs: 1
        )

        let result = try await Task {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return try await LocalChunkedSTTStreamer.transcribeChunk(
                audioURL: URL(fileURLWithPath: "/tmp/unused.m4a"),
                locale: "en",
                cancelledAfterCapture: true
            ) { _, _ in
                if Task.isCancelled {
                    throw CancellationError()
                }
                return [expected]
            }
        }.value

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.finalText, "hello")
    }

    func testTranscribeChunkPropagatesCancellationWhenNotCancelledAfterCapture() async {
        let task = Task { () throws -> [TranscriptSegment] in
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
            return try await LocalChunkedSTTStreamer.transcribeChunk(
                audioURL: URL(fileURLWithPath: "/tmp/unused.m4a"),
                locale: "en",
                cancelledAfterCapture: false
            ) { _, _ in
                if Task.isCancelled {
                    throw CancellationError()
                }
                return []
            }
        }

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("Expected CancellationError but got \(error)")
        }
    }
}
