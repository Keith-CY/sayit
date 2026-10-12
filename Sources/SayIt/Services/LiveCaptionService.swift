import AVFoundation
import Combine
import CoreMedia
import Foundation

#if canImport(Speech)
import Speech
#endif

// MARK: - View state

/// What the Live Captions panel shows. Kept separate from the session so the panel can
/// be rendered from fixtures (snapshot tests).
struct LiveCaptionViewState: Equatable {
    enum Phase: Equatable {
        case preparing
        case listening
        case failed(LiveCaptionFailure)
    }

    enum Microphone: Equatable {
        case off
        case on
        /// Turned on, but SayIt can't use it (permission denied or no device).
        case unavailable
    }

    /// One caption line as shown.
    struct Row: Identifiable, Equatable {
        let id: String
        let source: LiveCaptionSource
        /// Settled or draft words; empty when the row is only words still forming.
        var text: String
        /// Apple's forming words after `text`, including any separating space.
        var formingTail = ""
        /// `text` may still change (Apple's draft, or awaiting Qwen).
        var isDraft: Bool
        /// `text` is Qwen's.
        var isRefined = false
    }

    var phase: Phase = .preparing
    /// Oldest first, interleaved across sources by when they were spoken.
    var rows: [Row] = []
    var microphone: Microphone = .off
    /// Nothing but digital silence has arrived for a while.
    var showsSilenceHint = false
}

enum LiveCaptionFailure: Equatable {
    /// The system audio tap couldn't start.
    case cantHearMac
    /// Apple's speech model for the caption language couldn't be prepared.
    case speechUnavailable
}

/// Makes a capture that delivers 16 kHz mono chunks to the given closure.
typealias CaptionSourceFactory = (@escaping @Sendable ([Float]) -> Void) -> CaptionAudioSource

// MARK: - Service

/// Turns Live Captions on and off from the menu bar. The work happens in
/// `LiveCaptionSession`, which needs macOS 26 (SpeechAnalyzer).
@MainActor
final class LiveCaptionService: ObservableObject {
    static let shared = LiveCaptionService()

    @Published private(set) var isOn = false
    @Published private(set) var viewState = LiveCaptionViewState()

    static var isSupported: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    private var session: AnyObject?

    private init() {}

    func toggle() {
        if self.isOn { self.stop() } else { self.start() }
    }

    func start() {
        self.start(includeMicrophone: nil, makeMicrophone: nil)
    }

    /// - Parameters:
    ///   - includeMicrophone: Overrides the saved setting without changing it (tests).
    ///   - makeMicrophone: Replaces the real microphone (tests).
    func start(includeMicrophone: Bool?, makeMicrophone: CaptionSourceFactory?) {
        guard Self.isSupported, !self.isOn else { return }
        guard #available(macOS 26.0, *) else { return }
        self.isOn = true
        self.viewState = LiveCaptionViewState()
        LiveCaptionPanelController.shared.show()

        let session = LiveCaptionSession(
            includeMicrophone: includeMicrophone ?? SettingsStore.shared.liveCaptionsIncludeMicrophone,
            makeMicrophone: makeMicrophone
        ) { [weak self] state in
            self?.viewState = state
        }
        self.session = session
        DebugLogger.shared.info("Live Captions: on", source: "LiveCaptions")
        Task { await session.start() }
    }

    /// Turns the microphone source on or off, and remembers the choice.
    func setMicrophoneEnabled(_ enabled: Bool) {
        SettingsStore.shared.liveCaptionsIncludeMicrophone = enabled
        if #available(macOS 26.0, *), let session = self.session as? LiveCaptionSession {
            session.setMicrophoneEnabled(enabled)
        }
    }

    func stop() {
        guard self.isOn else { return }
        self.isOn = false
        LiveCaptionPanelController.shared.hide()
        if #available(macOS 26.0, *), let session = self.session as? LiveCaptionSession {
            Task { await session.stop() }
        }
        self.session = nil
        DebugLogger.shared.info("Live Captions: off", source: "LiveCaptions")
    }
}

// MARK: - Session

/// One Live Captions run. Each source (Mac audio, optionally the microphone) has its own
/// pipeline — capture → Apple draft words → lines — and closed lines from both share one
/// Qwen refinement queue.
@available(macOS 26.0, *)
@MainActor
private final class LiveCaptionSession {
    /// Dictation takes the model first; Live Captions wait while the user dictates.
    private static let dictationPollInterval: Duration = .milliseconds(150)
    private static let tickInterval: Duration = .milliseconds(250)
    /// Audio around a line, so Qwen hears word edges that Apple's timing clipped.
    private static let linePadding: Double = 0.25
    /// Recent audio always kept, since Apple may report a phrase a moment after it ends
    /// and echo checks look back at what the Mac played.
    private static let audioRetention: Double = 15
    /// When refinement falls this far behind, older lines keep Apple's words.
    private static let maxQueuedLines = 6
    /// Only pauses that began this recently count as new (longer silence was handled).
    private static let newPauseWindow: Double = 2.5
    /// How long only silence may arrive before the panel suggests checking permission.
    private static let silenceHintDelay: Double = 8
    /// Rows kept for display.
    private static let maxRows = 12
    /// Below this level (RMS) the Mac counts as quiet: the microphone can't be hearing it.
    private static let quietLevel: Float = 0.005
    /// How long a microphone line may wait for the Mac's words before it's shown anyway.
    private static let echoWait: Double = 3
    /// How far around a microphone line to look for the same words in Mac audio.
    private static let echoWindow: Double = 1.5

    private let onUpdate: (LiveCaptionViewState) -> Void
    private let makeMicrophone: CaptionSourceFactory
    private let checksMicrophonePermission: Bool
    /// The session clock: lines from different sources are ordered by time since this.
    private let startedAt = Date()

    private var phase: LiveCaptionViewState.Phase = .preparing
    private var microphoneState: LiveCaptionViewState.Microphone
    private var showsSilenceHint = false

    private let macAudio = CaptionPipeline(source: .macAudio)
    private var microphone: CaptionPipeline?
    /// Microphone lines held back until it's clear they aren't the speakers' sound.
    private var echoChecks: [(id: Int, since: Date)] = []
    private var dictationObserver: AnyCancellable?

    private var tickTask: Task<Void, Never>?
    private var refineTask: Task<Void, Never>?
    private var refineQueue: [(source: LiveCaptionSource, id: Int)] = []
    private let refineSignal: AsyncStream<Void>
    private let refineSignalContinuation: AsyncStream<Void>.Continuation
    private var refinesWithQwen = true
    private var isStopped = false

    init(
        includeMicrophone: Bool,
        makeMicrophone: CaptionSourceFactory?,
        onUpdate: @escaping (LiveCaptionViewState) -> Void
    ) {
        self.onUpdate = onUpdate
        self.microphoneState = includeMicrophone ? .on : .off
        self.makeMicrophone = makeMicrophone ?? { MicrophoneCapture(onSamples: $0) }
        self.checksMicrophonePermission = makeMicrophone == nil
        (self.refineSignal, self.refineSignalContinuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func start() async {
        guard !self.isStopped else { return }
        // Qwen loads while Apple and the audio tap start; lines that close first wait for it.
        self.refineTask = Task { [weak self] in await self?.runRefinement() }
        // The microphone hears whatever the user dictates to SayIt; that isn't a caption.
        let asr = AppServices.shared.asr
        self.dictationObserver = asr.$isStarting
            .combineLatest(asr.$isRunning, asr.$isTranscribingFinal)
            .sink { [weak self] starting, running, finishing in
                self?.microphone?.gate.isOpen = !(starting || running || finishing)
            }

        do {
            try await self.macAudio.startRecognizer { [weak self] in self?.handle($0, from: .macAudio) }
        } catch {
            DebugLogger.shared.error("Live Captions: Apple Speech unavailable: \(error)", source: "LiveCaptions")
            return self.fail(.speechUnavailable)
        }
        guard !self.isStopped else { return await self.macAudio.stop() }
        do {
            try self.macAudio.startCapture { SystemAudioCapture(onSamples: $0) }
        } catch {
            DebugLogger.shared.error("Live Captions: system audio capture failed: \(error)", source: "LiveCaptions")
            await self.macAudio.stop()
            return self.fail(.cantHearMac)
        }

        self.phase = .listening
        self.publish()
        self.tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                self?.tick()
            }
        }
        if self.microphoneState == .on {
            await self.startMicrophone()
        }
    }

    func stop() async {
        self.isStopped = true
        self.tickTask?.cancel()
        self.refineTask?.cancel()
        self.refineSignalContinuation.finish()
        self.dictationObserver = nil
        await self.macAudio.stop()
        await self.microphone?.stop()
        self.microphone = nil
        AppServices.shared.asr.releaseQwenAfterLiveCaptions()
    }

    // MARK: - Microphone

    func setMicrophoneEnabled(_ enabled: Bool) {
        guard !self.isStopped else { return }
        if enabled {
            guard self.microphone == nil else { return }
            self.microphoneState = .on
            self.publish()
            if self.phase == .listening {
                Task { await self.startMicrophone() }
            }
        } else {
            self.microphoneState = .off
            let microphone = self.microphone
            self.microphone = nil
            self.echoChecks.removeAll()
            self.refineQueue.removeAll { $0.source == .microphone }
            self.publish()
            Task { await microphone?.stop() }
        }
    }

    private func startMicrophone() async {
        if self.checksMicrophonePermission, await !Self.microphoneAuthorized() {
            DebugLogger.shared.info("Live Captions: microphone access is off", source: "LiveCaptions")
            self.microphoneState = .unavailable
            return self.publish()
        }
        let pipeline = CaptionPipeline(source: .microphone)
        pipeline.gate.isOpen = !AppServices.shared.asr.isDictationActive
        self.microphone = pipeline
        do {
            try await pipeline.startRecognizer { [weak self] in self?.handle($0, from: .microphone) }
            guard self.microphone === pipeline, !self.isStopped else { return await pipeline.stop() }
            try pipeline.startCapture(self.makeMicrophone)
        } catch {
            DebugLogger.shared.error("Live Captions: microphone failed: \(error)", source: "LiveCaptions")
            await pipeline.stop()
            guard self.microphone === pipeline else { return }
            self.microphone = nil
            self.microphoneState = .unavailable
            self.publish()
        }
    }

    private static func microphoneAuthorized() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    private func pipeline(for source: LiveCaptionSource) -> CaptionPipeline? {
        switch source {
        case .macAudio: return self.macAudio
        case .microphone: return self.microphone
        }
    }

    // MARK: - Apple results

    private func handle(_ event: LiveCaptionDraftEngine.Event, from source: LiveCaptionSource) {
        guard !self.isStopped, let pipeline = self.pipeline(for: source) else { return }
        switch event {
        case let .volatile(text, start):
            self.closed(pipeline.transcript.applyVolatile(text, start: start), in: pipeline)
        case let .final(text, start, end):
            self.closed(pipeline.transcript.applyFinal(text, start: start, end: end), in: pipeline)
        }
        self.publish()
    }

    private func tick() {
        guard !self.isStopped else { return }
        self.tick(self.macAudio)
        if let microphone = self.microphone {
            self.tick(microphone)
        }
        self.resolveEchoChecks()

        let now = self.macAudio.timeline.duration
        self.showsSilenceHint = self.macAudio.transcript.lines.isEmpty && now >= Self.silenceHintDelay
            && !self.macAudio.timeline.hasHeardSound
        self.publish()
    }

    private func tick(_ pipeline: CaptionPipeline) {
        let now = pipeline.timeline.duration
        self.closed(pipeline.transcript.closeIfIdle(now: now), in: pipeline)

        // A pause: Apple can take seconds to commit words on its own, so ask it to commit
        // them now and close the line, which sends it to Qwen right away.
        let silence = pipeline.timeline.trailingSilence()
        let pauseStart = now - silence
        if silence >= pipeline.transcript.policy.pauseSeconds, silence < Self.newPauseWindow,
           pauseStart > pipeline.handledPauseStart + 0.05,
           pipeline.transcript.hasUncommittedWords {
            pipeline.handledPauseStart = pauseStart
            self.closed(pipeline.transcript.speechEnded(at: pauseStart), in: pipeline)
            let draft = pipeline.draft
            Task { await draft.finalize(through: pauseStart) }
        }

        // Unbroken speech: ask Apple to commit its tail so the line can close, cutting at
        // the quietest moment of the last two seconds rather than mid-word.
        if pipeline.transcript.volatileTailIsOverdue(now: now), now - pipeline.lastForcedFinalize > 2 {
            pipeline.lastForcedFinalize = now
            let cut = pipeline.timeline.quietestPoint(from: now - 2, to: now - 0.2) ?? now
            let draft = pipeline.draft
            Task { await draft.finalize(through: cut) }
        }

        let needed = min(pipeline.transcript.earliestNeededTime(now: now), now - Self.audioRetention) - Self.linePadding
        pipeline.timeline.discard(before: needed)
    }

    /// Lines that closed: Mac audio lines go to Qwen; microphone lines are first checked
    /// for being the speakers' sound.
    private func closed(_ ids: [Int], in pipeline: CaptionPipeline) {
        guard !ids.isEmpty else { return }
        let now = pipeline.timeline.duration
        for id in ids {
            guard let line = pipeline.transcript.line(id) else { continue }
            DebugLogger.shared.debug(
                "Live Captions: \(pipeline.source.rawValue) line \(id) closed \(String(format: "%.1f", now - line.end))s after its last word",
                source: "LiveCaptions"
            )
        }
        switch pipeline.source {
        case .macAudio: self.enqueue(ids, from: .macAudio)
        case .microphone: self.echoChecks += ids.map { (id: $0, since: Date()) }
        }
    }

    // MARK: - Echo checks

    /// Keeps a microphone line when the Mac was quiet while it was spoken, drops it when
    /// the Mac played the same words around then, and otherwise keeps it after a short
    /// wait for Mac audio captions to catch up (both may genuinely talk at once).
    private func resolveEchoChecks() {
        guard let microphone = self.microphone else { return self.echoChecks.removeAll() }
        // Converts microphone time to Mac audio time through the session clock.
        let shift = microphone.offset(from: self.startedAt) - self.macAudio.offset(from: self.startedAt)

        self.echoChecks = self.echoChecks.filter { check in
            guard let line = microphone.transcript.line(check.id) else { return false }
            let start = line.start + shift
            let end = line.end + shift
            if self.macAudio.timeline.level(from: start, to: end) < Self.quietLevel {
                self.enqueue([check.id], from: .microphone)
                return false
            }
            let played = self.macAudio.transcript.text(overlapping: (start - Self.echoWindow)...(end + Self.echoWindow))
            if LiveCaptionEcho.isEcho(line.text, of: played) {
                DebugLogger.shared.debug("Live Captions: dropped microphone line \(check.id) as speaker sound", source: "LiveCaptions")
                microphone.transcript.remove(check.id)
                return false
            }
            if Date().timeIntervalSince(check.since) >= Self.echoWait {
                self.enqueue([check.id], from: .microphone)
                return false
            }
            return true
        }
    }

    // MARK: - Qwen refinement

    private func enqueue(_ ids: [Int], from source: LiveCaptionSource) {
        guard !ids.isEmpty, let pipeline = self.pipeline(for: source) else { return }
        guard self.refinesWithQwen else {
            ids.forEach { pipeline.transcript.refine($0, with: nil) }
            return
        }
        self.refineQueue += ids.map { (source: source, id: $0) }
        while self.refineQueue.count > Self.maxQueuedLines {
            let dropped = self.refineQueue.removeFirst()
            self.pipeline(for: dropped.source)?.transcript.refine(dropped.id, with: nil)
        }
        self.refineSignalContinuation.yield()
    }

    private func runRefinement() async {
        guard let qwen = await AppServices.shared.asr.qwenForLiveCaptions() else {
            DebugLogger.shared.info("Live Captions: Qwen isn't available; showing Apple Speech words", source: "LiveCaptions")
            self.refinesWithQwen = false
            for item in self.refineQueue {
                self.pipeline(for: item.source)?.transcript.refine(item.id, with: nil)
            }
            self.refineQueue.removeAll()
            return self.publish()
        }

        for await _ in self.refineSignal {
            while !self.refineQueue.isEmpty, !Task.isCancelled {
                await self.waitForDictationToFinish()
                guard !Task.isCancelled, !self.refineQueue.isEmpty else { break }
                let item = self.refineQueue.removeFirst()
                guard let pipeline = self.pipeline(for: item.source) else { continue }
                await self.refine(item.id, in: pipeline, with: qwen)
            }
        }
    }

    private func refine(_ id: Int, in pipeline: CaptionPipeline, with qwen: QwenASRProvider) async {
        guard let line = pipeline.transcript.line(id),
              let range = pipeline.transcript.audioRange(for: id, padding: Self.linePadding)
        else {
            pipeline.transcript.refine(id, with: nil)
            return self.publish()
        }
        let samples = pipeline.timeline.samples(from: range.lowerBound, to: range.upperBound)
        guard !samples.isEmpty else {
            pipeline.transcript.refine(id, with: nil)
            return self.publish()
        }

        let started = Date()
        let text = try? await qwen.transcribe(samples).text
        guard !Task.isCancelled, !self.isStopped else { return }
        let cleaned = text.map { ASRService.applyCustomDictionary(ASRService.removeFillerWords($0)) }
        // Qwen hearing no words where Apple heard some (music, noise): keep Apple's line.
        let refined = cleaned.flatMap { TranscriptContent.hasNoWords($0) ? nil : $0 }
        pipeline.transcript.refine(id, with: refined)
        DebugLogger.shared.debug(
            "Live Captions: refined \(pipeline.source.rawValue) line \(id) (\(String(format: "%.1f", line.end - line.start))s audio) in \(String(format: "%.2f", Date().timeIntervalSince(started)))s",
            source: "LiveCaptions"
        )
        self.publish()
    }

    private func waitForDictationToFinish() async {
        while AppServices.shared.asr.isDictationActive, !Task.isCancelled {
            try? await Task.sleep(for: Self.dictationPollInterval)
        }
    }

    // MARK: - Publishing

    private func fail(_ failure: LiveCaptionFailure) {
        self.phase = .failed(failure)
        self.publish()
    }

    private func publish() {
        guard !self.isStopped else { return }
        var rows = self.rows(of: self.macAudio, hidingForming: false)
        if let microphone = self.microphone {
            // While the Mac is playing, the microphone's forming words may be the speakers'
            // sound; they appear once their line passes the echo check.
            let macIsPlaying = self.macAudio.timeline.trailingSilence() < self.macAudio.transcript.policy.pauseSeconds
            rows += self.rows(of: microphone, hidingForming: macIsPlaying, hiding: Set(self.echoChecks.map(\.id)))
        }
        self.onUpdate(LiveCaptionViewState(
            phase: self.phase,
            rows: rows.sorted { $0.time < $1.time }.suffix(Self.maxRows).map(\.row),
            microphone: self.microphoneState,
            showsSilenceHint: self.showsSilenceHint
        ))
    }

    private func rows(
        of pipeline: CaptionPipeline,
        hidingForming: Bool,
        hiding hidden: Set<Int> = []
    ) -> [(time: Double, row: LiveCaptionViewState.Row)] {
        let transcript = pipeline.transcript
        let offset = pipeline.offset(from: self.startedAt)
        var rows: [(time: Double, row: LiveCaptionViewState.Row)] = []
        for line in transcript.lines where !hidden.contains(line.id) && !(hidingForming && line.state == .open) {
            let tail = line.state == .open && !transcript.volatileText.isEmpty
                ? String(LiveCaptionTranscript.join(line.text, transcript.volatileText).dropFirst(line.text.count))
                : ""
            let row = LiveCaptionViewState.Row(
                id: "\(pipeline.source.rawValue)-\(line.id)",
                source: pipeline.source,
                text: line.text,
                formingTail: tail,
                isDraft: line.isDraft,
                isRefined: line.state == .refined
            )
            rows.append((line.start + offset, row))
        }
        if !hidingForming, !transcript.volatileText.isEmpty, !transcript.lines.contains(where: { $0.state == .open }) {
            let row = LiveCaptionViewState.Row(
                id: "\(pipeline.source.rawValue)-forming",
                source: pipeline.source,
                text: "",
                formingTail: transcript.volatileText,
                isDraft: true
            )
            rows.append(((transcript.volatileStart ?? 0) + offset, row))
        }
        return rows
    }
}

// MARK: - Pipeline

/// One source's capture, Apple recognizer, audio and lines.
@available(macOS 26.0, *)
@MainActor
private final class CaptionPipeline {
    let source: LiveCaptionSource
    var transcript = LiveCaptionTranscript()
    let timeline = CaptionAudioTimeline()
    let draft = LiveCaptionDraftEngine()
    /// Closed while the user dictates: the microphone then captures silence.
    let gate = CaptureGate()
    var handledPauseStart: Double = -.infinity
    var lastForcedFinalize: Double = -.infinity
    private var capture: CaptionAudioSource?

    init(source: LiveCaptionSource) {
        self.source = source
    }

    func startRecognizer(onEvent: @escaping (LiveCaptionDraftEngine.Event) -> Void) async throws {
        try await self.draft.start(onEvent: onEvent)
    }

    func startCapture(_ make: CaptionSourceFactory) throws {
        let timeline = self.timeline
        let draft = self.draft
        let gate = self.gate
        let capture = make { samples in
            let audio = gate.isOpen ? samples : [Float](repeating: 0, count: samples.count)
            timeline.append(audio)
            draft.append(audio)
        }
        try capture.start()
        self.capture = capture
    }

    func stop() async {
        self.capture?.stop()
        self.capture = nil
        await self.draft.stop()
    }

    /// Seconds from the session start to this source's first sample, which maps its audio
    /// times onto the session clock.
    func offset(from sessionStart: Date) -> Double {
        self.timeline.startedAt.map { $0.timeIntervalSince(sessionStart) } ?? 0
    }
}

/// A thread-safe on/off switch read on the capture queue.
nonisolated final class CaptureGate: @unchecked Sendable {
    private let lock = NSLock()
    private var open = true

    var isOpen: Bool {
        get { self.lock.withLock { self.open } }
        set { self.lock.withLock { self.open = newValue } }
    }
}

// MARK: - Apple draft engine

/// Streams captured audio into Apple's SpeechAnalyzer and reports draft words as they
/// form (volatile) and settle (final), with their audio times.
///
/// Lifecycle calls run on the main actor; `append` runs on the capture queue and only
/// touches lock-protected state.
@available(macOS 26.0, *)
final class LiveCaptionDraftEngine {
    enum Event: Sendable {
        case volatile(String, start: Double)
        case final(String, start: Double, end: Double)
    }

    private nonisolated let lock = NSLock()
    private nonisolated(unsafe) var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private nonisolated(unsafe) var analyzerFormat: AVAudioFormat?
    /// Used only from the capture queue (`append`).
    private nonisolated let converter = BufferConverter()
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, Never>?

    func start(onEvent: @escaping (Event) -> Void) async throws {
        let locale = await AppleSpeechAnalyzerProvider.resolveSupportedLocale()
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            // Fast results: Qwen replaces the words anyway, so earlier beats more accurate.
            reportingOptions: [.volatileResults, .fastResults],
            // Word timings: Apple's result ranges tile the timeline and include silence.
            attributeOptions: [.audioTimeRange]
        )
        try await AppleSpeechAnalyzerProvider.installAssetsIfNeeded(for: transcriber, locale: locale, progressHandler: nil)
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let (start, end) = Self.speechSpan(of: result)
                    onEvent(result.isFinal ? .final(text, start: start, end: end) : .volatile(text, start: start))
                }
            } catch is CancellationError {
                // Stopped.
            } catch {
                DebugLogger.shared.warning("Live Captions: Apple results ended: \(error.localizedDescription)", source: "LiveCaptions")
            }
        }
        // Load the model now; otherwise it loads on the first audio and results arrive
        // seconds late, in one burst.
        try await analyzer.prepareToAnalyze(in: format)
        try await analyzer.start(inputSequence: stream)
        self.analyzer = analyzer
        self.lock.withLock {
            self.continuation = continuation
            self.analyzerFormat = format
        }
        DebugLogger.shared.info(
            "Live Captions: Apple Speech started (\(locale.identifier(.bcp47)))",
            source: "LiveCaptions"
        )
    }

    /// Called on the capture queue with 16 kHz mono samples.
    nonisolated func append(_ samples: [Float]) {
        let (continuation, format) = self.lock.withLock { (self.continuation, self.analyzerFormat) }
        guard let continuation, let buffer = Self.makeBuffer(samples) else { return }
        let input = format.flatMap { try? self.converter.convertBuffer(buffer, to: $0) } ?? buffer
        continuation.yield(AnalyzerInput(buffer: input))
    }

    /// Commits Apple's words up to `seconds`, ending the current phrase there.
    func finalize(through seconds: Double) async {
        try? await self.analyzer?.finalize(through: CMTime(seconds: seconds, preferredTimescale: 16000))
    }

    func stop() async {
        let continuation = self.lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.finish()
        await self.analyzer?.cancelAndFinishNow()
        self.resultsTask?.cancel()
        self.analyzer = nil
    }

    /// From the first word's start to the last word's end, so a line's times cover speech
    /// only — pauses between lines become measurable and Qwen isn't fed leading silence.
    private static func speechSpan(of result: SpeechTranscriber.Result) -> (start: Double, end: Double) {
        let words = result.text.runs.compactMap { $0[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] }
        let start = words.map(\.start.seconds).min() ?? result.range.start.seconds
        let end = words.map(\.end.seconds).max() ?? result.range.end.seconds
        return (start, max(start, end))
    }

    private nonisolated static func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        let format = CaptionAudio.outputFormat
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            channel.update(from: base, count: samples.count)
        }
        return buffer
    }
}

// MARK: - Audio timeline

/// Recent captured audio, addressable by time, so closed lines can be re-transcribed.
nonisolated final class CaptionAudioTimeline: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    /// Absolute index of `samples[0]` since capture started.
    private var baseIndex = 0
    private var heardSound = false
    private var firstSampleTime: Date?
    private static let sampleRate = CaptionAudio.sampleRate
    /// Trim in steps of at least this many samples, to avoid shifting the array every tick.
    private static let minimumTrim = Int(CaptionAudio.sampleRate * 5)

    func append(_ chunk: [Float]) {
        self.lock.withLock {
            if self.firstSampleTime == nil {
                // The chunk arrives once it's full, so its first sample is that much older.
                self.firstSampleTime = Date(timeIntervalSinceNow: -Double(chunk.count) / Self.sampleRate)
            }
            self.samples.append(contentsOf: chunk)
            if !self.heardSound, chunk.contains(where: { abs($0) > 1e-5 }) {
                self.heardSound = true
            }
        }
    }

    /// When the first sample was captured (time zero of this timeline).
    var startedAt: Date? {
        self.lock.withLock { self.firstSampleTime }
    }

    /// Seconds of audio received since capture started.
    var duration: Double {
        self.lock.withLock { Double(self.baseIndex + self.samples.count) / Self.sampleRate }
    }

    var hasHeardSound: Bool {
        self.lock.withLock { self.heardSound }
    }

    /// RMS level between two times; 0 for audio that is gone or not yet captured.
    func level(from start: Double, to end: Double) -> Float {
        let samples = self.samples(from: start, to: end)
        guard !samples.isEmpty else { return 0 }
        let energy = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (energy / Float(samples.count)).squareRoot()
    }

    /// The middle of the quietest 20 ms frame between two times, or nil if that audio is gone.
    func quietestPoint(from start: Double, to end: Double) -> Double? {
        self.lock.withLock {
            let frame = Int(Self.sampleRate / 50)
            var index = max(Int(start * Self.sampleRate), self.baseIndex) - self.baseIndex
            let last = min(Int(end * Self.sampleRate) - self.baseIndex, self.samples.count)
            var best: (index: Int, energy: Float)?
            while index + frame <= last {
                var energy: Float = 0
                for sample in index..<(index + frame) {
                    energy += self.samples[sample] * self.samples[sample]
                }
                if energy < (best?.energy ?? .infinity) { best = (index, energy) }
                index += frame
            }
            return best.map { Double(self.baseIndex + $0.index + frame / 2) / Self.sampleRate }
        }
    }

    /// Seconds of quiet at the end of the audio (up to `limit`), measured in 20 ms frames.
    func trailingSilence(threshold: Float = 0.005, limit: Double = 3) -> Double {
        self.lock.withLock {
            let frame = Int(Self.sampleRate / 50)
            var end = self.samples.count
            var silent = 0
            while end >= frame, Double(silent) / Self.sampleRate < limit {
                var energy: Float = 0
                for index in (end - frame)..<end {
                    energy += self.samples[index] * self.samples[index]
                }
                guard (energy / Float(frame)).squareRoot() < threshold else { break }
                silent += frame
                end -= frame
            }
            return Double(silent) / Self.sampleRate
        }
    }

    /// Audio between two times; empty if its start was already discarded.
    func samples(from start: Double, to end: Double) -> [Float] {
        self.lock.withLock {
            let first = max(Int(start * Self.sampleRate), 0)
            let last = min(Int(end * Self.sampleRate), self.baseIndex + self.samples.count)
            guard first >= self.baseIndex, last > first else { return [] }
            return Array(self.samples[(first - self.baseIndex)..<(last - self.baseIndex)])
        }
    }

    func discard(before time: Double) {
        self.lock.withLock {
            let cut = min(Int(time * Self.sampleRate) - self.baseIndex, self.samples.count)
            guard cut >= Self.minimumTrim else { return }
            self.samples.removeFirst(cut)
            self.baseIndex += cut
        }
    }
}
