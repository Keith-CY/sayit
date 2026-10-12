import Foundation

/// A language Live Captions can show: the language being spoken, or the language
/// captions are translated into. Captioning needs Apple's draft and Qwen; translating
/// needs macOS on-device Translation.
enum LiveCaptionLanguage: String, CaseIterable, Identifiable {
    case chinese
    case chineseTraditional
    case english
    case japanese
    case korean
    case french
    case german
    case spanish
    case italian
    case portuguese
    case russian

    var id: String { self.rawValue }

    /// The language's own name, so people find theirs in the list.
    var name: String {
        switch self {
        case .chinese: return "中文"
        case .chineseTraditional: return "繁體中文"
        case .english: return "English"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .italian: return "Italiano"
        case .portuguese: return "Português"
        case .russian: return "Русский"
        }
    }

    /// What Apple's draft and Qwen run with; nil when captions can't be in this language
    /// (Apple's speech model has no Russian).
    var speechMode: SettingsStore.SpeechLanguageMode? {
        switch self {
        case .chinese: return .chineseEnglishMixed
        case .chineseTraditional: return .chineseTraditional
        case .english: return .english
        case .japanese: return .japanese
        case .korean: return .korean
        case .french: return .french
        case .german: return .german
        case .spanish: return .spanish
        case .italian: return .italian
        case .portuguese: return .portuguese
        case .russian: return nil
        }
    }

    /// The language as macOS Translation names it.
    var translationLanguage: Locale.Language {
        switch self {
        case .chinese: return Locale.Language(identifier: "zh-Hans")
        case .chineseTraditional: return Locale.Language(identifier: "zh-Hant")
        case .english: return Locale.Language(identifier: "en")
        case .japanese: return Locale.Language(identifier: "ja")
        case .korean: return Locale.Language(identifier: "ko")
        case .french: return Locale.Language(identifier: "fr")
        case .german: return Locale.Language(identifier: "de")
        case .spanish: return Locale.Language(identifier: "es")
        case .italian: return Locale.Language(identifier: "it")
        case .portuguese: return Locale.Language(identifier: "pt")
        case .russian: return Locale.Language(identifier: "ru")
        }
    }

    /// Languages captions can be in.
    static let captionable = Self.allCases.filter { $0.speechMode != nil }

    /// Maps a language identifier ("zh-Hans-CN", "zh-TW", "ja-JP", "en") to a language.
    init?(languageIdentifier identifier: String) {
        let language = Locale.Language(identifier: identifier)
        switch language.languageCode?.identifier {
        case "zh":
            let traditional = language.script?.identifier == "Hant"
                || ["TW", "HK", "MO"].contains(language.region?.identifier ?? "")
            self = traditional ? .chineseTraditional : .chinese
        case "en": self = .english
        case "ja": self = .japanese
        case "ko": self = .korean
        case "fr": self = .french
        case "de": self = .german
        case "es": self = .spanish
        case "it": self = .italian
        case "pt": self = .portuguese
        case "ru": self = .russian
        default: return nil
        }
    }

    /// The caption language to start with: the dictation language, else the Mac's.
    static func initial(dictation: SettingsStore.SpeechLanguageMode, preferredLanguages: [String]) -> Self {
        if dictation == .chineseSimplified { return .chinese }
        if let match = Self.captionable.first(where: { $0.speechMode == dictation }) { return match }
        return preferredLanguages.lazy.compactMap { Self(languageIdentifier: $0) }.first { $0.speechMode != nil } ?? .english
    }

    /// The language to translate captions in `source` into, when none was chosen: the
    /// Mac's first language unless it's the captions' own, else English (or Chinese for
    /// English captions).
    static func suggestedTarget(for source: Self, preferredLanguages: [String]) -> Self {
        if let preferred = preferredLanguages.lazy.compactMap({ Self(languageIdentifier: $0) }).first,
           !preferred.isSameLanguage(as: source) {
            return preferred
        }
        return source == .english ? .chinese : .english
    }

    /// Simplified and Traditional Chinese count as one language: translating between
    /// them isn't what anyone wants from captions.
    func isSameLanguage(as other: Self) -> Bool {
        let chinese: Set<Self> = [.chinese, .chineseTraditional]
        return self == other || (chinese.contains(self) && chinese.contains(other))
    }
}
