import AppKit
import Foundation

/// What the recording overlay is communicating right now.
///
/// Both overlay styles (notch and bottom) render this one model, so every dictation
/// ends in a visible outcome instead of the overlay silently disappearing.
enum OverlayPhase: Equatable {
    /// Overlay hidden / nothing in progress.
    case idle
    /// Microphone is starting up.
    case starting
    /// Capturing speech.
    case listening
    /// Speech model is converting the recording to text.
    case transcribing
    /// AI Enhancement is rewriting the transcript.
    case refining
    /// Finished. Shown briefly, then the overlay leaves.
    case done(OverlayOutcome)
    /// Failed. Shown briefly with the reason, then the overlay leaves.
    case failed(String)
    /// The user cancelled (Esc or the close button).
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .done, .failed, .cancelled: return true
        default: return false
        }
    }

    var isWorking: Bool {
        switch self {
        case .transcribing, .refining: return true
        default: return false
        }
    }

    /// Short status line shown in the overlay and announced by VoiceOver.
    var statusText: String {
        switch self {
        case .idle: return ""
        case .starting: return "Starting…"
        case .listening: return "Listening"
        case .transcribing: return "Transcribing…"
        case .refining: return "Enhancing…"
        case let .done(outcome): return outcome.statusText
        case let .failed(reason): return reason
        case .cancelled: return "Cancelled"
        }
    }
}

enum OverlayOutcome: Equatable {
    /// Text was typed into the focused app.
    case inserted
    /// Text could not be typed and was copied to the clipboard instead.
    case copied
    /// AI Enhancement failed, so the original transcript was inserted.
    case insertedOriginal
    /// The recording contained no speech.
    case noSpeech

    var statusText: String {
        switch self {
        case .inserted: return "Inserted"
        case .copied: return "Copied to Clipboard"
        case .insertedOriginal: return "Inserted Original Text"
        case .noSpeech: return "No Speech Detected"
        }
    }

    /// Whether the outcome is fully successful (drives the ✓ vs. notice glyph).
    var isSuccess: Bool {
        switch self {
        case .inserted, .copied: return true
        case .insertedOriginal, .noSpeech: return false
        }
    }
}

extension OverlayPhase {
    /// Posts the phase to VoiceOver so state changes are heard, not only seen.
    func announce() {
        let text = self.statusText
        guard !text.isEmpty, let app = NSApp else { return }
        NSAccessibility.post(
            element: app,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}

extension OverlayPhase {
    /// What the empty transcript area says before any words are available.
    var transcriptPlaceholder: String? {
        switch self {
        case .starting, .listening:
            let settings = SettingsStore.shared
            let streams = settings.selectedSpeechModel.supportsStreaming && settings.enableStreamingPreview
            return streams ? "Your words appear as you speak." : "Your words appear when you stop."
        case .transcribing, .refining:
            return "Your words appear in a moment."
        default:
            return nil
        }
    }
}
