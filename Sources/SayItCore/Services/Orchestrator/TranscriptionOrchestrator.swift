import Foundation

public final class TranscriptionOrchestrator: @unchecked Sendable {
    private let primary: STTProvider
    private let localFallback: STTProvider
    private let fallbackStateMachine: FallbackStateMachine
    private let pipelineExecutor: PipelineExecutor
    private let repository: HistoryRepository

    public init(
        primary: STTProvider,
        localFallback: STTProvider,
        fallbackStateMachine: FallbackStateMachine,
        pipelineExecutor: PipelineExecutor,
        repository: HistoryRepository
    ) {
        self.primary = primary
        self.localFallback = localFallback
        self.fallbackStateMachine = fallbackStateMachine
        self.pipelineExecutor = pipelineExecutor
        self.repository = repository
    }

    public func transcribeFile(
        url: URL,
        session: TranscriptSession,
        config: STTFileConfig,
        pipeline: TextPipeline?
    ) async throws -> [TranscriptSegment] {
        try repository.createSession(session)

        let primary = self.primary
        let localFallback = self.localFallback
        let fileURL = url
        let fileConfig = config
        let (segments, fallbackEvent) = try await fallbackStateMachine.execute(
            primaryProvider: primary.id,
            fallbackProvider: localFallback.id,
            operation: {
                try await primary.transcribeFile(url: fileURL, config: fileConfig)
            },
            fallback: {
                try await localFallback.transcribeFile(url: fileURL, config: fileConfig)
            }
        )

        if let fallbackEvent {
            try repository.saveFallbackEvent(fallbackEvent)
        }

        var finalized: [TranscriptSegment] = []
        for (index, raw) in segments.enumerated() {
            let segmentID = raw.id
            var segment = raw
            segment.sessionID = session.id
            segment.sequence = index
            var pipelineRuns: [PipelineRunRecord] = []

            if let pipeline {
                let (text, runs) = try await pipelineExecutor.run(
                    text: segment.finalText,
                    pipeline: pipeline,
                    sessionID: session.id,
                    segmentID: segmentID,
                    locale: config.locale
                )
                segment.finalText = text
                pipelineRuns = runs
            }

            try repository.addSegment(segment)
            for run in pipelineRuns {
                try? repository.savePipelineRun(run)
            }
            finalized.append(segment)
        }

        return finalized
    }
}
