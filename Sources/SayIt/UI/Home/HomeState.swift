import AVFoundation
import Foundation

/// Everything Home renders, as plain values. `HomeScreen` builds it from live services;
/// snapshot tests build it directly.
struct HomeState: Equatable {
    var micStatus: AVAuthorizationStatus
    var accessibilityEnabled: Bool
    /// Accessibility was granted during this session but the shortcut listener
    /// needs a restart to pick it up.
    var accessibilityNeedsRestart: Bool
    var model: SpeechModelSummary
    var modelState: SpeechModelState
    /// A dictation has produced text at least once.
    var firstDictationDone: Bool
    var aiEnhancementConfigured: Bool
    var aiEnhancementEnabled: Bool
    var shortcut: String
    var commandShortcut: String?
    var editShortcut: String?
    var historyEnabled: Bool
    var recent: [RecentDictation]

    var micReady: Bool { self.micStatus == .authorized }

    var accessibilityDone: Bool { self.accessibilityEnabled && !self.accessibilityNeedsRestart }

    var modelReady: Bool {
        switch self.modelState {
        case .ready, .onDisk: return true
        default: return false
        }
    }

    /// Microphone, Accessibility and a speech model: what dictation needs to work.
    var requirementsMet: Bool {
        self.micReady && self.accessibilityDone && self.modelReady
    }

    /// Requirements plus one successful dictation. Until then Home shows the checklist.
    var setupComplete: Bool {
        self.requirementsMet && self.firstDictationDone
    }

    var completedRequiredSteps: Int {
        [self.micReady, self.accessibilityDone, self.modelReady, self.firstDictationDone]
            .filter { $0 }
            .count
    }

    static let requiredStepCount = 4
}

struct SpeechModelSummary: Equatable {
    var name: String
    /// e.g. “About 2.47 GB”; nil for built-in models.
    var sizeText: String?

    var isBuiltIn: Bool { self.sizeText == nil }

    init(name: String, sizeText: String?) {
        self.name = name
        self.sizeText = sizeText
    }

    init(_ model: SettingsStore.SpeechModel) {
        self.name = model.displayName
        switch model {
        case .appleSpeech, .appleSpeechAnalyzer:
            self.sizeText = nil
        default:
            let raw = model.downloadSize.replacingOccurrences(of: "~", with: "")
            self.sizeText = "About \(raw)"
        }
    }
}

enum SpeechModelState: Equatable {
    /// Loaded and ready to transcribe.
    case ready
    /// Downloaded; loads on first use.
    case onDisk
    /// Being loaded into memory.
    case loading
    /// Not on this Mac yet.
    case missing
    /// Downloading; `fraction` is nil when progress isn't reported.
    case downloading(fraction: Double?, cancellable: Bool)
    case failed(String)
    case cancelled
}

struct RecentDictation: Equatable, Identifiable {
    let id: UUID
    let text: String
    let appName: String
    let date: Date
}

/// Test area (playground) state.
struct HomeTestAreaState: Equatable {
    var action: RecordingControlAction
    var isRunning: Bool
    var transcript: String
    /// Parakeet custom-vocabulary status, shown under the test area when relevant.
    var wordBoostText: String?
}

/// Actions Home can trigger. Closures are supplied by `ContentView`.
struct HomeActions {
    var requestMicrophone: () -> Void = {}
    var openMicrophoneSettings: () -> Void = {}
    var openAccessibilitySettings: () -> Void = {}
    var restartApp: () -> Void = {}
    var downloadModel: () -> Void = {}
    var cancelDownload: () -> Void = {}
    var openVoiceEngine: () -> Void = {}
    var openAIEnhancement: () -> Void = {}
    var openGeneral: () -> Void = {}
    var openHistory: () -> Void = {}
    var openCommandMode: () -> Void = {}
    var recordingControl: () -> Void = {}
    var copyTranscript: () -> Void = {}
    var clearTranscript: () -> Void = {}
}
