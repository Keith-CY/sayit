import Foundation

/// Decides whether a transcript actually contains words.
///
/// Speech models often turn silence or breathing into a hesitation sound ("嗯。", "Um.").
/// Typing that into the user's app is worse than typing nothing, so the pipeline treats
/// such transcripts like an empty recording and reports "No Speech Detected".
enum TranscriptContent {
    /// Hesitation sounds models emit for silence, in the languages SayIt supports.
    static let hesitationTokens: Set<String> = [
        "嗯", "呃", "啊", "额", "哦", "噢", "唔", "欸",
        "um", "uh", "er", "ah", "eh", "hm", "hmm", "mm", "mhm", "erm", "uhm",
    ]

    /// True when `text` has no words: only whitespace, punctuation, symbols or hesitation
    /// sounds (including stretched ones like "嗯嗯" or "hmmm").
    static func hasNoWords(_ text: String, fillers: [String] = SettingsStore.shared.fillerWords) -> Bool {
        let vocabulary = self.hesitationTokens.union(fillers.map { $0.lowercased() })
        let separators = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)
        let tokens = text.lowercased()
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }

        return tokens.allSatisfy { token in
            vocabulary.contains(token) || vocabulary.contains(self.collapsingRepeats(token))
        }
    }

    /// "hmmm" → "hm", "嗯嗯嗯" → "嗯".
    private static func collapsingRepeats(_ token: String) -> String {
        var result = ""
        for character in token where character != result.last {
            result.append(character)
        }
        return result
    }
}
