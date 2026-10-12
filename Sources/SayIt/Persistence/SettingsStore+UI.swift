import Foundation

/// User-facing presentation for settings values, following docs/design/DESIGN.md § Copy.
/// Kept separate from the persisted model so storage identifiers never leak into UI copy.
extension SettingsStore.SpeechModel {
    /// The model's proper name.
    var uiName: String {
        switch self {
        case .parakeetTDT: return "Parakeet TDT v3"
        case .qwen3Asr: return "Qwen3-ASR 1.7B"
        case .appleSpeech: return "Apple Speech (Legacy)"
        case .appleSpeechAnalyzer: return "Apple Speech"
        case .whisperSmall: return "Whisper Small"
        case .whisperMedium: return "Whisper Medium"
        case .whisperLargeTurbo: return "Whisper Large Turbo"
        case .whisperLarge: return "Whisper Large"
        }
    }

    /// What the model is best at, in a few words.
    var uiTagline: String {
        switch self {
        case .parakeetTDT: return "Fastest, 25 languages"
        case .qwen3Asr: return "Chinese and English, including mixed speech"
        case .appleSpeech: return "Built into macOS"
        case .appleSpeechAnalyzer: return "Recommended for macOS 26 or later"
        case .whisperSmall: return "Private multilingual fallback"
        case .whisperMedium: return "Higher accuracy, more memory"
        case .whisperLargeTurbo: return "Near-maximum accuracy, faster"
        case .whisperLarge: return "Maximum accuracy"
        }
    }

    /// Download size, or that nothing needs downloading.
    var uiSize: String {
        switch self {
        case .appleSpeech, .appleSpeechAnalyzer:
            return "Built in"
        default:
            return self.downloadSize.replacingOccurrences(of: "~", with: "About ")
        }
    }

    /// Size phrase for confirmations ("about 500 MB").
    var uiSizePhrase: String {
        self.downloadSize.replacingOccurrences(of: "~", with: "about ")
    }

    var uiLanguages: String {
        switch self {
        case .appleSpeech: return "System languages"
        case .appleSpeechAnalyzer: return "9 languages"
        default: return self.languageSupport.replacingOccurrences(of: "Languages", with: "languages")
        }
    }

    /// Memory guidance without emoji or alarm wording.
    var uiMemoryNote: String? {
        switch self {
        case .qwen3Asr: return "Uses several gigabytes of memory while loaded."
        case .whisperLarge: return "Needs 10 GB of memory or more. Macs with less memory may quit unexpectedly."
        case .whisperLargeTurbo: return "Needs 8 GB of memory or more."
        case .whisperMedium: return "Needs 6 GB of memory or more."
        default: return nil
        }
    }

    /// Whether text appears only after recording stops.
    var uiTranscribesAfterRecording: Bool {
        !self.supportsStreaming
    }

    var uiCanDelete: Bool {
        !self.usesAppleLogo
    }
}

extension SettingsStore.SpeechLanguageMode {
    /// One-sentence explanation shown under the language picker.
    var uiExplanation: String {
        switch self {
        case .auto:
            return "Follows your macOS language settings."
        case .chineseEnglishMixed:
            return "For speech that mixes Chinese and English. Keeps Qwen or Whisper if one is in use; otherwise uses Apple Speech on macOS 26 or later, or Whisper Small on earlier versions."
        default:
            return "Always recognizes this language with Apple Speech."
        }
    }
}

extension SettingsStore.TranscriptionStartSound {
    var uiName: String {
        switch self {
        case .none: return "None"
        case .startupSfx1: return "Sound 1"
        case .startupSfx2: return "Sound 2"
        case .startupSfx3: return "Sound 3"
        case .startupSfx4: return "Sound 4"
        }
    }
}
