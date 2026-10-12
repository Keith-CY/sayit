import FluidAudio
import Foundation

/// Who spoke when in Mac audio, as reported by the diarizer. Times are seconds on the
/// Mac audio timeline.
nonisolated struct SpeakerTurns: Equatable {
    struct Turn: Equatable {
        /// The diarizer's speaker slot.
        let speaker: Int
        let start: Double
        let end: Double
    }

    var turns: [Turn] = []

    /// The speaker heard most during `range`, if anyone was heard for at least a quarter
    /// of it.
    func dominantSpeaker(in range: ClosedRange<Double>) -> Int? {
        let length = range.upperBound - range.lowerBound
        guard length > 0 else { return nil }
        var heard: [Int: Double] = [:]
        for turn in self.turns {
            let overlap = min(turn.end, range.upperBound) - max(turn.start, range.lowerBound)
            if overlap > 0 { heard[turn.speaker, default: 0] += overlap }
        }
        guard let (speaker, seconds) = heard.max(by: { $0.value < $1.value }), seconds >= length / 4 else { return nil }
        return speaker
    }
}

/// Numbers speakers 1, 2, 3… in the order they first speak this session.
nonisolated struct SpeakerNumbering: Equatable {
    private var numbers: [Int: Int] = [:]

    var count: Int { self.numbers.count }

    mutating func number(for speaker: Int) -> Int {
        if let number = self.numbers[speaker] { return number }
        let number = self.numbers.count + 1
        self.numbers[speaker] = number
        return number
    }
}

/// Runs streaming speaker diarization (FluidAudio's Sortformer) on Mac audio, off the
/// capture queue, and keeps a snapshot of recent speaker turns.
nonisolated final class SpeakerTracker: @unchecked Sendable {
    /// Balanced Sortformer v2.1: about 1 s latency, four speaker slots.
    private static let config = SortformerConfig.balancedV2_1
    /// Turns older than this are dropped from the snapshot.
    private static let retention: Double = 120

    private let queue = DispatchQueue(label: "com.sayit.livecaptions.speakers", qos: .utility)
    private let lock = NSLock()
    private var diarizer: SortformerDiarizer?
    private var snapshot = SpeakerTurns()
    private var isStopped = false

    /// Downloads the model on first use (about 250 MB), then loads it.
    func prepare() async throws {
        let models = try await SortformerModels.loadFromHuggingFace(config: Self.config)
        let diarizer = SortformerDiarizer(config: Self.config)
        diarizer.initialize(models: models)
        self.lock.withLock { self.diarizer = diarizer }
    }

    /// Called on the capture queue with 16 kHz mono samples; diarizes on its own queue.
    func append(_ samples: [Float]) {
        self.queue.async {
            guard let diarizer = self.lock.withLock({ self.isStopped ? nil : self.diarizer }) else { return }
            diarizer.addAudio(samples)
            do {
                guard try diarizer.process() != nil else { return }
            } catch {
                return
            }
            let turns = Self.turns(from: diarizer.timeline)
            self.lock.withLock { self.snapshot = turns }
        }
    }

    var turns: SpeakerTurns {
        self.lock.withLock { self.snapshot }
    }

    func stop() {
        self.lock.withLock {
            self.isStopped = true
            self.diarizer = nil
        }
    }

    private static func turns(from timeline: DiarizerTimeline) -> SpeakerTurns {
        var turns: [SpeakerTurns.Turn] = []
        for speaker in timeline.speakers.values {
            for segment in speaker.finalizedSegments + speaker.tentativeSegments {
                turns.append(.init(speaker: speaker.index, start: Double(segment.startTime), end: Double(segment.endTime)))
            }
        }
        let latest = turns.map(\.end).max() ?? 0
        return SpeakerTurns(turns: turns.filter { $0.end >= latest - self.retention }.sorted { $0.start < $1.start })
    }
}
