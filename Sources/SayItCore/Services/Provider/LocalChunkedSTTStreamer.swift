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
                do {
                    while !Task.isCancelled {
                        let started = Date()
                        let audioURL = try await resources.capture.recordFor(seconds: chunkSeconds)
                        defer { try? FileManager.default.removeItem(at: audioURL) }

                        if config.archiveChunks {
                            _ = try? SessionChunkArchive.archiveChunk(audioURL, sessionID: config.sessionID)
                        }

                        let cancelledAfterCapture = Task.isCancelled
                        let segments: [TranscriptSegment]
                        do {
                            segments = try await transcribe(audioURL, STTFileConfig(locale: config.locale))
                            transientDecodeFailureCount = 0
                        } catch is CancellationError {
                            break
                        } catch {
                            if isTransientDecodeError(error) {
                                transientDecodeFailureCount += 1
                                if cancelledAfterCapture || Task.isCancelled {
                                    break
                                }
                                if transientDecodeFailureCount <= 2 {
                                    continue
                                }
                            }
                            throw error
                        }
                        for raw in segments {
                            var segment = raw
                            segment.sessionID = config.sessionID
                            segment.sequence = sequence
                            segment.provider = providerID
                            if segment.latencyMs <= 0 {
                                segment.latencyMs = Int(Date().timeIntervalSince(started) * 1000)
                            }
                            sequence += 1
                            continuation.yield(STTEvent(kind: .final, text: segment.finalText, segment: segment))
                        }

                        if cancelledAfterCapture || Task.isCancelled {
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

    private static func resolvedChunkSeconds() -> TimeInterval {
        let raw = ProcessInfo.processInfo.environment["SAYIT_LOCAL_STREAM_CHUNK_SEC"] ?? ""
        let value = Double(raw) ?? 4.0
        // Keep chunks practical: too short causes poor accuracy, too long hurts latency.
        return min(max(value, 1.0), 10.0)
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
