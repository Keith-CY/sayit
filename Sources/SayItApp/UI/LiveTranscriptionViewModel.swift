import AppKit
@preconcurrency import AVFoundation
import Foundation
import SayItCore
import SwiftUI

@MainActor
final class LiveTranscriptionViewModel: ObservableObject {
    @Published var currentText: String = ""
    @Published var partialText: String = ""
    @Published var liveAudioLevel: CGFloat = 0
    @Published var liveAudioBands: [CGFloat] = Array(repeating: 0, count: 18)
    @Published var isRecording: Bool = false
    @Published var status: String = "Idle"
    @Published var activeSessionID: UUID?
    @Published var codexOAuthStatusLine: String = "Unknown"
    @Published var codexDeviceAuthURL: String = ""
    @Published var codexDeviceAuthCode: String = ""
    @Published var codexOAuthLogs: [String] = []
    @Published var codexOAuthInProgress: Bool = false
    @Published var codexOAuthOverlayVisible: Bool = false
    @Published var isProcessing: Bool = false
    @Published var processingCompletedUnits: Int = 0
    @Published var processingTotalUnits: Int = 0

    private let runtime: SayItCoreRuntime?
    private let onHistoryChanged: (() -> Void)?
    private let levelMonitor = MicrophoneLevelMonitor()
    private var streamTask: Task<Void, Never>?
    private var codexDeviceAuthTask: Task<Void, Never>?
    private var smoothedAudioLevel: CGFloat = 0
    private var smoothedAudioBands: [CGFloat] = Array(repeating: 0, count: 18)
    private var processingTaskCount = 0
    private lazy var playbackQueue = SpeechPlaybackQueue { [weak self] count in
        guard let self else { return }
        if count == 0, status.hasPrefix("Speaking") {
            status = "Idle"
        }
    }

    init(runtime: SayItCoreRuntime?, onHistoryChanged: (() -> Void)? = nil) {
        self.runtime = runtime
        self.onHistoryChanged = onHistoryChanged
    }

    deinit {
        codexDeviceAuthTask?.cancel()
    }

    var shouldShowCodexOAuthOverlay: Bool {
        codexOAuthOverlayVisible || codexOAuthInProgress
    }

    func startRecording() {
        guard !isRecording else { return }
        guard streamTask == nil else {
            status = "Previous session still finishing..."
            return
        }
        guard !isProcessing else {
            status = "Still processing previous audio..."
            return
        }
        streamTask = Task { [weak self] in
            guard let self else { return }
            await self.runStreaming()
        }
    }

    func stopRecording() {
        guard isRecording || streamTask != nil else { return }
        streamTask?.cancel()
        partialText = ""
        status = "Stopping..."
    }

    func toggleHotkeyCapture() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func clearText() {
        currentText = ""
        partialText = ""
        playbackQueue.clear()
    }

    func refineCurrentText() {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.runRefine(text: text)
        }
    }

    func speakCurrentText() {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.runTTS(text: text)
        }
    }

    func transcribeAudioFile(url: URL) {
        guard !isRecording else {
            status = "Stop live recording before transcribing file"
            return
        }

        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            await self.runFileTranscription(url: url)
        }
    }

    func startCodexOAuthLogin() {
        guard let runtime else {
            status = "Core runtime not available"
            return
        }
        guard codexDeviceAuthTask == nil else {
            status = "Codex login already running"
            return
        }

        codexOAuthOverlayVisible = true
        codexOAuthInProgress = true
        codexOAuthStatusLine = "Starting device auth..."
        codexDeviceAuthCode = ""
        codexDeviceAuthURL = ""
        codexOAuthLogs = []

        codexDeviceAuthTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = await runtime.codexOAuthManager.startDeviceAuthFlow()
                for try await event in stream {
                    if Task.isCancelled { break }
                    switch event {
                    case .output(let line):
                        appendOAuthLog(line)
                    case .challenge(let url, let code):
                        codexDeviceAuthURL = url.absoluteString
                        codexDeviceAuthCode = code
                        codexOAuthStatusLine = "Waiting for browser confirmation"
                    case .completed(let oauthStatus):
                        codexOAuthStatusLine = oauthStatus.statusLine
                        runtime.invalidateOpenAIAPIKeyCache()
                        try switchRefinePrimaryToCodex(runtime: runtime)
                        status = "Codex login complete; refine primary switched to codex_oauth"
                    }
                }
                codexOAuthInProgress = false
                codexDeviceAuthTask = nil
            } catch {
                codexOAuthInProgress = false
                codexDeviceAuthTask = nil
                codexOAuthStatusLine = "Login failed"
                status = "Codex login error: \(error.localizedDescription)"
            }
        }
    }

    func cancelCodexOAuthLogin() {
        codexDeviceAuthTask?.cancel()
        codexDeviceAuthTask = nil
        codexOAuthInProgress = false
        codexOAuthStatusLine = "Cancelled"
        guard let runtime else { return }
        Task {
            await runtime.codexOAuthManager.cancelActiveLogin()
        }
    }

    func dismissCodexOAuthOverlay() {
        codexOAuthOverlayVisible = false
    }

    func openCodexAuthURLInBrowser() {
        guard let url = URL(string: codexDeviceAuthURL), !codexDeviceAuthURL.isEmpty else { return }
        NSWorkspace.shared.open(url)
    }

    func copyCodexDeviceCode() {
        let value = codexDeviceAuthCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(value, forType: .string)
        status = "Device code copied"
    }

    func copyCodexAuthURL() {
        let value = codexDeviceAuthURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(value, forType: .string)
        status = "Auth URL copied"
    }

    func refreshCodexOAuthStatus() async {
        guard let runtime else {
            codexOAuthStatusLine = "Unavailable"
            return
        }

        do {
            let oauthStatus = try await runtime.codexOAuthManager.status()
            codexOAuthStatusLine = oauthStatus.statusLine
        } catch {
            codexOAuthStatusLine = "Status error: \(error.localizedDescription)"
        }
    }

    private func runStreaming() async {
        defer { streamTask = nil }
        guard let runtime else {
            status = "Core runtime not available"
            return
        }

        var primarySessionID: UUID?
        var fallbackTriggered = false
        var emittedFinalCount = 0
        var streamingSessionID: UUID?
        var streamingProvider: STTProvider?
        var streamingLocale = "zh-Hans"
        var streamingPipeline: TextPipeline?
        var streamingPipelineExecutor: PipelineExecutor?
        var streamingFinalSequence = 0
        var streamingSessionRecorder: SessionAudioRecorder?
        do {
            let config = try runtime.configManager.load()
            let primaryProvider = runtime.sttProvider(for: config.stt.primary)

            let session = TranscriptSession(source: "app_live_stream", locale: config.locale)
            let pipeline = resolveDefaultPipeline(runtime: runtime, config: config)
            let pipelineExecutor = PipelineExecutor(refineProvider: runtime.refineProvider(for: config.refine.primary))
            streamingSessionRecorder = shouldRecordSessionAudioInParallel(provider: primaryProvider) ? SessionAudioRecorder() : nil
            streamingSessionID = session.id
            streamingProvider = primaryProvider
            streamingLocale = config.locale
            streamingPipeline = pipeline
            streamingPipelineExecutor = pipelineExecutor
            activeSessionID = session.id
            isRecording = true
            status = "Starting..."
            partialText = ""

            try runtime.historyRepository.createSession(session)
            primarySessionID = session.id
            defer {
                if fallbackTriggered && emittedFinalCount == 0 {
                    SessionChunkArchive.clear(sessionID: session.id)
                    try? runtime.historyRepository.deleteSession(id: session.id)
                } else {
                    if let sessionAudioRecorder = streamingSessionRecorder {
                        persistLiveSessionAudioAsset(runtime: runtime, sessionID: session.id, recorder: sessionAudioRecorder)
                        SessionChunkArchive.clear(sessionID: session.id)
                    } else {
                        persistArchivedChunkAudioAssets(runtime: runtime, sessionID: session.id)
                    }
                    try? runtime.historyRepository.finishSession(id: session.id)
                }
                activeSessionID = nil
                isRecording = false
                stopLiveMetering()
                onHistoryChanged?()
            }

            if let sessionAudioRecorder = streamingSessionRecorder {
                do {
                    _ = try await sessionAudioRecorder.startRecording()
                } catch {
                    status = "Audio recording unavailable: \(error.localizedDescription)"
                }
            }

            var finalSequence = 0
            let stream = try await primaryProvider.startStreaming(
                config: STTStreamConfig(
                    sessionID: session.id,
                    sampleRate: 24_000,
                    channelCount: 1,
                    locale: config.locale,
                    archiveChunks: true
                )
            )
            await startLiveMetering()
            status = "Listening"

            for try await event in stream {
                switch event.kind {
                case .started:
                    status = "Streaming"
                case .partial:
                    partialText = event.text
                case .final:
                    partialText = ""
                    let normalizedFinal = event.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if normalizedFinal.isEmpty, event.segment == nil {
                        continue
                    }
                    let rawSegment = event.segment ?? TranscriptSegment(
                        sessionID: session.id,
                        sequence: finalSequence,
                        startMs: 0,
                        endMs: 0,
                        rawText: normalizedFinal,
                        finalText: normalizedFinal,
                        provider: primaryProvider.id,
                        latencyMs: 0
                    )

                    let rawFinal = rawSegment.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if rawFinal.isEmpty {
                        continue
                    }
                    let segment = try await persistSegment(
                        runtime: runtime,
                        raw: rawSegment,
                        sessionID: session.id,
                        sequence: finalSequence,
                        locale: config.locale,
                        pipeline: pipeline,
                        pipelineExecutor: pipelineExecutor
                    )
                    let renderedText = segment.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !renderedText.isEmpty else { continue }
                    finalSequence += 1
                    emittedFinalCount += 1
                    appendText(renderedText)
                case .ended:
                    break
                }
            }

            if emittedFinalCount == 0 {
                status = "Processing captured audio..."
                if let sessionAudioRecorder = streamingSessionRecorder {
                    let recovered = try await withProcessing {
                        try await recoverTranscriptFromSessionRecording(
                            runtime: runtime,
                            sessionID: session.id,
                            recorder: sessionAudioRecorder,
                            provider: primaryProvider,
                            locale: config.locale,
                            pipeline: pipeline,
                            pipelineExecutor: pipelineExecutor,
                            startSequence: finalSequence
                        )
                    }
                    emittedFinalCount += recovered
                    finalSequence += recovered
                    if recovered > 0 {
                        streamingSessionRecorder = nil
                    }
                } else {
                    let recovered = try await withProcessing {
                        try await recoverTranscriptFromArchivedChunks(
                            runtime: runtime,
                            sessionID: session.id,
                            provider: primaryProvider,
                            locale: config.locale,
                            pipeline: pipeline,
                            pipelineExecutor: pipelineExecutor,
                            startSequence: finalSequence
                        )
                    }
                    emittedFinalCount += recovered
                    finalSequence += recovered
                }
            }

            streamingFinalSequence = finalSequence
            let cancelled = Task.isCancelled
            if cancelled && emittedFinalCount == 0 {
                status = "Stopped"
                return
            }
            guard emittedFinalCount > 0 else {
                status = "No speech recognized (\(primaryProvider.id))"
                return
            }
            status = "Saved to history (\(primaryProvider.id))"
        } catch is CancellationError {
            if emittedFinalCount == 0,
               let sessionID = streamingSessionID,
               let provider = streamingProvider,
               let pipelineExecutor = streamingPipelineExecutor
            {
                var recovered = 0
                var recoveryError: Error?
                status = "Processing captured audio..."
                if let sessionAudioRecorder = streamingSessionRecorder {
                    do {
                        recovered = try await withProcessing {
                            try await recoverTranscriptFromSessionRecording(
                                runtime: runtime,
                                sessionID: sessionID,
                                recorder: sessionAudioRecorder,
                                provider: provider,
                                locale: streamingLocale,
                                pipeline: streamingPipeline,
                                pipelineExecutor: pipelineExecutor,
                                startSequence: streamingFinalSequence
                            )
                        }
                    } catch {
                        recoveryError = error
                        recovered = 0
                    }
                    if recovered > 0 {
                        streamingSessionRecorder = nil
                    }
                }
                if recovered == 0 {
                    do {
                        recovered = try await withProcessing {
                            try await recoverTranscriptFromSavedSessionAudio(
                                runtime: runtime,
                                sessionID: sessionID,
                                provider: provider,
                                locale: streamingLocale,
                                pipeline: streamingPipeline,
                                pipelineExecutor: pipelineExecutor,
                                startSequence: streamingFinalSequence
                            )
                        }
                    } catch {
                        if recoveryError == nil {
                            recoveryError = error
                        }
                        recovered = 0
                    }
                }
                if recovered == 0 {
                    do {
                        recovered = try await withProcessing {
                            try await recoverTranscriptFromArchivedChunks(
                                runtime: runtime,
                                sessionID: sessionID,
                                provider: provider,
                                locale: streamingLocale,
                                pipeline: streamingPipeline,
                                pipelineExecutor: pipelineExecutor,
                                startSequence: streamingFinalSequence
                            )
                        }
                    } catch {
                        if recoveryError == nil {
                            recoveryError = error
                        }
                        recovered = 0
                    }
                }
                if recovered > 0 {
                    status = "Saved to history (\(provider.id))"
                    return
                }
                if let recoveryError {
                    status = "Processing failed (\(provider.id)): \(recoveryError.localizedDescription)"
                    return
                }
            }
            if emittedFinalCount > 0, let provider = streamingProvider {
                status = "Saved to history (\(provider.id))"
            } else if let provider = streamingProvider {
                status = "No speech recognized (\(provider.id))"
            } else {
                status = "Stopped"
            }
        } catch {
            let reason = fallbackReason(for: error)
            if shouldAutoFallbackInLive() && shouldFallbackAfterPrimaryFailure(reason: reason) {
                status = fallbackStatusMessage(reason: reason)
                fallbackTriggered = true
                await runFallbackCapture(reason: reason)
                if emittedFinalCount == 0, let primarySessionID {
                    SessionChunkArchive.clear(sessionID: primarySessionID)
                    try? runtime.historyRepository.deleteSession(id: primarySessionID)
                    onHistoryChanged?()
                }
            } else {
                status = "Primary STT failed (\(reason)): \(error.localizedDescription)"
            }
        }
    }

    private func runFallbackCapture(reason: String) async {
        guard let runtime else {
            status = "Fallback unavailable"
            isRecording = false
            return
        }
        do {
            let config = try runtime.configManager.load()
            let fallbackID = config.stt.localDefault
            let provider = localProvider(runtime: runtime, id: fallbackID)
            let session = TranscriptSession(source: "app_fallback_capture", locale: config.locale)
            let pipeline = resolveDefaultPipeline(runtime: runtime, config: config)
            let pipelineExecutor = PipelineExecutor(refineProvider: runtime.refineProvider(for: config.refine.primary))
            let sessionAudioRecorder = SessionAudioRecorder()

            activeSessionID = session.id
            isRecording = true
            await startLiveMetering()
            status = "Fallback recording (\(provider.id))"
            partialText = ""

            try runtime.historyRepository.createSession(session)
            defer {
                try? runtime.historyRepository.finishSession(id: session.id)
                activeSessionID = nil
                isRecording = false
                stopLiveMetering()
                onHistoryChanged?()
            }

            try runtime.historyRepository.saveFallbackEvent(
                FallbackEvent(
                    fromProvider: runtime.primarySTTProvider.id,
                    toProvider: fallbackID,
                    reason: reason,
                    latencyMs: 0
                )
            )

            _ = try await sessionAudioRecorder.startRecording()
            while true {
                do {
                    try await Task.sleep(nanoseconds: 100_000_000)
                } catch is CancellationError {
                    break
                }
            }

            status = "Fallback transcribing (\(provider.id))"
            guard let tempURL = sessionAudioRecorder.stopRecording() else {
                status = "No audio captured by fallback (\(provider.id))"
                return
            }
            defer { try? FileManager.default.removeItem(at: tempURL) }

            do {
                let audioAsset = try runtime.audioAssetStore.importFile(tempURL, sessionID: session.id)
                try runtime.historyRepository.saveAudioAsset(audioAsset)
            } catch {
                // Preserve transcript path even if audio persistence fails.
            }

            let fallbackAudioUnits = progressUnitsForAudioFile(tempURL)
            startProcessingProgress(totalUnits: fallbackAudioUnits)
            let recoveredSegments = try await withProcessing {
                try await transcribeWithRetry(provider: provider, url: tempURL, locale: config.locale)
            }
            advanceProcessingProgress(by: fallbackAudioUnits)
            var savedCount = 0
            var sequence = 0
            for raw in recoveredSegments {
                let normalized = raw.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                if normalized.isEmpty {
                    continue
                }
                let segment = try await persistSegment(
                    runtime: runtime,
                    raw: raw,
                    sessionID: session.id,
                    sequence: sequence,
                    locale: config.locale,
                    pipeline: pipeline,
                    pipelineExecutor: pipelineExecutor
                )
                let rendered = segment.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rendered.isEmpty else { continue }
                appendText(rendered)
                sequence += 1
                savedCount += 1
            }

            if savedCount == 0 {
                status = "No speech recognized by fallback (\(provider.id))"
            } else {
                status = "Saved with fallback (\(provider.id))"
            }
        } catch {
            status = "Error: \(error.localizedDescription)"
            isRecording = false
        }
    }

    private func runFileTranscription(url: URL) async {
        defer { streamTask = nil }
        beginProcessing()
        defer { endProcessing() }

        guard let runtime else {
            status = "Core runtime not available"
            return
        }

        do {
            let config = try runtime.configManager.load()
            let session = TranscriptSession(source: "app_file_transcribe", locale: config.locale)
            let primary = runtime.sttProvider(for: config.stt.primary)
            let fallbackID = config.fallbackPolicy.localFallback.isEmpty ? config.stt.localDefault : config.fallbackPolicy.localFallback
            let localFallback = runtime.sttProvider(for: fallbackID)
            let stateMachine = FallbackStateMachine(policy: config.fallbackPolicy)
            let pipelineExecutor = PipelineExecutor(refineProvider: runtime.refineProvider(for: config.refine.primary))
            let pipeline = resolveDefaultPipeline(runtime: runtime, config: config)

            activeSessionID = session.id
            status = "Transcribing file"
            partialText = ""
            currentText = ""
            let fileAudioUnits = progressUnitsForAudioFile(url)
            startProcessingProgress(totalUnits: fileAudioUnits)

            try runtime.historyRepository.createSession(session)
            defer {
                try? runtime.historyRepository.finishSession(id: session.id)
                activeSessionID = nil
                onHistoryChanged?()
            }

            do {
                let audioAsset = try runtime.audioAssetStore.importFile(url, sessionID: session.id)
                try runtime.historyRepository.saveAudioAsset(audioAsset)
            } catch {
                status = "Audio asset import skipped: \(error.localizedDescription)"
            }

            let (segments, fallbackEvent) = try await stateMachine.execute(
                primaryProvider: primary.id,
                fallbackProvider: localFallback.id,
                operation: {
                    try await primary.transcribeFile(url: url, config: STTFileConfig(locale: config.locale))
                },
                fallback: {
                    try await localFallback.transcribeFile(url: url, config: STTFileConfig(locale: config.locale))
                }
            )
            advanceProcessingProgress(by: fileAudioUnits)

            if let fallbackEvent {
                try runtime.historyRepository.saveFallbackEvent(fallbackEvent)
            }

            var savedCount = 0
            var nextSequence = 0
            for raw in segments {
                let normalized = raw.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                if normalized.isEmpty {
                    continue
                }
                let segment = try await persistSegment(
                    runtime: runtime,
                    raw: raw,
                    sessionID: session.id,
                    sequence: nextSequence,
                    locale: config.locale,
                    pipeline: pipeline,
                    pipelineExecutor: pipelineExecutor
                )
                let renderedText = segment.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !renderedText.isEmpty else { continue }
                nextSequence += 1
                savedCount += 1
                appendText(renderedText)
            }

            if savedCount == 0 {
                status = "No speech recognized in file"
                return
            }

            if let fallbackEvent {
                status = "File saved (fallback: \(fallbackEvent.toProvider))"
            } else {
                status = "File saved (\(primary.id))"
            }
        } catch is CancellationError {
            status = "Stopped"
        } catch {
            status = "File transcribe error: \(error.localizedDescription)"
        }
    }

    private func runRefine(text: String) async {
        beginProcessing()
        defer { endProcessing() }

        guard let runtime else {
            status = "Refine unavailable"
            return
        }

        do {
            let config = try runtime.configManager.load()
            let request = RefineRequest(sessionID: activeSessionID, text: text, locale: config.locale)
            let primary = runtime.refineProvider(for: config.refine.primary)
            let fallback = primary.id == runtime.openAIRefineProvider.id ? runtime.codexRefineProvider : runtime.openAIRefineProvider

            do {
                let result = try await primary.refine(request)
                currentText = result.text
                status = "Refined by \(result.provider)"
            } catch {
                if primary.id == runtime.codexRefineProvider.id {
                    if case SayItError.authentication = error {
                        startCodexOAuthLogin()
                    }
                }
                let result = try await fallback.refine(request)
                currentText = result.text
                status = "Refined by fallback \(result.provider)"
            }
        } catch {
            status = "Refine error: \(error.localizedDescription)"
        }
    }

    private func runTTS(text: String) async {
        beginProcessing()
        defer { endProcessing() }

        guard let runtime else {
            status = "TTS unavailable"
            return
        }

        do {
            let config = try runtime.configManager.load()
            let request = TTSRequest(text: text, locale: config.locale, format: "mp3")
            let primary = runtime.ttsProvider(for: config.tts.primary)
            let fallback = primary.id == runtime.systemTTSProvider.id ? runtime.openAITTSProvider : runtime.systemTTSProvider
            do {
                let audio = try await primary.synthesize(request)
                try playbackQueue.enqueue(audio)
                status = "Speaking (\(audio.provider)) queue=\(playbackQueue.pendingCount)"
            } catch {
                let fallbackRequest = fallback.id == runtime.systemTTSProvider.id
                    ? TTSRequest(text: text, locale: config.locale, format: "aiff")
                    : request
                let fallbackAudio = try await fallback.synthesize(fallbackRequest)
                try playbackQueue.enqueue(fallbackAudio)
                status = "Speaking (\(fallbackAudio.provider)) queue=\(playbackQueue.pendingCount)"
            }
        } catch {
            status = "TTS error: \(error.localizedDescription)"
        }
    }

    private func localProvider(runtime: SayItCoreRuntime, id: String) -> STTProvider {
        runtime.sttProvider(for: id)
    }

    var hasDeterminateProcessingProgress: Bool {
        processingTotalUnits > 0
    }

    var processingProgressFraction: Double {
        guard processingTotalUnits > 0 else { return 0 }
        return min(1, max(0, Double(processingCompletedUnits) / Double(processingTotalUnits)))
    }

    var processingProgressPercentText: String {
        guard processingTotalUnits > 0 else { return "" }
        let percent = Int((processingProgressFraction * 100).rounded())
        let completedSeconds = Double(processingCompletedUnits) / 1000
        let totalSeconds = Double(processingTotalUnits) / 1000
        return String(format: "%d%% (%.1fs/%.1fs)", percent, completedSeconds, totalSeconds)
    }

    private func beginProcessing() {
        processingTaskCount += 1
        isProcessing = true
    }

    private func endProcessing() {
        processingTaskCount = max(0, processingTaskCount - 1)
        isProcessing = processingTaskCount > 0
        if !isProcessing {
            resetProcessingProgress()
        }
    }

    private func withProcessing<T>(
        _ operation: () async throws -> T
    ) async rethrows -> T {
        beginProcessing()
        defer { endProcessing() }
        return try await operation()
    }

    private func startProcessingProgress(totalUnits: Int) {
        let total = max(1, totalUnits)
        withAnimation(.easeInOut(duration: 0.18)) {
            processingTotalUnits = total
            processingCompletedUnits = 0
        }
    }

    private func advanceProcessingProgress(by units: Int = 1) {
        guard processingTotalUnits > 0 else { return }
        let step = max(1, units)
        withAnimation(.easeInOut(duration: 0.16)) {
            processingCompletedUnits = min(processingTotalUnits, processingCompletedUnits + step)
        }
    }

    private func resetProcessingProgress() {
        processingCompletedUnits = 0
        processingTotalUnits = 0
    }

    private func progressUnitsForAudioFile(_ fileURL: URL) -> Int {
        let durationMs = measuredAudioDurationMs(for: fileURL)
        if durationMs > 0 {
            return durationMs
        }
        // Keep determinate progress even when metadata read fails.
        return 1_000
    }

    private func measuredAudioDurationMs(for fileURL: URL) -> Int {
        guard let file = try? AVAudioFile(forReading: fileURL) else {
            return 0
        }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return 0 }
        let seconds = Double(file.length) / sampleRate
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(seconds * 1000)
    }

    private func fallbackReason(for error: Error) -> String {
        if let httpError = error as? ProviderHTTPError {
            switch httpError.statusCode {
            case 401:
                return "auth_401"
            case 429:
                return "rate_limit"
            case 500...599:
                return "server_error"
            default:
                return "http_\(httpError.statusCode)"
            }
        }

        if error is ProviderTimeoutError {
            return "timeout"
        }

        if let sayItError = error as? SayItError {
            switch sayItError {
            case .authentication:
                return "auth_unavailable"
            case .network:
                return "network"
            case .storage:
                return "storage"
            case .unavailable:
                return "provider_unavailable"
            default:
                return "internal"
            }
        }

        return "stream_failed"
    }

    private func fallbackStatusMessage(reason: String) -> String {
        switch reason {
        case "auth_unavailable", "auth_401":
            return "Primary STT auth unavailable, switching to local fallback"
        case "rate_limit":
            return "Primary STT quota reached, switching to local fallback"
        case "timeout", "network":
            return "Primary STT network timeout, switching to local fallback"
        default:
            return "Primary STT unavailable, switching to local fallback"
        }
    }

    private func shouldFallbackAfterPrimaryFailure(reason: String) -> Bool {
        switch reason {
        case "rate_limit", "timeout", "network", "server_error", "provider_unavailable", "storage":
            return true
        default:
            // Surface auth/client failures directly so OpenAI capability checks are explicit.
            return false
        }
    }

    private func shouldAutoFallbackInLive() -> Bool {
        let raw = ProcessInfo.processInfo.environment["SAYIT_LIVE_AUTO_FALLBACK"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return raw == "1" || raw == "true" || raw == "yes" || raw == "on"
    }

    private func appendText(_ text: String) {
        guard !text.isEmpty else { return }
        if currentText.isEmpty {
            currentText = text
        } else {
            currentText += "\n" + text
        }
    }

    private func startLiveMetering() async {
        smoothedAudioLevel = 0
        smoothedAudioBands = Array(repeating: 0, count: 18)
        liveAudioLevel = 0
        liveAudioBands = Array(repeating: 0, count: 18)
        do {
            try await levelMonitor.start { [weak self] signal in
                guard let self else { return }
                let raw = CGFloat(signal.level)
                let smoothed = (self.smoothedAudioLevel * 0.76) + (raw * 0.24)
                self.smoothedAudioLevel = smoothed
                self.liveAudioLevel = min(max(smoothed, 0), 1)

                if self.smoothedAudioBands.count != signal.bands.count {
                    self.smoothedAudioBands = Array(repeating: 0, count: signal.bands.count)
                }
                for index in 0..<self.smoothedAudioBands.count {
                    let rawBand = CGFloat(signal.bands[index])
                    let previous = self.smoothedAudioBands[index]
                    let smoothing: CGFloat = rawBand > previous ? 0.45 : 0.22
                    self.smoothedAudioBands[index] = previous * (1 - smoothing) + rawBand * smoothing
                }
                self.liveAudioBands = self.smoothedAudioBands
            }
        } catch {
            // Metering is best effort and should never break transcription.
            liveAudioLevel = 0
            liveAudioBands = Array(repeating: 0, count: 18)
        }
    }

    private func stopLiveMetering() {
        levelMonitor.stop()
        smoothedAudioLevel = 0
        smoothedAudioBands = Array(repeating: 0, count: 18)
        liveAudioLevel = 0
        liveAudioBands = Array(repeating: 0, count: 18)
    }

    private func resolveDefaultPipeline(runtime: SayItCoreRuntime, config: AppConfig) -> TextPipeline? {
        let pipelines = (try? runtime.pipelineStore.load()) ?? DefaultPipelines.all()
        guard !pipelines.isEmpty else { return nil }
        if let id = config.pipeline.defaultID, let selected = pipelines.first(where: { $0.id == id }) {
            return selected
        }
        return pipelines.first
    }

    private func persistSegment(
        runtime: SayItCoreRuntime,
        raw: TranscriptSegment,
        sessionID: UUID,
        sequence: Int,
        locale: String,
        pipeline: TextPipeline?,
        pipelineExecutor: PipelineExecutor
    ) async throws -> TranscriptSegment {
        let segmentID = raw.id
        var segment = raw
        segment.sessionID = sessionID
        segment.sequence = sequence
        var pipelineRuns: [PipelineRunRecord] = []

        if let pipeline {
            do {
                let (processedText, runs) = try await pipelineExecutor.run(
                    text: segment.finalText,
                    pipeline: pipeline,
                    sessionID: sessionID,
                    segmentID: segmentID,
                    locale: locale
                )
                let normalizedProcessed = processedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if normalizedProcessed.isEmpty {
                    // Never lose recognized content completely due to aggressive cleanup stages.
                    segment.finalText = segment.rawText
                } else {
                    segment.finalText = processedText
                }
                pipelineRuns = runs
            } catch {
                status = "Pipeline skipped: \(error.localizedDescription)"
            }
        }

        try runtime.historyRepository.addSegment(segment)
        for run in pipelineRuns {
            do {
                try runtime.historyRepository.savePipelineRun(run)
            } catch {
                status = "Pipeline run skipped: \(error.localizedDescription)"
            }
        }
        return segment
    }

    private func recoverTranscriptFromSessionRecording(
        runtime: SayItCoreRuntime,
        sessionID: UUID,
        recorder: SessionAudioRecorder,
        provider: STTProvider,
        locale: String,
        pipeline: TextPipeline?,
        pipelineExecutor: PipelineExecutor,
        startSequence: Int
    ) async throws -> Int {
        guard let tempURL = recorder.stopRecording() else { return 0 }
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let totalUnits = progressUnitsForAudioFile(tempURL)
        startProcessingProgress(totalUnits: totalUnits)

        do {
            let audioAsset = try runtime.audioAssetStore.importFile(tempURL, sessionID: sessionID)
            try runtime.historyRepository.saveAudioAsset(audioAsset)
        } catch {
            // Recovery transcription should continue even if asset persistence fails.
        }

        let recoveredSegments = try await transcribeWithRetry(provider: provider, url: tempURL, locale: locale)
        advanceProcessingProgress(by: totalUnits)
        var recoveredCount = 0
        var nextSequence = startSequence
        for raw in recoveredSegments {
            let normalized = raw.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized.isEmpty {
                continue
            }
            let segment = try await persistSegment(
                runtime: runtime,
                raw: raw,
                sessionID: sessionID,
                sequence: nextSequence,
                locale: locale,
                pipeline: pipeline,
                pipelineExecutor: pipelineExecutor
            )
            let rendered = segment.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rendered.isEmpty else { continue }
            appendText(rendered)
            nextSequence += 1
            recoveredCount += 1
        }
        return recoveredCount
    }

    private func recoverTranscriptFromArchivedChunks(
        runtime: SayItCoreRuntime,
        sessionID: UUID,
        provider: STTProvider,
        locale: String,
        pipeline: TextPipeline?,
        pipelineExecutor: PipelineExecutor,
        startSequence: Int
    ) async throws -> Int {
        let chunkURLs = SessionChunkArchive.listChunks(sessionID: sessionID)
        guard !chunkURLs.isEmpty else { return 0 }
        let existingChunks = chunkURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existingChunks.isEmpty else { return 0 }
        let weightedChunks = existingChunks.map { (url: $0, units: progressUnitsForAudioFile($0)) }
        let totalUnits = weightedChunks.reduce(0) { $0 + $1.units }
        startProcessingProgress(totalUnits: totalUnits)

        var recoveredCount = 0
        var nextSequence = startSequence

        for weightedChunk in weightedChunks {
            defer { advanceProcessingProgress(by: weightedChunk.units) }
            let chunkURL = weightedChunk.url
            let recoveredSegments: [TranscriptSegment]
            do {
                recoveredSegments = try await transcribeWithRetry(provider: provider, url: chunkURL, locale: locale)
            } catch {
                // Individual chunk decode failures should not abort recovery for the whole session.
                continue
            }

            for raw in recoveredSegments {
                let normalized = raw.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                if normalized.isEmpty {
                    continue
                }
                let segment = try await persistSegment(
                    runtime: runtime,
                    raw: raw,
                    sessionID: sessionID,
                    sequence: nextSequence,
                    locale: locale,
                    pipeline: pipeline,
                    pipelineExecutor: pipelineExecutor
                )
                let rendered = segment.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rendered.isEmpty else { continue }
                appendText(rendered)
                nextSequence += 1
                recoveredCount += 1
            }
        }

        return recoveredCount
    }

    private func recoverTranscriptFromSavedSessionAudio(
        runtime: SayItCoreRuntime,
        sessionID: UUID,
        provider: STTProvider,
        locale: String,
        pipeline: TextPipeline?,
        pipelineExecutor: PipelineExecutor,
        startSequence: Int
    ) async throws -> Int {
        guard let asset = try runtime.historyRepository.latestAudioAsset(sessionID: sessionID) else {
            return 0
        }
        let fileURL = URL(fileURLWithPath: asset.path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return 0
        }
        let totalUnits: Int
        if asset.durationMs > 0 {
            totalUnits = asset.durationMs
        } else {
            totalUnits = progressUnitsForAudioFile(fileURL)
        }
        startProcessingProgress(totalUnits: totalUnits)

        let recoveredSegments = try await transcribeWithRetry(provider: provider, url: fileURL, locale: locale)
        advanceProcessingProgress(by: totalUnits)
        var recoveredCount = 0
        var nextSequence = startSequence
        for raw in recoveredSegments {
            let normalized = raw.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized.isEmpty {
                continue
            }
            let segment = try await persistSegment(
                runtime: runtime,
                raw: raw,
                sessionID: sessionID,
                sequence: nextSequence,
                locale: locale,
                pipeline: pipeline,
                pipelineExecutor: pipelineExecutor
            )
            let rendered = segment.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rendered.isEmpty else { continue }
            appendText(rendered)
            nextSequence += 1
            recoveredCount += 1
        }
        return recoveredCount
    }

    private func transcribeWithRetry(provider: STTProvider, url: URL, locale: String) async throws -> [TranscriptSegment] {
        do {
            return try await provider.transcribeFile(url: url, config: STTFileConfig(locale: locale))
        } catch {
            guard isTransientWhisperError(error) else {
                throw error
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            return try await provider.transcribeFile(url: url, config: STTFileConfig(locale: locale))
        }
    }

    private func isTransientWhisperError(_ error: Error) -> Bool {
        let message = ("\(error) \(error.localizedDescription)").lowercased()
        return message.contains("whispererror error 1")
            || message.contains("whispererror error 2")
            || message.contains("instancebusy")
            || message.contains("cancelled")
    }

    private func switchRefinePrimaryToCodex(runtime: SayItCoreRuntime) throws {
        var config = try runtime.configManager.load()
        config.refine.primary = runtime.codexRefineProvider.id
        try runtime.configManager.save(config)
    }

    private func appendOAuthLog(_ line: String) {
        codexOAuthLogs.append(line)
        if codexOAuthLogs.count > 60 {
            codexOAuthLogs.removeFirst(codexOAuthLogs.count - 60)
        }
    }

    private var shouldCaptureSessionAudio: Bool {
        guard let raw = ProcessInfo.processInfo.environment["SAYIT_CAPTURE_SESSION_AUDIO"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty
        else {
            return true
        }
        return !(raw == "0" || raw == "false" || raw == "off" || raw == "no")
    }

    private func shouldRecordSessionAudioInParallel(provider: STTProvider) -> Bool {
        guard shouldCaptureSessionAudio else { return false }
        switch provider.id {
        case "whisper", "parakeet", "moonshine":
            // Local chunked providers already own microphone capture.
            return false
        case "openai":
            let mode = ProcessInfo.processInfo.environment["SAYIT_OPENAI_STREAM_MODE"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            // OpenAI chunked mode also owns local microphone capture.
            return mode == "realtime"
        default:
            return true
        }
    }

    private func persistLiveSessionAudioAsset(
        runtime: SayItCoreRuntime,
        sessionID: UUID,
        recorder: SessionAudioRecorder
    ) {
        guard let tempURL = recorder.stopRecording() else { return }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            let asset = try runtime.audioAssetStore.importFile(tempURL, sessionID: sessionID)
            try runtime.historyRepository.saveAudioAsset(asset)
        } catch {
            // Keep main transcription path unaffected by audio-asset persistence failure.
        }
    }

    private func persistArchivedChunkAudioAssets(
        runtime: SayItCoreRuntime,
        sessionID: UUID
    ) {
        let chunkURLs = SessionChunkArchive.listChunks(sessionID: sessionID)
        guard !chunkURLs.isEmpty else { return }
        defer { SessionChunkArchive.clear(sessionID: sessionID) }

        for chunkURL in chunkURLs {
            do {
                let asset = try runtime.audioAssetStore.importFile(chunkURL, sessionID: sessionID)
                try runtime.historyRepository.saveAudioAsset(asset)
            } catch {
                // Preserve transcription success even if chunk asset persistence fails.
            }
        }
    }
}
