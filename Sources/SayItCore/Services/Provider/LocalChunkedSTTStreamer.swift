import Foundation

enum LocalChunkedSTTStreamer {
    static func start(
        providerID: String,
        config: STTStreamConfig,
        transcribe: @escaping @Sendable (URL, STTFileConfig) async throws -> [TranscriptSegment]
    ) -> AsyncThrowingStream<STTEvent, Error> {
        let chunkSeconds = resolvedChunkSeconds()

        return AsyncThrowingStream { continuation in
            continuation.yield(STTEvent(kind: .started, text: ""))

            let resources = LocalStreamingResources()
            resources.task = Task {
                var sequence = 0
                var transientDecodeFailureCount = 0
                var pendingChunks: [PendingChunkTranscription] = []
                do {
                    while !Task.isCancelled {
                        let started = Date()
                        let audioURL = try await resources.capture.recordFor(seconds: chunkSeconds)

                        if config.archiveChunks {
                            _ = try? SessionChunkArchive.archiveChunk(audioURL, sessionID: config.sessionID)
                        }

                        let cancelledAfterCapture = Task.isCancelled
                        pendingChunks.append(
                            startChunkTranscription(
                                audioURL: audioURL,
                                locale: config.locale,
                                startedAt: started,
                                cancelledAfterCapture: cancelledAfterCapture,
                                transcribe: transcribe
                            )
                        )

                        // Keep one chunk in flight to overlap capture and decode with minimal audio gaps.
                        if pendingChunks.count > 1 {
                            let outcome = try await consumeNextPendingChunk(
                                pendingChunks: &pendingChunks,
                                providerID: providerID,
                                sessionID: config.sessionID,
                                sequence: &sequence,
                                transientDecodeFailureCount: &transientDecodeFailureCount,
                                continuation: continuation
                            )
                            if outcome == .stop {
                                break
                            }
                        }

                        if cancelledAfterCapture || Task.isCancelled {
                            break
                        }
                    }

                    while !pendingChunks.isEmpty {
                        let outcome = try await consumeNextPendingChunk(
                            pendingChunks: &pendingChunks,
                            providerID: providerID,
                            sessionID: config.sessionID,
                            sequence: &sequence,
                            transientDecodeFailureCount: &transientDecodeFailureCount,
                            continuation: continuation
                        )
                        if outcome == .stop {
                            break
                        }
                    }

                    continuation.yield(STTEvent(kind: .ended, text: ""))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.yield(STTEvent(kind: .ended, text: ""))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                resources.cancel()
            }
        }
    }

    static func resolvedChunkSeconds(environment: [String: String] = ProcessInfo.processInfo.environment) -> TimeInterval {
        let raw = environment["SAYIT_LOCAL_STREAM_CHUNK_SEC"] ?? ""
        let value = Double(raw) ?? 0.8
        // Keep chunks practical: too short causes poor accuracy, too long hurts latency.
        return min(max(value, 0.3), 10.0)
    }

    static func transcribeChunk(
        audioURL: URL,
        locale: String,
        cancelledAfterCapture: Bool,
        transcribe: @escaping @Sendable (URL, STTFileConfig) async throws -> [TranscriptSegment]
    ) async throws -> [TranscriptSegment] {
        let fileConfig = STTFileConfig(locale: locale)
        guard cancelledAfterCapture, Task.isCancelled else {
            return try await transcribe(audioURL, fileConfig)
        }

        // When stop is pressed right after capture, finish decoding this already-recorded chunk.
        return try await Task.detached(priority: .userInitiated) {
            try await transcribe(audioURL, fileConfig)
        }.value
    }

    private static func startChunkTranscription(
        audioURL: URL,
        locale: String,
        startedAt: Date,
        cancelledAfterCapture: Bool,
        transcribe: @escaping @Sendable (URL, STTFileConfig) async throws -> [TranscriptSegment]
    ) -> PendingChunkTranscription {
        let task = Task.detached(priority: .userInitiated) {
            defer { try? FileManager.default.removeItem(at: audioURL) }
            return try await transcribeChunk(
                audioURL: audioURL,
                locale: locale,
                cancelledAfterCapture: cancelledAfterCapture,
                transcribe: transcribe
            )
        }
        return PendingChunkTranscription(
            startedAt: startedAt,
            cancelledAfterCapture: cancelledAfterCapture,
            task: task
        )
    }

    private static func consumeNextPendingChunk(
        pendingChunks: inout [PendingChunkTranscription],
        providerID: String,
        sessionID: UUID,
        sequence: inout Int,
        transientDecodeFailureCount: inout Int,
        continuation: AsyncThrowingStream<STTEvent, Error>.Continuation
    ) async throws -> ChunkConsumeOutcome {
        let pending = pendingChunks.removeFirst()
        let segments: [TranscriptSegment]

        do {
            segments = try await pending.task.value
            transientDecodeFailureCount = 0
        } catch is CancellationError {
            return .stop
        } catch {
            if isTransientDecodeError(error) {
                transientDecodeFailureCount += 1
                if pending.cancelledAfterCapture {
                    return .stop
                }
                if transientDecodeFailureCount <= 2 {
                    return .continue
                }
            }
            throw error
        }

        for raw in segments {
            var segment = raw
            segment.sessionID = sessionID
            segment.sequence = sequence
            segment.provider = providerID
            if segment.latencyMs <= 0 {
                segment.latencyMs = Int(Date().timeIntervalSince(pending.startedAt) * 1000)
            }
            sequence += 1
            continuation.yield(STTEvent(kind: .final, text: segment.finalText, segment: segment))
        }

        if pending.cancelledAfterCapture {
            return .stop
        }
        return .continue
    }

    private static func isTransientDecodeError(_ error: Error) -> Bool {
        let message = "\(error) \(error.localizedDescription)".lowercased()
        return message.contains("whispererror error 1")
            || message.contains("whispererror error 2")
            || message.contains("instancebusy")
            || message.contains("cancelled")
    }
}

private final class LocalStreamingResources: @unchecked Sendable {
    let capture = AudioCaptureService()
    var task: Task<Void, Never>?

    func cancel() {
        task?.cancel()
        capture.stop()
    }
}

private struct PendingChunkTranscription: Sendable {
    let startedAt: Date
    let cancelledAfterCapture: Bool
    let task: Task<[TranscriptSegment], Error>
}

private enum ChunkConsumeOutcome {
    case `continue`
    case stop
}
