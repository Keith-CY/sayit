import SwiftUI
import XCTest

@testable import SayIt

/// General, Voice Engine and Dictionary pages in light and dark. Read-only: nothing
/// here writes settings, keychain items or model files.
@MainActor
final class SettingsSnapshotTests: XCTestCase {
    private let pageWidth: CGFloat = 860

    // MARK: - General

    func testGeneralPage() throws {
        try SnapshotRenderer.snapshot("settings-general", size: CGSize(width: self.pageWidth, height: 2350)) {
            self.generalPage(accessibilityEnabled: true, capturing: false)
        }
    }

    func testGeneralPageWithoutAccessibility() throws {
        try SnapshotRenderer.snapshot(
            "settings-general-no-accessibility",
            size: CGSize(width: self.pageWidth, height: 1000),
            appearances: [.dark]
        ) {
            self.generalPage(accessibilityEnabled: false, capturing: false)
        }
    }

    func testGeneralPageCapturingShortcut() throws {
        try SnapshotRenderer.snapshot(
            "settings-general-capturing",
            size: CGSize(width: self.pageWidth, height: 1000),
            appearances: [.light]
        ) {
            self.generalPage(accessibilityEnabled: true, capturing: true)
        }
    }

    private func generalPage(accessibilityEnabled: Bool, capturing: Bool) -> some View {
        SettingsView(
            appear: .constant(true),
            visualizerNoiseThreshold: .constant(0.4),
            selectedInputUID: .constant("mic"),
            selectedOutputUID: .constant("speakers"),
            // Constant bindings: selections never change, so no device is ever switched.
            inputDevices: .constant([
                AudioDevice.Device(id: 1, uid: "mic", name: "MacBook Pro Microphone", hasInput: true, hasOutput: false),
            ]),
            outputDevices: .constant([
                AudioDevice.Device(id: 2, uid: "speakers", name: "MacBook Pro Speakers", hasInput: false, hasOutput: true),
            ]),
            accessibilityEnabled: .constant(accessibilityEnabled),
            hotkeyShortcut: .constant(HotkeyShortcut(keyCode: 61, modifierFlags: [])),
            isRecordingShortcut: .constant(capturing),
            commandModeShortcut: .constant(HotkeyShortcut(keyCode: 49, modifierFlags: [.command, .option])),
            isRecordingCommandModeShortcut: .constant(false),
            rewriteShortcut: .constant(HotkeyShortcut(keyCode: 15, modifierFlags: [.command, .option])),
            isRecordingRewriteShortcut: .constant(false),
            commandModeShortcutEnabled: .constant(true),
            rewriteShortcutEnabled: .constant(false),
            hotkeyManagerInitialized: .constant(true),
            pressAndHoldModeEnabled: .constant(false),
            enableStreamingPreview: .constant(true),
            copyToClipboard: .constant(true),
            hotkeyManager: nil,
            menuBarManager: MenuBarManager(),
            startRecording: {},
            refreshDevices: {},
            openAccessibilitySettings: {},
            restartApp: {},
            revealAppInFinder: {},
            openApplicationsFolder: {}
        )
        .environmentObject(AppServices.shared)
    }

    // MARK: - Voice Engine

    func testVoiceEnginePage() throws {
        try SnapshotRenderer.snapshot("settings-voice-engine", size: CGSize(width: self.pageWidth, height: 1900)) {
            VoiceEngineSettingsScreen(appServices: AppServices.shared, theme: .dark)
        }
    }

    func testVoiceEngineDownloadAndError() throws {
        let viewModel = VoiceEngineSettingsViewModel(settings: SettingsStore.shared, appServices: AppServices.shared)
        // Applied after onAppear, which resets the expanded row to the model in use.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            viewModel.previewSpeechModel = .whisperMedium
            viewModel.downloadingModel = .whisperLarge
            viewModel.downloadProgress = 0.42
            viewModel.issue = VoiceEngineIssue(
                title: "Whisper Small didn’t finish downloading",
                message: "The network connection was lost.",
                retry: .download(.whisperSmall)
            )
        }
        try SnapshotRenderer.snapshot(
            "settings-voice-engine-states",
            size: CGSize(width: self.pageWidth, height: 1500),
            appearances: [.dark]
        ) {
            SettingsKit.Page(title: "Voice Engine", subtitle: "States: download in progress, error, expanded row.") {
                VoiceEngineSettingsView(viewModel: viewModel, settings: SettingsStore.shared)
            }
        }
    }

    // MARK: - Dictionary

    func testDictionaryPage() throws {
        try SnapshotRenderer.snapshot("settings-dictionary", size: CGSize(width: self.pageWidth, height: 1000)) {
            CustomDictionaryView(
                previewEntries: [
                    SettingsStore.CustomDictionaryEntry(triggers: ["cloud code", "clawed code"], replacement: "Claude Code"),
                    SettingsStore.CustomDictionaryEntry(triggers: ["say it"], replacement: "SayIt"),
                    SettingsStore.CustomDictionaryEntry(triggers: ["kubernetes", "cube netties"], replacement: "Kubernetes"),
                ],
                previewTerms: [
                    .init(text: "Magickbase", weight: 10, aliases: []),
                    .init(text: "Nervos CKB", weight: 13, aliases: []),
                    .init(text: "Qwen3-ASR", weight: 5, aliases: []),
                ]
            )
        }
    }

    func testDictionaryEmptyWithError() throws {
        try SnapshotRenderer.snapshot(
            "settings-dictionary-empty",
            size: CGSize(width: self.pageWidth, height: 1000),
            appearances: [.light]
        ) {
            CustomDictionaryView(
                previewEntries: [],
                previewTerms: [],
                previewError: "The file “vocabulary.json” couldn’t be opened because you don’t have permission to view it."
            )
        }
    }

    func testDictionaryEditorSheets() throws {
        try SnapshotRenderer.snapshot("settings-dictionary-replacement-sheet", size: CGSize(width: 460, height: 420), appearances: [.dark]) {
            ReplacementEditorSheet(
                entry: SettingsStore.CustomDictionaryEntry(triggers: ["cloud code", "say it"], replacement: "Claude Code"),
                existingTriggers: ["say it"],
                onSave: { _ in }
            )
        }
        try SnapshotRenderer.snapshot("settings-dictionary-word-sheet", size: CGSize(width: 460, height: 320), appearances: [.light]) {
            CustomWordEditorSheet(term: nil, existingTerms: [], onSave: { _ in })
        }
    }
}
