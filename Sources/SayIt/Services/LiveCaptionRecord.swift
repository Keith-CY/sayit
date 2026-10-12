import Foundation

/// Every line one Live Captions session settled, kept for the saved transcript (the
/// panel only holds recent lines).
struct LiveCaptionRecord {
    struct Entry: Equatable {
        /// The row id, e.g. "macAudio-12".
        let id: String
        /// When the line was spoken.
        let time: Date
        let source: LiveCaptionSource
        /// Who spoke in Mac audio, when speakers are labeled.
        var speaker: Int?
        var text: String
        var translation: String?
    }

    let startedAt: Date
    var language: LiveCaptionLanguage
    var translationTarget: LiveCaptionLanguage?
    /// Oldest first.
    private(set) var entries: [Entry] = []

    init(startedAt: Date, language: LiveCaptionLanguage) {
        self.startedAt = startedAt
        self.language = language
    }

    var isEmpty: Bool { self.entries.isEmpty }

    /// Adds a settled line, in spoken order (lines from two sources settle out of order).
    mutating func add(_ entry: Entry) {
        guard !self.entries.contains(where: { $0.id == entry.id }) else { return }
        let index = self.entries.lastIndex { $0.time <= entry.time }.map { $0 + 1 } ?? 0
        self.entries.insert(entry, at: index)
    }

    mutating func setTranslation(_ translation: String, for id: String) {
        guard let index = self.entries.firstIndex(where: { $0.id == id }) else { return }
        self.entries[index].translation = translation
    }

    // MARK: - Markdown

    /// A new time mark is written at least this often within one speaker's turn.
    private static let timeMarkInterval: TimeInterval = 60

    /// The transcript as Markdown: a time and who is speaking at each turn, each line as a
    /// paragraph, its translation (if any) quoted below it.
    func markdown(timeZone: TimeZone = .current) -> String {
        let labelsSpeakers = Set(self.entries.compactMap(\.speaker)).count >= 2
        let labelsSources = self.entries.contains { $0.source == .microphone }

        var output = "# Live Captions \(Self.format(self.startedAt, "yyyy-MM-dd HH:mm", timeZone))\n\n"
        var languages = self.language.name
        if let target = self.translationTarget { languages += " → \(target.name)" }
        output += "\(languages)\n"

        var previous: (who: String?, mark: Date)?
        for entry in self.entries {
            let who = Self.who(entry, labelsSpeakers: labelsSpeakers, labelsSources: labelsSources)
            if let previous, previous.who == who, entry.time.timeIntervalSince(previous.mark) < Self.timeMarkInterval {
                output += "\n"
            } else {
                let time = Self.format(entry.time, "HH:mm:ss", timeZone)
                output += "\n**\(who.map { "\(time) · \($0)" } ?? time)**\n\n"
                previous = (who, entry.time)
            }
            output += "\(entry.text)\n"
            if let translation = entry.translation, !translation.isEmpty {
                output += "> \(translation)\n"
            }
        }
        return output
    }

    /// File name for a session's transcript; sorts by start time.
    static func fileName(startedAt: Date, timeZone: TimeZone = .current) -> String {
        "Live Captions \(Self.format(startedAt, "yyyy-MM-dd HH.mm.ss", timeZone)).md"
    }

    private static func who(_ entry: Entry, labelsSpeakers: Bool, labelsSources: Bool) -> String? {
        if entry.source == .microphone { return "You" }
        if labelsSpeakers, let speaker = entry.speaker { return "Speaker \(speaker)" }
        return labelsSources ? "Mac Audio" : nil
    }

    private static func format(_ date: Date, _ pattern: String, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

/// Where Live Captions transcripts are saved: Documents › SayIt › Live Captions.
enum LiveCaptionTranscripts {
    static var folder: URL {
        URL.documentsDirectory.appending(path: "SayIt/Live Captions", directoryHint: .isDirectory)
    }

    /// Writes a session's transcript, replacing the previous save of the same session.
    nonisolated static func write(_ markdown: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }
}
