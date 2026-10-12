import Foundation

/// Where caption audio comes from.
enum LiveCaptionSource: String, Sendable {
    /// What the Mac plays.
    case macAudio
    /// The user, through the microphone.
    case microphone
}

/// The caption text, grouped into lines that Qwen refines one at a time.
///
/// Apple's streaming results arrive as short *final* phrases plus a *volatile* tail that
/// keeps changing. Finals are appended to the open line; the line closes after a pause,
/// when it gets long, or when speech stops. Each closed line is one Qwen job: its audio
/// is re-transcribed and the line's text is replaced. Times are seconds since capture
/// started.
struct LiveCaptionTranscript: Equatable {
    struct Line: Identifiable, Equatable {
        enum State: Equatable {
            /// Still receiving Apple finals.
            case open
            /// Closed; Qwen hasn't replaced it yet.
            case awaitingRefinement
            /// Qwen's text.
            case refined
            /// Closed with Apple's text only (Qwen unavailable, skipped, or empty).
            case draftOnly
        }

        let id: Int
        var text: String
        var start: Double
        var end: Double
        var state: State

        /// Text that may still change.
        var isDraft: Bool { self.state == .open || self.state == .awaitingRefinement }
    }

    struct Policy: Equatable {
        /// A gap at least this long between phrases starts a new line.
        var pauseSeconds: Double = 0.8
        /// Lines close once they span this long, so refinement keeps up with speech.
        var maxLineSeconds: Double = 8
        /// With no new words for this long, the open line closes.
        var idleSeconds: Double = 1.2
        /// Words Apple hasn't committed for this long are committed at a quiet point.
        /// Measured from a coarse start (it can include a pause), so it's above `maxLineSeconds`.
        var maxUncommittedSeconds: Double = 10
        /// Lines kept for display; older finished lines are dropped.
        var maxLines: Int = 30
    }

    let policy: Policy
    private(set) var lines: [Line] = []
    /// Apple's in-progress words after the last final phrase.
    private(set) var volatileText = ""
    private(set) var volatileStart: Double?
    /// Speech ended here (a pause was heard); phrases ending by then close their line at once.
    private var speechEndedAt: Double?
    private var nextID = 0
    /// Apple's word times can trail the audio slightly.
    private static let timingTolerance = 0.3

    init(policy: Policy = Policy()) {
        self.policy = policy
    }

    // MARK: - Apple results

    /// Adds a final phrase. Returns the ids of lines that closed and need refining.
    mutating func applyFinal(_ text: String, start: Double, end: Double) -> [Int] {
        if let volatileStart = self.volatileStart, volatileStart < end {
            self.volatileText = ""
            self.volatileStart = nil
        }
        let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return [] }

        if let ended = self.speechEndedAt, start > ended {
            self.speechEndedAt = nil
        }
        var closed: [Int] = []
        if let index = self.openIndex, start - self.lines[index].end >= self.policy.pauseSeconds {
            closed.append(self.close(index))
        }
        if let index = self.openIndex {
            self.lines[index].text = Self.join(self.lines[index].text, phrase)
            self.lines[index].end = max(self.lines[index].end, end)
            if self.lines[index].end - self.lines[index].start >= self.policy.maxLineSeconds {
                closed.append(self.close(index))
            }
        } else {
            self.lines.append(Line(id: self.nextID, text: phrase, start: start, end: end, state: .open))
            self.nextID += 1
        }
        if let index = self.openIndex, let ended = self.speechEndedAt, self.lines[index].end <= ended + Self.timingTolerance {
            closed.append(self.close(index))
        }
        self.trim()
        return closed
    }

    /// A pause was heard at `time`: closes the open line now, or as soon as Apple commits
    /// the words spoken before it.
    mutating func speechEnded(at time: Double) -> [Int] {
        self.speechEndedAt = time
        guard self.volatileText.isEmpty, let index = self.openIndex,
              self.lines[index].end <= time + Self.timingTolerance
        else { return [] }
        return [self.close(index)]
    }

    /// True when Apple has words that a heard pause should commit.
    var hasUncommittedWords: Bool {
        !self.volatileText.isEmpty || self.openIndex != nil
    }

    /// Updates the forming words. Returns the open line's id if these words start after a
    /// pause, so that line can be refined now instead of when they settle.
    mutating func applyVolatile(_ text: String, start: Double) -> [Int] {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.volatileText = words
        self.volatileStart = words.isEmpty ? nil : start
        guard !words.isEmpty, let index = self.openIndex, start - self.lines[index].end >= self.policy.pauseSeconds else {
            return []
        }
        return [self.close(index)]
    }

    /// Closes the open line once speech has stopped for `idleSeconds`.
    mutating func closeIfIdle(now: Double) -> [Int] {
        guard let index = self.openIndex, self.volatileText.isEmpty,
              now - self.lines[index].end >= self.policy.idleSeconds
        else { return [] }
        return [self.close(index)]
    }

    /// True when the volatile tail has run long enough that Apple should be asked to
    /// commit it, so a line can't grow without bound during unbroken speech.
    func volatileTailIsOverdue(now: Double) -> Bool {
        guard let volatileStart = self.volatileStart else { return false }
        return now - volatileStart >= self.policy.maxUncommittedSeconds
    }

    // MARK: - Refinement

    /// Replaces a closed line with Qwen's text, or keeps Apple's text when `text` is nil.
    mutating func refine(_ id: Int, with text: String?) {
        guard let index = self.lines.firstIndex(where: { $0.id == id }), self.lines[index].state == .awaitingRefinement else {
            return
        }
        if let text, !text.isEmpty {
            self.lines[index].text = text
            self.lines[index].state = .refined
        } else {
            self.lines[index].state = .draftOnly
        }
        self.trim()
    }

    func line(_ id: Int) -> Line? {
        self.lines.first { $0.id == id }
    }

    /// Drops a line, e.g. microphone words that were the speakers' sound.
    mutating func remove(_ id: Int) {
        self.lines.removeAll { $0.id == id }
    }

    /// Text heard between two times: lines that overlap them plus the forming words.
    func text(overlapping range: ClosedRange<Double>) -> String {
        var parts = self.lines.filter { $0.start <= range.upperBound && $0.end >= range.lowerBound }.map(\.text)
        if let volatileStart = self.volatileStart, volatileStart <= range.upperBound {
            parts.append(self.volatileText)
        }
        return parts.joined(separator: " ")
    }

    /// The audio to re-transcribe for a line: its words plus `padding` on each side, but
    /// never reaching into a neighbouring line, so a word at a boundary isn't heard twice.
    func audioRange(for id: Int, padding: Double) -> ClosedRange<Double>? {
        guard let index = self.lines.firstIndex(where: { $0.id == id }) else { return nil }
        let line = self.lines[index]
        var start = line.start - padding
        var end = line.end + padding
        if index > 0 { start = max(start, self.lines[index - 1].end) }
        if index + 1 < self.lines.count { end = min(end, self.lines[index + 1].start) }
        return min(start, line.start)...max(end, line.end)
    }

    /// Audio before this time is no longer needed for refinement.
    func earliestNeededTime(now: Double) -> Double {
        self.lines.filter(\.isDraft).map(\.start).min() ?? self.volatileStart ?? now
    }

    // MARK: - Helpers

    private var openIndex: Int? {
        self.lines.lastIndex { $0.state == .open }
    }

    private mutating func close(_ index: Int) -> Int {
        self.lines[index].state = .awaitingRefinement
        return self.lines[index].id
    }

    /// Drops the oldest finished lines past `maxLines`; draft lines are kept until refined.
    private mutating func trim() {
        while self.lines.count > self.policy.maxLines, let index = self.lines.firstIndex(where: { !$0.isDraft }) {
            self.lines.remove(at: index)
        }
    }

    /// Joins phrases with a space only between Latin words, never inside CJK text.
    static func join(_ head: String, _ tail: String) -> String {
        guard let last = head.last, let first = tail.first else { return head + tail }
        let needsSpace = !last.isWhitespace && !first.isWhitespace
            && Self.isLatin(last) && Self.isLatin(first) && (first.isLetter || first.isNumber)
        return needsSpace ? "\(head) \(tail)" : head + tail
    }

    private static func isLatin(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { $0.isASCII && !CharacterSet.whitespaces.contains($0) }
    }
}

/// Recognizes microphone lines that are the speakers' sound picked up again: with no
/// headphones, the microphone hears what the Mac plays, which is already captioned.
enum LiveCaptionEcho {
    /// Share of the microphone line's character pairs that must also occur in what the Mac
    /// played. Pairs tolerate the small differences between two recognitions of the same
    /// sound; a real reply rarely repeats half of what was just said.
    static let threshold = 0.5

    static func isEcho(_ microphoneText: String, of macAudioText: String) -> Bool {
        let heard = self.normalized(microphoneText)
        let played = self.normalized(macAudioText)
        guard !heard.isEmpty, !played.isEmpty else { return false }
        guard heard.count > 1 else { return played.contains(heard[0]) }

        let playedPairs = Set(self.pairs(played))
        let heardPairs = self.pairs(heard)
        let shared = heardPairs.filter(playedPairs.contains).count
        return Double(shared) / Double(heardPairs.count) >= self.threshold
    }

    /// Letters and digits only, lowercased: punctuation and spacing differ between
    /// recognitions.
    private static func normalized(_ text: String) -> [Character] {
        text.lowercased().filter { $0.isLetter || $0.isNumber }.map { $0 }
    }

    private static func pairs(_ characters: [Character]) -> [String] {
        zip(characters, characters.dropFirst()).map { String([$0, $1]) }
    }
}
