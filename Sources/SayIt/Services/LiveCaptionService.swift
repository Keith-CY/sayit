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

    var phase: Phase = .preparing
    var lines: [LiveCaptionTranscript.Line] = []
    var volatileText = ""
    /// Nothing but digital silence has arrived for a while.
    var showsSilenceHint = false
}

enum LiveCaptionFailure: Equatable {
    /// The system audio tap couldn't start.
    case cantHearMac
    /// Apple's speech model for the caption language couldn't be prepared.
    case speechUnavailable
}

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
        guard Self.isSupported, !self.isOn else { return }
        guard #available(macOS 26.0, *) else { return }
        self.isOn = true
        self.viewState = LiveCaptionViewState()
        LiveCaptionPanelController.shared.show()

        let session = LiveCaptionSession { [weak self] state in
            self?.viewState = state
        }
        self.session = session
        DebugLogger.shared.info("Live Captions: on", source: "LiveCaptions")
        Task { await session.start() }
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

/// One Live Captions run: system audio → Apple draft words → lines → Qwen refinement.
@available(macOS 26.0, *)
@MainActor
private final class LiveCaptionSession {
    /// Dictation takes the model first; Live Captions wait while the user dictates.
    private static let dictationPollInterval: Duration = .milliseconds(150)
    private static let tickInterval: Duration = .milliseconds(250)
    /// Audio around a line, so Qwen hears word edges that Apple's timing clipped.
    private static let linePadding: Double = 0.25
    /// Recent audio always kept, since Apple may report a phrase a moment after it ends.
    private static let audioRetention: Double = 15
    /// When refinement falls this far behind, older lines keep Apple's words.
    private static let maxQueuedLines = 6
    /// Only pauses that began this recently count as new (longer silence was handled).
    private static let newPauseWindow: Double = 2.5
    /// How long only silence may arrive before the panel suggests checking permission.
    private static let silenceHintDelay: Double = 8

    private let onUpdate: (LiveCaptionViewState) -> Void
    private var transcript = LiveCaptionTranscript()
    private var phase: LiveCaptionViewState.Phase = .preparing
    private var showsSilenceHint = false

    private let timeline = CaptionAudioTimeline()
    private let draft = LiveCaptionDraftEngine()
    private var capture: SystemAudioCapture?
    private var tickTask: Task<Void, Never>?
    private var refineTask: Task<Void, Never>?
    private var refineQueue: [Int] = []
    private let refineSignal: AsyncStream<Void>
    private let refineSignalContinuation: AsyncStream<Void>.Continuation
    private var refinesWithQwen = true
    private var lastForcedFinalize: Double = -.infinity
    /// Start of the last pause handled, so each pause commits Apple's words once.
    private var handledPauseStart: Double = -.infinity
    private var isStopped = false

    init(onUpdate: @escaping (LiveCaptionViewState) -> Void) {
        self.onUpdate = onUpdate
        (self.refineSignal, self.refineSignalContinuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func start() async {
        guard !self.isStopped else { return }
        // Qwen loads while Apple and the audio tap start; lines that close first wait for it.
        self.refineTask = Task { [weak self] in await self?.runRefinement() }

        do {
            try await self.draft.start { [weak self] event in self?.handle(event) }
        } catch {
            DebugLogger.shared.error("Live Captions: Apple Speech unavailable: \(error)", source: "LiveCaptions")
            self.fail(.speechUnavailable)
            return
        }
        guard !self.isStopped else { return await self.draft.stop() }

        let timeline = self.timeline
        let draft = self.draft
        let capture = SystemAudioCapture { samples in
            timeline.append(samples)
            draft.append(samples)
        }
        do {
            try capture.start()
        } catch {
            DebugLogger.shared.error("Live Captions: system audio capture failed: \(error)", source: "LiveCaptions")
            await self.draft.stop()
            self.fail(.cantHearMac)
            return
        }
        self.capture = capture
        self.phase = .listening
        self.publish()
        self.tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                self?.tick()
            }
        }
    }

    func stop() async {
        self.isStopped = true
        self.tickTask?.cancel()
        self.refineTask?.cancel()
        self.refineSignalContinuation.finish()
        self.capture?.stop()
        self.capture = nil
        await self.draft.stop()
        AppServices.shared.asr.releaseQwenAfterLiveCaptions()
    }

    // MARK: - Apple results

    private func handle(_ event: LiveCaptionDraftEngine.Event) {
        guard !self.isStopped else { return }
        switch event {
        case let .volatile(text, start):
            self.enqueue(self.transcript.applyVolatile(text, start: start))
        case let .final(text, start, end):
            self.enqueue(self.transcript.applyFinal(text, start: start, end: end))
        }
        self.publish()
    }

    private func tick() {
        guard !self.isStopped else { return }
        let now = self.timeline.duration
        self.enqueue(self.transcript.closeIfIdle(now: now))

        // A pause: Apple can take seconds to commit words on its own, so ask it to commit
        // them now and close the line, which sends it to Qwen right away.
        let silence = self.timeline.trailingSilence()
        let pauseStart = now - silence
        if silence >= self.transcript.policy.pauseSeconds, silence < Self.newPauseWindow,
           pauseStart > self.handledPauseStart + 0.05,
           self.transcript.hasUncommittedWords {
            self.handledPauseStart = pauseStart
            self.enqueue(self.transcript.speechEnded(at: pauseStart))
            let draft = self.draft
            Task { await draft.finalize(through: pauseStart) }
        }

        // Unbroken speech: ask Apple to commit its tail so the line can close, cutting at
        // the quietest moment of the last two seconds rather than mid-word.
        if self.transcript.volatileTailIsOverdue(now: now), now - self.lastForcedFinalize > 2 {
            self.lastForcedFinalize = now
            let cut = self.timeline.quietestPoint(from: now - 2, to: now - 0.2) ?? now
            let draft = self.draft
            Task { await draft.finalize(through: cut) }
        }

        self.showsSilenceHint = self.transcript.lines.isEmpty && now >= Self.silenceHintDelay && !self.timeline.hasHeardSound
        let needed = min(self.transcript.earliestNeededTime(now: now), now - Self.audioRetention) - Self.linePadding
        self.timeline.discard(before: needed)
        self.publish()
    }

    // MARK: - Qwen refinement

    private func enqueue(_ ids: [Int]) {
        guard !ids.isEmpty else { return }
        let now = self.timeline.duration
        for id in ids {
            guard let line = self.transcript.line(id) else { continue }
            DebugLogger.shared.debug(
                "Live Captions: line \(id) closed \(String(format: "%.1f", now - line.end))s after its last word",
                source: "LiveCaptions"
            )
        }
        guard self.refinesWithQwen else {
            ids.forEach { self.transcript.refine($0, with: nil) }
            return
        }
        self.refineQueue.append(contentsOf: ids)
        while self.refineQueue.count > Self.maxQueuedLines {
            self.transcript.refine(self.refineQueue.removeFirst(), with: nil)
        }
        self.refineSignalContinuation.yield()
    }

    private func runRefinement() async {
        guard let qwen = await AppServices.shared.asr.qwenForLiveCaptions() else {
            DebugLogger.shared.info("Live Captions: Qwen isn't available; showing Apple Speech words", source: "LiveCaptions")
            self.refinesWithQwen = false
            self.refineQueue.forEach { self.transcript.refine($0, with: nil) }
            self.refineQueue.removeAll()
            self.publish()
            return
        }

        for await _ in self.refineSignal {
            while !self.refineQueue.isEmpty, !Task.isCancelled {
                await self.waitForDictationToFinish()
                guard !Task.isCancelled, !self.refineQueue.isEmpty else { break }
                let id = self.refineQueue.removeFirst()
                await self.refine(id, with: qwen)
            }
        }
    }

    private func refine(_ id: Int, with qwen: QwenASRProvider) async {
        guard let line = self.transcript.line(id),
              let range = self.transcript.audioRange(for: id, padding: Self.linePadding)
        else {
            self.transcript.refine(id, with: nil)
            self.publish()
            return
        }
        let samples = self.timeline.samples(from: range.lowerBound, to: range.upperBound)
        guard !samples.isEmpty else {
            self.transcript.refine(id, with: nil)
            self.publish()
            return
        }

        let started = Date()
        let text = try? await qwen.transcribe(samples).text
        guard !Task.isCancelled, !self.isStopped else { return }
        let cleaned = text.map { ASRService.applyCustomDictionary(ASRService.removeFillerWords($0)) }
        // Qwen hearing no words where Apple heard some (music, noise): keep Apple's line.
        let refined = cleaned.flatMap { TranscriptContent.hasNoWords($0) ? nil : $0 }
        self.transcript.refine(id, with: refined)
        DebugLogger.shared.debug(
            "Live Captions: refined line \(id) (\(String(format: "%.1f", line.end - line.start))s audio) in \(String(format: "%.2f", Date().timeIntervalSince(started)))s",
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
        self.onUpdate(LiveCaptionViewState(
            phase: self.phase,
            lines: self.transcript.lines,
            volatileText: self.transcript.volatileText,
            showsSilenceHint: self.showsSilenceHint
        ))
    }
}

// MARK: - Apple draft engine

/// Streams system audio into Apple's SpeechAnalyzer and reports draft words as they
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
        let format = SystemAudioCapture.outputFormat
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
@available(macOS 14.2, *)
nonisolated final class CaptionAudioTimeline: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    /// Absolute index of `samples[0]` since capture started.
    private var baseIndex = 0
    private var heardSound = false
    private static let sampleRate = SystemAudioCapture.sampleRate
    /// Trim in steps of at least this many samples, to avoid shifting the array every tick.
    private static let minimumTrim = Int(SystemAudioCapture.sampleRate * 5)

    func append(_ chunk: [Float]) {
        self.lock.withLock {
            self.samples.append(contentsOf: chunk)
            if !self.heardSound, chunk.contains(where: { abs($0) > 1e-5 }) {
                self.heardSound = true
            }
        }
    }

    /// Seconds of audio received since capture started.
    var duration: Double {
        self.lock.withLock { Double(self.baseIndex + self.samples.count) / Self.sampleRate }
    }

    var hasHeardSound: Bool {
        self.lock.withLock { self.heardSound }
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
