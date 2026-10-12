//
//  ContentView.swift
//  SayIt
//
//  Created by Barathwaj Anandan on 7/30/25.
//

import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreGraphics
import Security
import SwiftUI

// MARK: - Sidebar

/// Main-window destinations, in sidebar order (docs/design/DESIGN.md § 6).
enum SidebarItem: Hashable, CaseIterable {
    case home
    case history
    case stats
    case commandMode
    case fileTranscription
    case general
    case voiceEngine
    case dictionary
    case aiEnhancement
    case help

    var title: String {
        switch self {
        case .home: return "Home"
        case .history: return "History"
        case .stats: return "Stats"
        case .commandMode: return "Command Mode"
        case .fileTranscription: return "File Transcription"
        case .general: return "General"
        case .voiceEngine: return "Voice Engine"
        case .dictionary: return "Dictionary"
        case .aiEnhancement: return "AI Enhancement"
        case .help: return "Help & Feedback"
        }
    }

    /// Outline SF Symbols at regular weight; never mixed with filled variants.
    var systemImage: String {
        switch self {
        case .home: return "house"
        case .history: return "clock.arrow.circlepath"
        case .stats: return "chart.bar"
        case .commandMode: return "terminal"
        case .fileTranscription: return "doc.text"
        case .general: return "gearshape"
        case .voiceEngine: return "waveform"
        case .dictionary: return "character.book.closed"
        case .aiEnhancement: return "sparkles"
        case .help: return "questionmark.circle"
        }
    }

    static let sections: [SidebarSection] = [
        SidebarSection(title: nil, items: [.home]),
        SidebarSection(title: "Activity", items: [.history, .stats]),
        SidebarSection(title: "Tools", items: [.commandMode, .fileTranscription]),
        SidebarSection(title: "Settings", items: [.general, .voiceEngine, .dictionary, .aiEnhancement]),
        SidebarSection(title: nil, items: [.help]),
    ]
}

struct SidebarSection: Identifiable {
    let title: String?
    let items: [SidebarItem]
    var id: String { self.title ?? self.items.first?.title ?? "" }
}

/// Native sidebar: sections, outline symbols, system row sizes.
struct MainSidebar: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: self.$selection) {
            ForEach(SidebarItem.sections) { section in
                if let title = section.title {
                    Section(title) {
                        self.rows(section.items)
                    }
                } else {
                    Section {
                        self.rows(section.items)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(AppIdentity.displayName)
    }

    private func rows(_ items: [SidebarItem]) -> some View {
        ForEach(items, id: \.self) { item in
            NavigationLink(value: item) {
                Label(item.title, systemImage: item.systemImage)
            }
            .accessibilityAddTraits(self.selection == item ? .isSelected : [])
        }
    }
}

struct ContentView: View {
    private enum ActiveRecordingMode: String {
        case none
        case dictate
        case edit
        case command
    }

    @EnvironmentObject private var appServices: AppServices
    @StateObject private var commandModeService = CommandModeService()
    @StateObject private var rewriteModeService = RewriteModeService()
    @EnvironmentObject private var menuBarManager: MenuBarManager
    @ObservedObject private var settings = SettingsStore.shared

    // Computed properties to access shared services from AppServices container
    // This maintains backward compatibility with the existing code while
    // removing the duplicate service instances that cause startup crashes.
    private var asr: ASRService { self.appServices.asr }
    private var audioObserver: AudioHardwareObserver { self.appServices.audioObserver }
    @Environment(\.theme) private var theme
    @State private var hotkeyManager: GlobalHotkeyManager? = nil
    @State private var hotkeyManagerInitialized: Bool = false

    @State private var appear = false
    @State private var accessibilityEnabled = false
    @State private var hotkeyShortcut: HotkeyShortcut = SettingsStore.shared.hotkeyShortcut
    @State private var commandModeHotkeyShortcut: HotkeyShortcut = SettingsStore.shared.commandModeHotkeyShortcut
    @State private var rewriteModeHotkeyShortcut: HotkeyShortcut = SettingsStore.shared.rewriteModeHotkeyShortcut
    @State private var isCommandModeShortcutEnabled: Bool = SettingsStore.shared.commandModeShortcutEnabled
    @State private var isRewriteModeShortcutEnabled: Bool = SettingsStore.shared.rewriteModeShortcutEnabled
    @State private var isRecordingForRewrite: Bool = false // Track if current recording is for rewrite mode
    @State private var isRecordingForCommand: Bool = false // Track if current recording is for command mode
    @State private var activeRecordingMode: ActiveRecordingMode = .none
    @State private var isRecordingShortcut = false
    @State private var isRecordingCommandModeShortcut = false
    @State private var isRecordingRewriteShortcut = false
    @State private var pendingModifierFlags: NSEvent.ModifierFlags = []
    @State private var pendingModifierKeyCode: UInt16?
    @State private var pendingModifierOnly = false
    @FocusState private var isTranscriptionFocused: Bool

    @State private var selectedSidebarItem: SidebarItem?
    @State private var previousSidebarItem: SidebarItem? = nil // Track previous for mode transitions
    /// A dictation has produced text at least once (persisted as `playgroundUsed`).
    @State private var firstDictationDone: Bool = SettingsStore.shared.playgroundUsed
    @State private var recordingAppInfo: (name: String, bundleId: String, windowTitle: String)? = nil
    @StateObject private var homeModelDownloader = HomeModelDownloader()

    // Audio Settings Tab State
    @State private var visualizerNoiseThreshold: Double = SettingsStore.shared.visualizerNoiseThreshold
    @State private var inputDevices: [AudioDevice.Device] = []
    @State private var outputDevices: [AudioDevice.Device] = []
    @State private var selectedInputUID: String = SettingsStore.shared.preferredInputDeviceUID ?? ""
    @State private var selectedOutputUID: String = SettingsStore.shared.preferredOutputDeviceUID ?? ""

    // AI provider context (used to normalize stored provider/model selections on launch)
    @State private var openAIBaseURL: String = ModelRepository.shared.defaultBaseURL(for: "openai")

    @State private var pressAndHoldModeEnabled: Bool = SettingsStore.shared.pressAndHoldMode
    @State private var enableStreamingPreview: Bool = SettingsStore.shared.enableStreamingPreview
    @State private var copyToClipboard: Bool = SettingsStore.shared.copyTranscriptionToClipboard

    // Preferences Tab State
    @State private var launchAtStartup: Bool = SettingsStore.shared.launchAtStartup
    @State private var showInDock: Bool = SettingsStore.shared.showInDock
    /// Accessibility was granted while running; the event tap needs a restart to pick it up.
    @State private var accessibilityNeedsRestart: Bool = false
    @State private var showAccessibilityRestartAlert: Bool = false
    private let accessibilityRestartFlagKey = AppIdentity.defaultsAccessibilityRestartKey
    /// After Accessibility is granted, how long to wait for the shortcut listener to start
    /// (12 × 0.5s) before concluding SayIt needs a restart.
    private static let listenerStartChecks = 12
    private static let listenerStartCheckInterval: UInt64 = 500_000_000
    private let hasAutoRestartedForAccessibilityKey = AppIdentity.defaultsAutoRestartedAccessibilityKey
    @State private var accessibilityPollingTask: Task<Void, Never>?

    // MARK: - Voice Recognition Model Management

    // Models scoped by provider (name -> [models])
    @State private var availableModelsByProvider: [String: [String]] = [:]
    @State private var selectedModelByProvider: [String: String] = [:]
    @State private var availableModels: [String] = ["gpt-4.1"] // derived from currentProvider
    @State private var selectedModel: String = "gpt-4.1" // derived from currentProvider

    // MARK: - Provider Management

    @State private var providerAPIKeys: [String: String] = [:] // [providerKey: apiKey]
    @State private var currentProvider: String = "openai" // canonical key: "openai" | "groq" | "custom:<id>"

    @State private var savedProviders: [SettingsStore.SavedProvider] = []
    @State private var selectedProviderID: String = SettingsStore.shared.selectedProviderID
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        let layout = AnyView(
            NavigationSplitView(columnVisibility: self.$columnVisibility) {
                self.sidebarView
                    .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
            } detail: {
                self.detailView
            }
            .navigationSplitViewStyle(.balanced)
        )

        let nav = layout.onChange(of: self.menuBarManager.requestedNavigationDestination) { _, destination in
            self.handleMenuBarNavigation(destination)
        }

        return nav.onAppear {
            self.appear = true
            self.accessibilityEnabled = self.checkAccessibilityPermissions()

            // Handle any pending menu-bar navigation (e.g., Settings clicked before window existed).
            self.handleMenuBarNavigation(self.menuBarManager.requestedNavigationDestination)
            // A fresh launch picks up Accessibility trust, so any pending restart is done.
            UserDefaults.standard.set(false, forKey: self.accessibilityRestartFlagKey)
            self.accessibilityNeedsRestart = false

            // Home is always the default destination.
            if self.selectedSidebarItem == nil {
                self.selectedSidebarItem = .home
            }

            // Allow the restart offer again if permission was revoked and is granted later.
            if !self.accessibilityEnabled {
                UserDefaults.standard.set(false, forKey: self.hasAutoRestartedForAccessibilityKey)
            }

            // Initialize menu bar after app is ready (prevents window server crash)
            self.menuBarManager.initializeMenuBar()

            // DEFENSIVE STRATEGY: Multi-layer protection against startup crash
            // Layer 1: Service consolidation (already done - no duplicate @StateObjects)
            // Layer 2: Lazy service initialization (services created on first access)
            // Layer 3: Startup gate (signalUIReady + 1.5s delay)
            // Layer 4: Delayed audio initialization (CoreAudio listeners start after UI is stable)
            //
            // This delay ensures SwiftUI's AttributeGraph has finished processing before
            // any heavy audio system work begins. The race condition between CoreAudio's
            // HALSystem initialization and SwiftUI metadata processing causes EXC_BAD_ACCESS at 0x0.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                DebugLogger.shared.info("🚦 Startup delay complete, signaling UI ready...", source: "ContentView")

                // Signal that UI is ready - this enables service initialization
                self.appServices.signalUIReady()

                DebugLogger.shared.info("🔊 Starting delayed audio initialization...", source: "ContentView")

                // Now it's safe to access services (they'll be lazily created)
                self.audioObserver.startObserving()
                self.asr.initialize()

                // Configure menu bar manager with ASR service AFTER services are initialized
                self.menuBarManager.configure(asrService: self.appServices.asr)

                // Load available devices
                self.refreshDevices()

                // Set default selection if empty
                if self.selectedInputUID.isEmpty, let defIn = AudioDevice.getDefaultInputDevice()?.uid { self.selectedInputUID = defIn }
                if self.selectedOutputUID.isEmpty, let defOut = AudioDevice.getDefaultOutputDevice()?.uid { self.selectedOutputUID = defOut }

                // Load saved preferences for UI display (but don't force system defaults)
                // SayIt should NOT control system-wide audio routing
                if let prefIn = SettingsStore.shared.preferredInputDeviceUID,
                   prefIn.isEmpty == false,
                   inputDevices.first(where: { $0.uid == prefIn }) != nil
                {
                    self.selectedInputUID = prefIn
                }

                if let prefOut = SettingsStore.shared.preferredOutputDeviceUID,
                   prefOut.isEmpty == false,
                   outputDevices.first(where: { $0.uid == prefOut }) != nil
                {
                    self.selectedOutputUID = prefOut
                }

                DebugLogger.shared.info("✅ Audio subsystems initialized", source: "ContentView")
            }

            // Set up notch click callback for expanding command conversation
            NotchOverlayManager.shared.onNotchClicked = {
                // When notch is clicked in command mode, show expanded conversation
                if !NotchContentState.shared.commandConversationHistory.isEmpty {
                    NotchOverlayManager.shared.showExpandedCommandOutput()
                }
            }

            // Set up command mode callbacks for notch
            NotchOverlayManager.shared.onCommandFollowUp = { [weak commandModeService] text in
                await commandModeService?.processFollowUpCommand(text)
            }

            // Chat management callbacks
            NotchOverlayManager.shared.onNewChat = { [weak commandModeService] in
                commandModeService?.createNewChat()
            }

            NotchOverlayManager.shared.onSwitchChat = { [weak commandModeService] chatID in
                commandModeService?.switchToChat(id: chatID)
            }

            NotchOverlayManager.shared.onClearChat = { [weak commandModeService] in
                commandModeService?.deleteCurrentChat()
            }

            // Start polling for accessibility permission if not granted
            self.startAccessibilityPolling()

            // Initialize hotkey manager with improved timing and validation
            self.initializeHotkeyManagerIfNeeded()

            // Note: Overlay is now managed by MenuBarManager (persists even when window closed)

            // Devices loaded in delayed audio initialization block
            // Device defaults and preferences handled in delayed block

            // Preload ASR model on app startup (with small delay to let app initialize)
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                await self.preloadASRModel()
            }

            // Load saved provider ID first
            self.selectedProviderID = SettingsStore.shared.selectedProviderID

            // Establish provider context first
            self.updateCurrentProvider()

            self.availableModelsByProvider = SettingsStore.shared.availableModelsByProvider
            self.selectedModelByProvider = SettingsStore.shared.selectedModelByProvider
            self.providerAPIKeys = SettingsStore.shared.providerAPIKeys
            self.savedProviders = SettingsStore.shared.savedProviders

            // Migration & cleanup: normalize provider keys and drop legacy flat lists
            var normalized: [String: [String]] = [:]
            for (key, models) in self.availableModelsByProvider {
                let lower = key.lowercased()
                let newKey: String
                // Use ModelRepository to correctly identify ALL built-in providers
                if ModelRepository.shared.isBuiltIn(lower) {
                    newKey = lower
                } else {
                    newKey = key.hasPrefix("custom:") ? key : "custom:\(key)"
                }
                // Keep only unique, trimmed models
                let clean = Array(Set(models.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })).sorted()
                if !clean.isEmpty { normalized[newKey] = clean }
            }
            self.availableModelsByProvider = normalized
            SettingsStore.shared.availableModelsByProvider = normalized

            // Normalize selectedModelByProvider keys similarly and drop invalid selections
            var normalizedSel: [String: String] = [:]
            for (key, model) in self.selectedModelByProvider {
                let lower = key.lowercased()
                // Use ModelRepository to correctly identify ALL built-in providers
                let newKey: String = ModelRepository.shared.isBuiltIn(lower) ? lower :
                    (key.hasPrefix("custom:") ? key : "custom:\(key)")
                if let list = normalized[newKey], list.contains(model) { normalizedSel[newKey] = model }
            }
            self.selectedModelByProvider = normalizedSel
            SettingsStore.shared.selectedModelByProvider = normalizedSel

            // Determine initial model list without legacy flat-list fallback
            if let saved = savedProviders.first(where: { $0.id == selectedProviderID }) {
                // Use models from saved provider
                self.availableModels = saved.models
                self.openAIBaseURL = saved.baseURL
            } else if let stored = availableModelsByProvider[currentProvider], !stored.isEmpty {
                // Use provider-specific stored list if present
                self.availableModels = stored
            } else {
                // Built-in defaults
                self.availableModels = ModelRepository.shared.defaultModels(for: self.providerKey(for: self.selectedProviderID))
            }

            // Restore previously selected model if valid
            if let sel = selectedModelByProvider[currentProvider], availableModels.contains(sel) {
                self.selectedModel = sel
            } else if let first = availableModels.first {
                self.selectedModel = first
            }

            NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
                let eventModifiers = event.modifierFlags.intersection([.function, .command, .option, .control, .shift])
                let shortcutModifiers = self.hotkeyShortcut.modifierFlags.intersection([.function, .command, .option, .control, .shift])

                let isRecordingAnyShortcut = self.isRecordingShortcut || self.isRecordingCommandModeShortcut || self.isRecordingRewriteShortcut

                if event.type == .keyDown {
                    if event.keyCode == self.hotkeyShortcut.keyCode && eventModifiers == shortcutModifiers {
                        DebugLogger.shared.debug("NSEvent monitor: Global hotkey matched on keyDown, passing event through (GlobalHotkeyManager handles)", source: "ContentView")
                        return event
                    }

                    guard isRecordingAnyShortcut else {
                        if event.keyCode == 53 {
                            // Escape pressed - handle cancellation
                            var handled = false

                            // Close expanded command notch if visible (highest priority)
                            if NotchOverlayManager.shared.isCommandOutputExpanded {
                                DebugLogger.shared
                                    .debug(
                                        "NSEvent monitor: Escape pressed, closing expanded command notch",
                                        source: "ContentView"
                                    )
                                NotchOverlayManager.shared.hideExpandedCommandOutput()
                                handled = true
                            }

                            if self.asr.isRunning {
                                DebugLogger.shared.debug("NSEvent monitor: Escape pressed, cancelling ASR recording", source: "ContentView")
                                NotchOverlayManager.shared.present(.cancelled)
                                self.clearActiveRecordingMode()
                                Task { await self.asr.stopWithoutTranscription() }
                                handled = true
                            }

                            if handled {
                                return nil // Suppress beep
                            }
                        }
                        self.resetPendingShortcutState()
                        return event
                    }

                    let keyCode = event.keyCode
                    if keyCode == 53 {
                        DebugLogger.shared.debug("NSEvent monitor: Escape pressed, cancelling shortcut recording", source: "ContentView")
                        self.isRecordingShortcut = false
                        self.isRecordingCommandModeShortcut = false
                        self.isRecordingRewriteShortcut = false
                        self.resetPendingShortcutState()
                        return nil
                    }

                    let combinedModifiers = self.pendingModifierFlags.union(eventModifiers)
                    let newShortcut = HotkeyShortcut(keyCode: keyCode, modifierFlags: combinedModifiers)
                    DebugLogger.shared.debug("NSEvent monitor: Recording new shortcut: \(newShortcut.displayString)", source: "ContentView")

                    if self.isRecordingRewriteShortcut {
                        self.rewriteModeHotkeyShortcut = newShortcut
                        SettingsStore.shared.rewriteModeHotkeyShortcut = newShortcut
                        self.hotkeyManager?.updateRewriteModeShortcut(newShortcut)
                        self.isRecordingRewriteShortcut = false
                    } else if self.isRecordingCommandModeShortcut {
                        self.commandModeHotkeyShortcut = newShortcut
                        SettingsStore.shared.commandModeHotkeyShortcut = newShortcut
                        self.hotkeyManager?.updateCommandModeShortcut(newShortcut)
                        self.isRecordingCommandModeShortcut = false
                    } else {
                        self.hotkeyShortcut = newShortcut
                        SettingsStore.shared.hotkeyShortcut = newShortcut
                        self.hotkeyManager?.updateShortcut(newShortcut)
                        self.isRecordingShortcut = false
                    }
                    self.resetPendingShortcutState()
                    DebugLogger.shared.debug("NSEvent monitor: Finished recording shortcut", source: "ContentView")
                    return nil
                } else if event.type == .flagsChanged {
                    if self.hotkeyShortcut.modifierFlags.isEmpty {
                        let isModifierKeyPressed = eventModifiers.isEmpty == false
                        if event.keyCode == self.hotkeyShortcut.keyCode && isModifierKeyPressed {
                            DebugLogger.shared.debug("NSEvent monitor: Global hotkey matched on flagsChanged, passing event through (GlobalHotkeyManager handles)", source: "ContentView")
                            return event
                        }
                    }

                    guard isRecordingAnyShortcut else {
                        self.resetPendingShortcutState()
                        return event
                    }

                    if eventModifiers.isEmpty {
                        if self.pendingModifierOnly, let modifierKeyCode = pendingModifierKeyCode {
                            let newShortcut = HotkeyShortcut(keyCode: modifierKeyCode, modifierFlags: [])
                            DebugLogger.shared.debug("NSEvent monitor: Recording modifier-only shortcut: \(newShortcut.displayString)", source: "ContentView")

                            if self.isRecordingRewriteShortcut {
                                self.rewriteModeHotkeyShortcut = newShortcut
                                SettingsStore.shared.rewriteModeHotkeyShortcut = newShortcut
                                self.hotkeyManager?.updateRewriteModeShortcut(newShortcut)
                                self.isRecordingRewriteShortcut = false
                            } else if self.isRecordingCommandModeShortcut {
                                self.commandModeHotkeyShortcut = newShortcut
                                SettingsStore.shared.commandModeHotkeyShortcut = newShortcut
                                self.hotkeyManager?.updateCommandModeShortcut(newShortcut)
                                self.isRecordingCommandModeShortcut = false
                            } else {
                                self.hotkeyShortcut = newShortcut
                                SettingsStore.shared.hotkeyShortcut = newShortcut
                                self.hotkeyManager?.updateShortcut(newShortcut)
                                self.isRecordingShortcut = false
                            }
                            self.resetPendingShortcutState()
                            DebugLogger.shared.debug("NSEvent monitor: Finished recording modifier shortcut", source: "ContentView")
                            return nil
                        }

                        self.resetPendingShortcutState()
                        DebugLogger.shared.debug("NSEvent monitor: Modifiers released without recording, continuing to wait", source: "ContentView")
                        return nil
                    }

                    // Modifiers are currently pressed
                    var actualKeyCode = event.keyCode
                    if eventModifiers.contains(.function) {
                        actualKeyCode = 63 // fn key
                    } else if eventModifiers.contains(.command) {
                        actualKeyCode = (event.keyCode == 55) ? 55 : 54 // 55 = left cmd, 54 = right cmd
                    } else if eventModifiers.contains(.option) {
                        actualKeyCode = (event.keyCode == 58) ? 58 : 61 // 58 = left opt, 61 = right opt
                    } else if eventModifiers.contains(.control) {
                        actualKeyCode = (event.keyCode == 59) ? 59 : 62 // 59 = left ctrl, 62 = right ctrl
                    } else if eventModifiers.contains(.shift) {
                        actualKeyCode = (event.keyCode == 56) ? 56 : 60 // 56 = left shift, 60 = right shift
                    }

                    self.pendingModifierFlags = eventModifiers
                    self.pendingModifierKeyCode = actualKeyCode
                    self.pendingModifierOnly = true
                    DebugLogger.shared.debug("NSEvent monitor: Modifier key pressed during recording, pending modifiers: \(self.pendingModifierFlags)", source: "ContentView")
                    return nil
                }

                return event
            }
        }
        .onChange(of: self.accessibilityEnabled) { _, enabled in
            if enabled && self.hotkeyManager != nil && !self.hotkeyManagerInitialized {
                DebugLogger.shared.debug("Accessibility enabled, reinitializing hotkey manager", source: "ContentView")
                self.hotkeyManager?.reinitialize()
            }
        }
        .onChange(of: self.selectedModel) { _, newValue in
            if newValue != "__ADD_MODEL__" {
                self.selectedModelByProvider[self.currentProvider] = newValue
                SettingsStore.shared.selectedModelByProvider = self.selectedModelByProvider
            }
        }
        .onChange(of: self.selectedProviderID) { _, newValue in
            SettingsStore.shared.selectedProviderID = newValue
        }
        .onChange(of: self.isCommandModeShortcutEnabled) { _, newValue in
            SettingsStore.shared.commandModeShortcutEnabled = newValue
            self.hotkeyManager?.updateCommandModeShortcutEnabled(newValue)

            if !newValue {
                self.isRecordingCommandModeShortcut = false

                if self.activeRecordingMode == .command {
                    if self.asr.isRunning {
                        Task { await self.asr.stopWithoutTranscription() }
                    }
                    self.clearActiveRecordingMode()
                    self.menuBarManager.setOverlayMode(.dictation)
                }
            }
        }
        .onChange(of: self.isRewriteModeShortcutEnabled) { _, newValue in
            SettingsStore.shared.rewriteModeShortcutEnabled = newValue
            self.hotkeyManager?.updateRewriteModeShortcutEnabled(newValue)

            if !newValue {
                self.isRecordingRewriteShortcut = false

                if self.activeRecordingMode == .edit {
                    if self.asr.isRunning {
                        Task { await self.asr.stopWithoutTranscription() }
                    }
                    self.clearActiveRecordingMode()
                    self.rewriteModeService.clearState()
                    self.menuBarManager.setOverlayMode(.dictation)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            self.asr.refreshMicAuthorizationStatus()

            let trusted = AXIsProcessTrusted()
            if trusted != self.accessibilityEnabled {
                self.accessibilityEnabled = trusted
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCustomDictionaryFromVoiceEngine)) { _ in
            self.selectedSidebarItem = .dictionary
        }
        .alert(
            self.asr.errorTitle,
            isPresented: Binding(
                get: { self.asr.showError },
                set: { self.asr.showError = $0 }
            )
        ) {
            self.errorRecoveryButtons
        } message: {
            Text(self.asr.errorMessage)
        }
        .alert(
            "Restart SayIt to Finish Enabling Accessibility",
            isPresented: self.$showAccessibilityRestartAlert
        ) {
            Button("Restart Now") { self.restartApp() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("SayIt needs to restart once so your shortcut works in every app. Anything you’re dictating now will be stopped.")
        }
        .onChange(of: self.asr.isRunning) { _, isRunning in
            // Audio is flowing: the overlay moves from “Starting…” to listening.
            if isRunning, self.activeRecordingMode != .none {
                NotchOverlayManager.shared.present(.listening)
            }
        }
        .onChange(of: self.asr.showError) { _, isShowing in
            // Errors during dictation must be visible even when this window is hidden.
            let phase = NotchContentState.shared.phase
            let dictationInFlight = self.activeRecordingMode != .none
                || phase == .starting || phase == .listening || phase.isWorking
            guard isShowing, dictationInFlight else { return }
            NotchOverlayManager.shared.present(.failed(self.asr.errorTitle))
        }
        .onChange(of: self.audioObserver.changeTick) { _, _ in
            // Hardware change detected → refresh device lists
            self.refreshDevices()

            // Only sync UI with system defaults when sync is enabled
            // When sync is disabled, keep the user's preferred device selection
            if SettingsStore.shared.syncAudioDevicesWithSystem {
                // Sync mode: Update UI to match current system defaults
                if let sysIn = AudioDevice.getDefaultInputDevice()?.uid {
                    self.selectedInputUID = sysIn
                }
                if let sysOut = AudioDevice.getDefaultOutputDevice()?.uid {
                    self.selectedOutputUID = sysOut
                }
            } else {
                // Independent mode: Only update if preferred device is no longer available
                if let prefIn = SettingsStore.shared.preferredInputDeviceUID,
                   inputDevices.contains(where: { $0.uid == prefIn })
                {
                    self.selectedInputUID = prefIn
                } else if let sysIn = AudioDevice.getDefaultInputDevice()?.uid {
                    // Fallback to system default if preferred device disconnected
                    self.selectedInputUID = sysIn
                    SettingsStore.shared.preferredInputDeviceUID = sysIn
                }

                if let prefOut = SettingsStore.shared.preferredOutputDeviceUID,
                   outputDevices.contains(where: { $0.uid == prefOut })
                {
                    self.selectedOutputUID = prefOut
                } else if let sysOut = AudioDevice.getDefaultOutputDevice()?.uid {
                    // Fallback to system default if preferred device disconnected
                    self.selectedOutputUID = sysOut
                    SettingsStore.shared.preferredOutputDeviceUID = sysOut
                }
            }
        }
        .onDisappear {
            NotchContentState.shared.onPromptModeSwitchRequested = nil
            NotchContentState.shared.onOverlayModeSwitchRequested = nil
            NotchContentState.shared.onReprocessLastRequested = nil
            NotchContentState.shared.onCopyLastRequested = nil
            NotchContentState.shared.onUndoLastAIRequested = nil
            NotchContentState.shared.onToggleAIProcessingRequested = nil
            NotchContentState.shared.onOpenPreferencesRequested = nil
            Task { await self.asr.stopWithoutTranscription() }
            // Note: Overlay lifecycle is now managed by MenuBarManager

            // Stop accessibility polling
            self.accessibilityPollingTask?.cancel()
            self.accessibilityPollingTask = nil
        }
        .onChange(of: self.hotkeyShortcut) { _, newValue in
            DebugLogger.shared.debug("Hotkey shortcut changed to \(newValue.displayString)", source: "ContentView")
            self.hotkeyManager?.updateShortcut(newValue)

            // Update initialization status after shortcut change
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.hotkeyManagerInitialized = self.hotkeyManager?.validateEventTapHealth() ?? false
                DebugLogger.shared.debug(
                    "Hotkey manager initialized: \(self.hotkeyManagerInitialized)",
                    source: "ContentView"
                )
            }
        }
        .onChange(of: self.selectedSidebarItem) { _, newValue in
            self.handleModeTransition(from: self.previousSidebarItem, to: newValue)
            self.previousSidebarItem = newValue
        }
    }

    // MARK: - Analytics helpers

    private func currentDictationAIModelInfo() -> (provider: String?, model: String?) {
        let providerID = SettingsStore.shared.selectedProviderID

        if providerID == "apple-intelligence" {
            return (provider: "apple-intelligence", model: "apple-intelligence")
        }

        let storedSelectedModelByProvider = SettingsStore.shared.selectedModelByProvider
        let storedSavedProviders = SettingsStore.shared.savedProviders

        let derivedProvider: String
        let derivedModel: String

        if let saved = storedSavedProviders.first(where: { $0.id == providerID }) {
            derivedProvider = "custom:\(saved.id)"
            derivedModel = storedSelectedModelByProvider[derivedProvider] ?? saved.models.first ?? ""
        } else if providerID == "openai" {
            derivedProvider = "openai"
            derivedModel = storedSelectedModelByProvider["openai"] ?? "gpt-4.1"
        } else if providerID == "groq" {
            derivedProvider = "groq"
            derivedModel = storedSelectedModelByProvider["groq"] ?? "llama-3.3-70b-versatile"
        } else {
            derivedProvider = providerID
            derivedModel = storedSelectedModelByProvider[providerID] ?? ""
        }

        let providerOut = derivedProvider.isEmpty ? nil : derivedProvider
        let modelOut = derivedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : derivedModel
        return (provider: providerOut, model: modelOut)
    }

    // MARK: - Navigation

    /// Cleans up page-local state when leaving a page. Navigation never changes global
    /// behaviour such as the overlay mode; shortcuts own that.
    private func handleModeTransition(from oldValue: SidebarItem?, to newValue: SidebarItem?) {
        DebugLogger.shared.debug("Navigation: \(String(describing: oldValue)) → \(String(describing: newValue))", source: "ContentView")

        if oldValue == .commandMode, newValue != .commandMode, NotchOverlayManager.shared.isCommandOutputExpanded {
            NotchOverlayManager.shared.hideExpandedCommandOutput()
        }
    }

    @MainActor
    private func handleMenuBarNavigation(_ destination: MenuBarNavigationDestination?) {
        guard let destination else { return }
        defer { menuBarManager.requestedNavigationDestination = nil }

        switch destination {
        case .preferences:
            self.selectedSidebarItem = .general
        }
    }

    private func resetPendingShortcutState() {
        self.pendingModifierFlags = []
        self.pendingModifierKeyCode = nil
        self.pendingModifierOnly = false
    }

    private var sidebarView: some View {
        MainSidebar(selection: self.$selectedSidebarItem)
    }

    private var detailView: some View {
        ZStack {
            self.theme.palette.contentBackground
                .ignoresSafeArea()

            self.detailContent
                .id(self.selectedSidebarItem ?? .home)
                .transition(.opacity)
        }
        // A quiet cross-fade between pages; Motion.fade is also the Reduce Motion fallback.
        .animation(Motion.fade, value: self.selectedSidebarItem)
    }

    private var detailContent: AnyView {
        switch self.selectedSidebarItem ?? .home {
        case .home:
            return AnyView(self.homeView)
        case .voiceEngine:
            return AnyView(VoiceEngineSettingsScreen(
                appServices: self.appServices,
                theme: self.theme
            ))
        case .aiEnhancement:
            return AnyView(AIEnhancementSettingsScreen(
                menuBarManager: self.menuBarManager,
                theme: self.theme
            ))
        case .help:
            return AnyView(FeedbackView())
        case .general:
            return AnyView(self.generalSettingsView)
        case .fileTranscription:
            return AnyView(MeetingTranscriptionView(asrService: self.asr))
        case .dictionary:
            return AnyView(CustomDictionaryView())
        case .stats:
            return AnyView(StatsView())
        case .commandMode:
            return AnyView(self.commandModeView)
        case .history:
            return AnyView(TranscriptionHistoryView())
        }
    }

    // MARK: - Home

    private var homeView: some View {
        HomeScreen(
            downloader: self.homeModelDownloader,
            selectedSidebarItem: self.$selectedSidebarItem,
            firstDictationDone: self.$firstDictationDone,
            isTranscriptionFocused: self.$isTranscriptionFocused,
            accessibilityEnabled: self.accessibilityEnabled,
            accessibilityNeedsRestart: self.accessibilityNeedsRestart,
            stopAndProcessTranscription: { await self.stopAndProcessTranscription() },
            startRecording: self.startRecording,
            openAccessibilitySettings: self.openAccessibilitySettings,
            restartApp: self.restartApp
        )
    }

    // MARK: - General Settings

    private var generalSettingsView: some View {
        SettingsView(
            appear: self.$appear,
            visualizerNoiseThreshold: self.$visualizerNoiseThreshold,
            selectedInputUID: self.$selectedInputUID,
            selectedOutputUID: self.$selectedOutputUID,
            inputDevices: self.$inputDevices,
            outputDevices: self.$outputDevices,
            accessibilityEnabled: self.$accessibilityEnabled,
            hotkeyShortcut: self.$hotkeyShortcut,
            isRecordingShortcut: self.$isRecordingShortcut,
            commandModeShortcut: self.$commandModeHotkeyShortcut,
            isRecordingCommandModeShortcut: self.$isRecordingCommandModeShortcut,
            rewriteShortcut: self.$rewriteModeHotkeyShortcut,
            isRecordingRewriteShortcut: self.$isRecordingRewriteShortcut,
            commandModeShortcutEnabled: self.$isCommandModeShortcutEnabled,
            rewriteShortcutEnabled: self.$isRewriteModeShortcutEnabled,
            hotkeyManagerInitialized: self.$hotkeyManagerInitialized,
            pressAndHoldModeEnabled: self.$pressAndHoldModeEnabled,
            enableStreamingPreview: self.$enableStreamingPreview,
            copyToClipboard: self.$copyToClipboard,
            hotkeyManager: self.hotkeyManager,
            menuBarManager: self.menuBarManager,
            startRecording: self.startRecording,
            refreshDevices: self.refreshDevices,
            openAccessibilitySettings: self.openAccessibilitySettings,
            restartApp: self.restartApp,
            revealAppInFinder: self.revealAppInFinder,
            openApplicationsFolder: self.openApplicationsFolder
        )
    }

    private var commandModeView: some View {
        CommandModeView(service: self.commandModeService, onClose: {
            self.selectedSidebarItem = .home
        })
    }

    // MARK: - Error Recovery

    /// Recovery actions for the main-window error alert, chosen from the error title.
    @ViewBuilder
    private var errorRecoveryButtons: some View {
        let title = self.asr.errorTitle.lowercased()
        if title.contains("microphone") {
            Button("Open System Settings") { self.asr.openSystemSettingsForMic() }
            Button("Close", role: .cancel) {}
        } else if title.contains("model") || title.contains("voice") || title.contains("speech") {
            Button("Try Again") {
                Task {
                    do {
                        try await self.asr.ensureAsrReady()
                    } catch {
                        self.asr.errorMessage = error.localizedDescription
                        self.asr.showError = true
                    }
                }
            }
            Button("Open Voice Engine") { self.selectedSidebarItem = .voiceEngine }
            Button("Close", role: .cancel) {}
        } else {
            Button("OK", role: .cancel) {}
        }
    }

    // Audio settings merged into SettingsView

    private func refreshDevices() {
        // Query CoreAudio off the main thread — during device topology changes, synchronous
        // CoreAudio calls on main can deadlock while the HAL is still settling.
        DispatchQueue.global(qos: .userInitiated).async {
            let inputs = AudioDevice.listInputDevices()
            let outputs = AudioDevice.listOutputDevices()
            DispatchQueue.main.async {
                self.inputDevices = inputs
                self.outputDevices = outputs
            }
        }
    }

    // MARK: - Provider Management Functions

    private func providerKey(for providerID: String) -> String {
        // Built-in providers use their ID directly
        if ModelRepository.shared.isBuiltIn(providerID) { return providerID }
        // Saved providers use their stable id with "custom:" prefix (if not already present)
        if providerID.hasPrefix("custom:") { return providerID }
        return providerID.isEmpty ? self.currentProvider : "custom:\(providerID)"
    }

    private func updateCurrentProvider() {
        // Map baseURL to canonical key for built-ins; else keep existing
        let url = self.openAIBaseURL.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if url.contains("openai.com") { self.currentProvider = "openai"; return }
        if url.contains("groq.com") { self.currentProvider = "groq"; return }
        // For saved/custom, keep current or derive from selectedProviderID
        self.currentProvider = self.providerKey(for: self.selectedProviderID)
    }

    // MARK: - App Detection and Context-Aware Prompts

    private func getCurrentAppInfo() -> (name: String, bundleId: String, windowTitle: String) {
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            let name = frontmostApp.localizedName ?? "Unknown"
            let bundleId = frontmostApp.bundleIdentifier ?? "unknown"
            let title = self.getFrontmostWindowTitle(ownerPid: frontmostApp.processIdentifier) ?? ""
            return (name: name, bundleId: bundleId, windowTitle: title)
        }
        return (name: "Unknown", bundleId: "unknown", windowTitle: "")
    }

    /// Best-effort frontmost window title lookup for the current app
    private func getFrontmostWindowTitle(ownerPid: pid_t) -> String? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for info in windowInfo {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid == ownerPid else { continue }
            if let name = info[kCGWindowName as String] as? String, name.isEmpty == false {
                return name
            }
        }
        return nil
    }

    // MARK: - Commented out app-specific prompts - using general processing only

    /*
     private func getContextualPrompt(for appInfo: (name: String, bundleId: String, windowTitle: String)) -> String {
         let appName = appInfo.name
         let bundleId = appInfo.bundleId.lowercased()
         let windowTitle = appInfo.windowTitle.lowercased()

         // Code editors and IDEs
         if bundleId.contains("xcode") || bundleId.contains("vscode") || bundleId.contains("sublime") ||
            bundleId.contains("atom") || bundleId.contains("jetbrains") || bundleId.contains("cursor") ||
            bundleId.contains("vim") || bundleId.contains("emacs") || appName.lowercased().contains("code")
         {
             return "Clean up this transcribed text for code editor \(appName). Make the smallest necessary mechanical edits; do not add or invent content or answer questions. Remove fillers and false starts. Correct programming terms and obvious transcription errors. Preserve meaning and tone."
         }

         // Email applications
         else if bundleId.contains("mail") || bundleId.contains("outlook") || bundleId.contains("thunderbird") ||
                 bundleId.contains("airmail") || bundleId.contains("spark")
         {
             return "Clean up this transcribed text for email app \(appName). Make minimal edits only; do not add or invent content or answer questions. Remove fillers and false starts. Fix grammar, punctuation, and capitalization while preserving meaning and tone."
         }

         // Messaging and chat applications
         else if bundleId.contains("messages") || bundleId.contains("slack") || bundleId.contains("discord") ||
                 bundleId.contains("telegram") || bundleId.contains("whatsapp") || bundleId.contains("signal") ||
                 bundleId.contains("teams") || bundleId.contains("zoom")
         {
             return "Clean up this transcribed text for messaging app \(appName). Make minimal edits only; do not add or invent content or answer questions. Remove fillers and false starts. Fix basic grammar and clarity while keeping the casual tone."
         }

         // Document editors and word processors
         else if bundleId.contains("pages") || bundleId.contains("word") || bundleId.contains("docs") ||
                 bundleId.contains("writer") || bundleId.contains("notion") || bundleId.contains("bear") ||
                 bundleId.contains("ulysses") || bundleId.contains("scrivener")
         {
             return "Clean up this transcribed text for document editor \(appName). Make minimal edits only; do not add or invent content or answer questions. Remove fillers and false starts. Fix grammar, punctuation, and structure while preserving meaning."
         }

         // Note-taking applications
         else if bundleId.contains("notes") || bundleId.contains("obsidian") || bundleId.contains("roam") ||
                 bundleId.contains("logseq") || bundleId.contains("evernote") || bundleId.contains("onenote")
         {
             return "Clean up this transcribed text for note-taking app \(appName). Make minimal edits only; do not add or invent content or answer questions. Remove fillers and false starts. Fix grammar and organize into clear, readable notes without adding information."
         }

         // Browsers (various web apps). Include: Safari, Chrome, Firefox, Edge, Arc, Brave, Dia, Comet
         else if bundleId.contains("safari") || bundleId.contains("chrome") || bundleId.contains("firefox") ||
                 bundleId.contains("edge") || bundleId.contains("arc") || bundleId.contains("brave") ||
                 bundleId.contains("dia") || bundleId.contains("comet") ||
                 appName.lowercased().contains("safari") || appName.lowercased().contains("chrome") ||
                 appName.lowercased().contains("arc") || appName.lowercased().contains("brave") ||
                 appName.lowercased().contains("dia") || appName.lowercased().contains("comet")
         {
             // Infer common web apps from window title for better context
             if let inferred = inferWebContext(from: windowTitle, appName: appName) {
                 return inferred
             }
             return "Clean up this transcribed text for web browser \(appName). Make minimal edits only; do not add or invent content or answer questions. Remove fillers and false starts. Fix grammar and basic formatting while preserving meaning."
         }

         // Terminal and command line tools
         else if bundleId.contains("terminal") || bundleId.contains("iterm") || bundleId.contains("console") ||
                 appName.lowercased().contains("terminal")
         {
             return "Clean up this transcribed text for terminal \(appName). Make minimal edits only; do not add or invent content or answer questions. Remove fillers and false starts. Fix command syntax, file paths, and technical terms without adding options or commands."
         }

         // Social media and creative apps
         else if bundleId.contains("twitter") || bundleId.contains("facebook") || bundleId.contains("instagram") ||
                 bundleId.contains("tiktok") || bundleId.contains("linkedin")
         {
             return "Clean up this transcribed text for social media app \(appName). Make minimal edits only; do not add or invent content or answer questions. Remove fillers and false starts. Fix basic grammar while keeping the natural, engaging tone."
         }

         // Default fallback
         else
         {
             return "Clean up this transcribed text for \(appName). Make minimal edits only; do not add or invent content or answer questions. Remove fillers and false starts. Fix grammar, punctuation, and formatting while preserving meaning and tone."
         }
     }
     */

    /*
     /// Infer web-app specific prompt from a browser window title
     private func inferWebContext(from windowTitle: String, appName: String) -> String? {
         let title = windowTitle
         // Email (Gmail, Outlook Web)
         if title.contains("gmail") || title.contains("inbox") || title.contains("outlook") {
             return "Clean up this transcribed text for email app \(appName) (web). Make minimal edits only; do not add or invent content or answer questions. Remove fillers and false starts. Fix grammar, punctuation, and capitalization while preserving meaning."
         }
         // Messaging (Slack, Discord, Teams, Telegram, WhatsApp)
         if title.contains("slack") || title.contains("discord") || title.contains("teams") || title.contains("telegram") || title.contains("whatsapp") {
             return "Clean up this transcribed text for messaging app \(appName) (web). Make minimal edits only; do not add or invent content or answer questions. Remove fillers and false starts. Fix basic grammar and clarity while keeping the casual tone."
         }
         // Documents (Google Docs/Sheets, Notion, Confluence)
         if title.contains("google docs") || title.contains("docs") || title.contains("notion") || title.contains("confluence") || title.contains("google sheets") || title.contains("sheet") {
             return "Clean up this transcribed text for a document editor in \(appName). Make minimal edits only; do not add or invent content or answer questions. Remove fillers and false starts. Improve grammar, structure, and readability without adding information."
         }
         // Code (GitHub, Stack Overflow, online IDEs)
         if title.contains("github") || title.contains("stack overflow") || title.contains("stackexchange") || title.contains("replit") || title.contains("codesandbox") {
             return "Clean up this transcribed text for code-related context in \(appName). Make minimal edits only; do not add or invent content or answer questions. Remove fillers and false starts. Correct programming terms and obvious errors without adding explanations."
         }
         // Project/issue tracking (Jira, Linear, Asana)
         if title.contains("jira") || title.contains("linear") || title.contains("asana") || title.contains("clickup") {
             return "Clean up this transcribed text for project management context in \(appName). Make minimal edits only; do not add or invent content or answer questions. Remove fillers and false starts. Keep the text concise and clear without adding commentary."
         }
         return nil
     }
     */

    /// Build a general system prompt with voice editing commands support
    private func buildSystemPrompt(appInfo: (name: String, bundleId: String, windowTitle: String)) -> String {
        _ = appInfo
        return SettingsStore.shared.effectiveSystemPrompt(for: .dictate)
    }

    private var shouldTracePromptProcessing: Bool {
        self.forcePromptTraceToConsole ||
            UserDefaults.standard.bool(forKey: "EnableDebugLogs")
    }

    private var forcePromptTraceToConsole: Bool {
        ProcessInfo.processInfo.environment["SAYIT_PROMPT_TRACE"] == "1"
    }

    private func logDictationPromptTrace(_ title: String, value: String) {
        let line = "[PromptTrace][Dictate] \(title):\n\(value)"
        if self.forcePromptTraceToConsole {
            print(line)
        }
        DebugLogger.shared.debug(line, source: "ContentView")
    }

    private func customPromptAnalyticsProperties(promptSource: String, overrideEmpty: Bool?) -> [String: Any] {
        let providerID = SettingsStore.shared.selectedProviderID
        let providerKey = self.providerKey(for: providerID)
        let selectedModel = SettingsStore.shared.selectedModelByProvider[providerKey] ?? SettingsStore.shared.selectedModel ?? ""
        let isCustomProvider = !ModelRepository.shared.isBuiltIn(providerID)
        let providerName = isCustomProvider ? "Custom Provider" : ModelRepository.shared.displayName(for: providerID)

        var properties: [String: Any] = [
            "prompt_source": promptSource,
            "provider_id": isCustomProvider ? "custom" : providerID,
            "provider_name": providerName,
            "provider_type": isCustomProvider ? "custom" : "built_in",
        ]
        if !selectedModel.isEmpty {
            properties["model"] = isCustomProvider ? "custom" : selectedModel
        }
        if let overrideEmpty {
            properties["override_empty"] = overrideEmpty
        }
        return properties
    }

    // MARK: - Local Endpoint Detection

    private func isLocalEndpoint(_ urlString: String) -> Bool {
        return ModelRepository.shared.isLocalEndpoint(urlString)
    }

    // NOTE: Thinking token filtering is now handled by LLMClient.stripThinkingTags()

    // MARK: - Modular AI Processing

    private enum AITextProcessingResult {
        case success(String)
        case failure(String)
    }

    private func processTextWithAI(
        _ inputText: String,
        overrideSystemPrompt: String? = nil
    ) async -> AITextProcessingResult {
        // CRITICAL FIX: Read current settings from SettingsStore, not stale @State copies
        // This ensures AI provider/model changes in AISettingsView take effect immediately
        let settings = SettingsStore.shared
        let currentSelectedProviderID = settings.selectedProviderID
        let storedSelectedModelByProvider = settings.selectedModelByProvider
        let storedSavedProviders = settings.savedProviders

        // Derive currentProvider and openAIBaseURL from the current settings
        let derivedCurrentProvider = self.providerKey(for: currentSelectedProviderID)
        let derivedBaseURL = settings.baseURL(for: currentSelectedProviderID)
        let derivedSelectedModel = storedSelectedModelByProvider[derivedCurrentProvider]
            ?? storedSavedProviders.first(where: { $0.id == currentSelectedProviderID })?.models.first
            ?? ModelRepository.shared.defaultModels(for: currentSelectedProviderID).first
            ?? ""

        DebugLogger.shared.debug("processTextWithAI using provider=\(derivedCurrentProvider), model=\(derivedSelectedModel)", source: "ContentView")

        // Route to Apple Intelligence if selected
        if currentSelectedProviderID == "apple-intelligence" {
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                let provider = AppleIntelligenceProvider()
                let appInfo = self.recordingAppInfo ?? self.getCurrentAppInfo()
                let systemPrompt = self.buildSystemPrompt(appInfo: appInfo)
                if self.shouldTracePromptProcessing {
                    let selectedProfile = SettingsStore.shared.selectedPromptProfile(for: .dictate)
                    let selectedPromptName: String = {
                        if let profile = selectedProfile {
                            return profile.name.isEmpty ? "Untitled Prompt" : profile.name
                        }
                        return "Default Dictate"
                    }()
                    self.logDictationPromptTrace("Selected prompt profile", value: selectedPromptName)
                    self.logDictationPromptTrace("Prompt body (custom/default body)", value: SettingsStore.shared.effectivePromptBody(for: .dictate))
                    self.logDictationPromptTrace("Built-in default system prompt (baseline)", value: SettingsStore.defaultSystemPromptText(for: .dictate))
                    self.logDictationPromptTrace("Final system prompt sent to model", value: systemPrompt)
                    self.logDictationPromptTrace("Input transcription (Q)", value: inputText)
                    self.logDictationPromptTrace("Selected context text", value: "<none (dictation mode)>")
                }
                DebugLogger.shared.debug("Using Apple Intelligence for transcription cleanup", source: "ContentView")
                do {
                    let output = try await provider.process(systemPrompt: systemPrompt, userText: inputText)
                    let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedOutput.isEmpty else {
                        return .failure("Apple Intelligence returned no text.")
                    }
                    if self.shouldTracePromptProcessing {
                        self.logDictationPromptTrace("Model answer (A)", value: output)
                    }
                    return .success(output)
                } catch {
                    DebugLogger.shared.error(
                        "Apple Intelligence error: \(error.localizedDescription)",
                        source: "ContentView"
                    )
                    return .failure(error.localizedDescription)
                }
            }
            #endif
            return .failure(AppleIntelligenceService.unavailabilityReason ?? "Apple Intelligence is unavailable.")
        }

        guard !derivedBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Base URL not set for \(ModelRepository.shared.displayName(for: currentSelectedProviderID)). Configure it in AI Settings.")
        }

        guard !derivedSelectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("No model selected for \(ModelRepository.shared.displayName(for: currentSelectedProviderID)).")
        }

        // Skip API key validation for local endpoints
        let isLocal = self.isLocalEndpoint(derivedBaseURL)
        let apiKey = settings.getAPIKey(for: currentSelectedProviderID) ?? ""

        if !isLocal {
            guard !apiKey.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else {
                return .failure("API Key not set for \(derivedCurrentProvider).")
            }
        }

        // Get app context captured at start of recording if available
        let appInfo = self.recordingAppInfo ?? self.getCurrentAppInfo()
        let systemPrompt: String = {
            let override = overrideSystemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !override.isEmpty { return override }
            return self.buildSystemPrompt(appInfo: appInfo)
        }()
        DebugLogger.shared.debug("Using app context for AI: app=\(appInfo.name), bundleId=\(appInfo.bundleId), title=\(appInfo.windowTitle)", source: "ContentView")
        if self.shouldTracePromptProcessing {
            let selectedProfile = SettingsStore.shared.selectedPromptProfile(for: .dictate)
            let selectedPromptName: String = {
                if let profile = selectedProfile {
                    return profile.name.isEmpty ? "Untitled Prompt" : profile.name
                }
                return "Default Dictate"
            }()
            self.logDictationPromptTrace("Selected prompt profile", value: selectedPromptName)
            self.logDictationPromptTrace("Prompt body (custom/default body)", value: SettingsStore.shared.effectivePromptBody(for: .dictate))
            self.logDictationPromptTrace("Built-in default system prompt (baseline)", value: SettingsStore.defaultSystemPromptText(for: .dictate))
            self.logDictationPromptTrace("Prompt override in use", value: (overrideSystemPrompt?.isEmpty == false) ? "yes" : "no")
            if let overrideSystemPrompt, !overrideSystemPrompt.isEmpty {
                self.logDictationPromptTrace("Override system prompt", value: overrideSystemPrompt)
            }
            self.logDictationPromptTrace("Final system prompt sent to model", value: systemPrompt)
            self.logDictationPromptTrace("Input transcription (Q)", value: inputText)
            self.logDictationPromptTrace("Selected context text", value: "<none (dictation mode)>")
        }

        // Check if this is a reasoning model that doesn't support temperature parameter
        let modelLower = derivedSelectedModel.lowercased()
        let isReasoningModel = modelLower.hasPrefix("o1") || modelLower.hasPrefix("o3") || modelLower.hasPrefix("gpt-5")

        // Get reasoning config for this model (uses per-model settings or auto-detection)
        // This handles custom parameters like reasoning_effort, enable_thinking, etc.
        let providerKey = self.providerKey(for: currentSelectedProviderID)
        let reasoningConfig = SettingsStore.shared.getReasoningConfig(forModel: derivedSelectedModel, provider: providerKey)

        // Build extra parameters from reasoning config
        var extraParams: [String: Any] = [:]
        if let config = reasoningConfig, config.isEnabled {
            if config.parameterName == "enable_thinking" {
                // DeepSeek uses boolean
                extraParams = [config.parameterName: config.parameterValue == "true"]
            } else {
                // OpenAI/Groq use string values (reasoning_effort, etc.)
                extraParams = [config.parameterName: config.parameterValue]
            }
            DebugLogger.shared.debug(
                "Added reasoning param: \(config.parameterName)=\(config.parameterValue)",
                source: "ContentView"
            )
        }

        // Build messages array
        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": inputText],
        ]

        // NOTE: Transcription doesn't need streaming - the full result appears at once
        // Streaming is only useful for Command/Rewrite modes where real-time display helps
        // Using non-streaming is simpler and more reliable for transcription cleanup
        let enableStreaming = false // Hardcoded off for transcription

        // Build LLMClient configuration
        // Note: No onContentChunk callback needed since we don't display real-time
        // Thinking tokens are extracted but not displayed (no onThinkingChunk)
        let config = LLMClient.Config(
            messages: messages,
            model: derivedSelectedModel,
            baseURL: derivedBaseURL,
            apiKey: apiKey,
            streaming: enableStreaming,
            tools: [],
            temperature: isReasoningModel ? nil : 0.0,
            extraParameters: extraParams,
            providerID: currentSelectedProviderID
        )

        DebugLogger.shared.info("Using LLMClient for transcription (streaming=\(enableStreaming))", source: "ContentView")

        do {
            let response = try await LLMClient.shared.call(config)

            // Log thinking if present (for debugging)
            if let thinking = response.thinking {
                DebugLogger.shared.debug("LLM thinking tokens extracted (\(thinking.count) chars)", source: "ContentView")
                if self.shouldTracePromptProcessing {
                    self.logDictationPromptTrace("Model thinking", value: thinking)
                }
            }

            if self.shouldTracePromptProcessing {
                self.logDictationPromptTrace("Model answer (A)", value: response.content)
            }

            guard !response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure("The selected model returned no text.")
            }
            return .success(response.content)
        } catch {
            DebugLogger.shared.error("AI API error: \(error.localizedDescription)", source: "ContentView")
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - Streaming Response Handler (DEPRECATED - Now handled by LLMClient)

    // This method is no longer used - LLMClient.call() handles streaming internally

    // MARK: - Stop and Process Transcription

    /// True when the user cancelled (Esc / close button) after `token` was captured.
    private func wasCancelled(since token: UInt64) -> Bool {
        NotchContentState.shared.cancellationCount != token
    }

    private func stopAndProcessTranscription() async {
        DebugLogger.shared.debug("stopAndProcessTranscription called", source: "ContentView")

        // Check if we're in rewrite or command mode
        let modeAtStop = self.activeRecordingMode
        let wasRewriteMode = modeAtStop == .edit || self.isRecordingForRewrite
        let wasCommandMode = modeAtStop == .command || self.isRecordingForCommand
        DebugLogger.shared.info(
            "Routing decision snapshot | activeMode=\(modeAtStop.rawValue) | rewrite=\(wasRewriteMode) | command=\(wasCommandMode) | overlay=\(NotchContentState.shared.mode.rawValue)",
            source: "ContentView"
        )

        self.clearActiveRecordingMode()
        let cancelToken = NotchContentState.shared.cancellationCount

        // Keep the overlay visible in its “Transcribing” phase while asr.stop() finalizes;
        // slower models (Whisper Medium/Large) can take a moment.
        DebugLogger.shared.debug("Showing transcription processing state", source: "ContentView")
        self.menuBarManager.setProcessing(true)
        NotchOverlayManager.shared.present(.transcribing)

        // Give SwiftUI a chance to render the processing state before we do heavier work
        // (ASR finalization + optional AI post-processing).
        await Task.yield()

        // Stop the ASR service and wait for transcription to complete
        // The processing indicator will stay visible during this phase
        let transcribedText = await asr.stop()

        if self.wasCancelled(since: cancelToken) {
            DebugLogger.shared.info("Dictation cancelled while transcribing; discarding text", source: "ContentView")
            self.menuBarManager.setProcessing(false)
            return
        }

        guard transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            DebugLogger.shared.debug("Transcription returned empty text", source: "ContentView")
            // Say why nothing was typed before the overlay leaves.
            if self.asr.showError {
                NotchOverlayManager.shared.present(.failed(self.asr.errorTitle))
            } else {
                NotchOverlayManager.shared.present(.done(.noSpeech))
            }
            self.menuBarManager.setProcessing(false)
            return
        }

        // Keep what was heard on screen (de-emphasized) while any further work runs.
        NotchOverlayManager.shared.updateTranscriptionText(transcribedText)

        // Prompt Test Mode: reroute dictation hotkey output into the prompt editor (no typing/clipboard/history).
        let promptTest = DictationPromptTestCoordinator.shared
        if promptTest.isActive {
            promptTest.lastTranscriptionText = transcribedText
            promptTest.lastOutputText = ""
            promptTest.lastError = ""

            guard DictationAIPostProcessingGate.isConfigured() else {
                promptTest.lastError = "AI Enhancement isn’t set up. Turn it on and choose a provider and model (and an API key for cloud providers)."
                NotchOverlayManager.shared.present(.idle)
                self.menuBarManager.setProcessing(false)
                return
            }

            promptTest.isProcessing = true
            NotchOverlayManager.shared.present(.refining)
            defer {
                // Prompt tests write into the prompt editor, not another app.
                NotchOverlayManager.shared.present(.idle)
                self.menuBarManager.setProcessing(false)
                promptTest.isProcessing = false
            }

            let result = await self.processTextWithAI(
                transcribedText,
                overrideSystemPrompt: promptTest.draftPromptText
            )
            switch result {
            case let .success(output):
                promptTest.lastOutputText = ASRService.applyGAAVFormatting(output)
            case let .failure(message):
                promptTest.lastError = message
            }
            return
        }

        // If this was a rewrite recording, process the rewrite instead of typing
        if wasRewriteMode {
            DebugLogger.shared.info("Processing rewrite with instruction: \(transcribedText)", source: "ContentView")
            await self.processRewriteWithVoiceInstruction(transcribedText)
            AnalyticsService.shared.capture(
                .transcriptionCompleted,
                properties: [
                    "mode": AnalyticsMode.rewrite.rawValue,
                    "words_bucket": AnalyticsBuckets.bucketWords(AnalyticsBuckets.wordCount(in: transcribedText)),
                    "ai_used": true,
                ]
            )
            return
        }

        // If this was a command recording, process the command
        if wasCommandMode {
            DebugLogger.shared.info("Processing command: \(transcribedText)", source: "ContentView")
            await self.processCommandWithVoice(transcribedText)
            AnalyticsService.shared.capture(
                .transcriptionCompleted,
                properties: [
                    "mode": AnalyticsMode.command.rawValue,
                    "words_bucket": AnalyticsBuckets.bucketWords(AnalyticsBuckets.wordCount(in: transcribedText)),
                    "ai_used": true,
                ]
            )
            return
        }

        var finalText: String
        var aiFailed = false

        // Check if we should use AI processing
        let shouldUseAI = DictationAIPostProcessingGate.isConfigured()

        if shouldUseAI {
            DebugLogger.shared.debug("Routing transcription through AI post-processing", source: "ContentView")
            NotchOverlayManager.shared.present(.refining)

            // Ensure the status label becomes visible immediately.
            await Task.yield()

            switch await self.processTextWithAI(transcribedText) {
            case let .success(output):
                finalText = output
            case let .failure(message):
                DebugLogger.shared.warning(
                    "AI cleanup failed; using the original transcription: \(message)",
                    source: "ContentView"
                )
                finalText = transcribedText
                aiFailed = true
            }
        } else {
            finalText = transcribedText
        }

        if self.wasCancelled(since: cancelToken) {
            DebugLogger.shared.info("Dictation cancelled while enhancing; discarding text", source: "ContentView")
            self.menuBarManager.setProcessing(false)
            return
        }

        // Apply GAAV formatting as the FINAL step (after AI post-processing)
        // This ensures the user's preference for no capitalization/period is respected
        finalText = ASRService.applyGAAVFormatting(finalText)

        DebugLogger.shared.info("Transcription finalized (chars: \(finalText.count))", source: "ContentView")

        AnalyticsService.shared.capture(
            .transcriptionCompleted,
            properties: [
                "mode": AnalyticsMode.dictation.rawValue,
                "words_bucket": AnalyticsBuckets.bucketWords(AnalyticsBuckets.wordCount(in: finalText)),
                "ai_used": shouldUseAI,
                "ai_changed_text": transcribedText != finalText,
            ]
        )

        // Save to transcription history (transcription mode only, if enabled)
        if SettingsStore.shared.saveTranscriptionHistory {
            let appInfo = self.recordingAppInfo ?? self.getCurrentAppInfo()
            TranscriptionHistoryStore.shared.addEntry(
                rawText: transcribedText,
                processedText: finalText,
                appName: appInfo.name,
                windowTitle: appInfo.windowTitle
            )
        }

        // Copy to clipboard if enabled (happens before typing as a backup)
        if SettingsStore.shared.copyTranscriptionToClipboard {
            ClipboardService.copyToClipboard(finalText)
            AnalyticsService.shared.capture(
                .outputDelivered,
                properties: [
                    "mode": AnalyticsMode.dictation.rawValue,
                    "method": AnalyticsOutputMethod.clipboard.rawValue,
                ]
            )
        }

        var didTypeExternally = false
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let frontmostName = frontmostApp?.localizedName ?? "Unknown"
        let isSayItFrontmost = frontmostApp?.bundleIdentifier?.contains("sayit") == true
        let wantsExternalTyping = !isSayItFrontmost || self.isTranscriptionFocused == false
        // Typing into other apps needs Accessibility; without it, fall back to the clipboard.
        let canTypeExternally = AXIsProcessTrusted()
        let shouldTypeExternally = wantsExternalTyping && canTypeExternally

        DebugLogger.shared.debug(
            "Typing decision → frontmost: \(frontmostName), sayItFrontmost: \(isSayItFrontmost), editorFocused: \(self.isTranscriptionFocused), willTypeExternally: \(shouldTypeExternally)",
            source: "ContentView"
        )

        // The first dictation that produces text completes setup.
        if !self.firstDictationDone {
            self.firstDictationDone = true
            SettingsStore.shared.playgroundUsed = true
        }

        // Report the outcome before leaving the processing state, so the overlay shows it
        // for its dwell time instead of disappearing.
        let outcome: OverlayOutcome
        if wantsExternalTyping, !canTypeExternally {
            if !SettingsStore.shared.copyTranscriptionToClipboard {
                ClipboardService.copyToClipboard(finalText)
            }
            outcome = .copied
        } else {
            outcome = aiFailed ? .insertedOriginal : .inserted
        }
        NotchOverlayManager.shared.present(.done(outcome))
        self.menuBarManager.setProcessing(false)

        if shouldTypeExternally {
            // Await typing completion before proceeding to edit tracker
            // This ensures the tracker window opens after text has been typed
            await self.restoreFocusToRecordingTarget()
            self.asr.typeTextToActiveField(
                finalText,
                preferredTargetPID: NotchContentState.shared.recordingTargetPID
            )
            didTypeExternally = true
        }

        if didTypeExternally {
            AnalyticsService.shared.capture(
                .outputDelivered,
                properties: [
                    "mode": AnalyticsMode.dictation.rawValue,
                    "method": AnalyticsOutputMethod.typed.rawValue,
                ]
            )

            // Now that typing is complete, start the edit tracker
            let wordsBucket = AnalyticsBuckets.bucketWords(AnalyticsBuckets.wordCount(in: finalText))
            let modelInfo = self.currentDictationAIModelInfo()
            await PostTranscriptionEditTracker.shared.markTranscriptionCompleted(
                mode: AnalyticsMode.dictation.rawValue,
                outputMethod: AnalyticsOutputMethod.typed.rawValue,
                wordsBucket: wordsBucket,
                aiUsed: shouldUseAI,
                aiModel: modelInfo.model,
                aiProvider: modelInfo.provider
            )

            NotchOverlayManager.shared.hide()
        } else if SettingsStore.shared.copyTranscriptionToClipboard == false,
                  SettingsStore.shared.saveTranscriptionHistory
        {
            AnalyticsService.shared.capture(
                .outputDelivered,
                properties: [
                    "mode": AnalyticsMode.dictation.rawValue,
                    "method": AnalyticsOutputMethod.historyOnly.rawValue,
                ]
            )
        }
    }

    private func reprocessLastDictationFromHistory() {
        guard let last = TranscriptionHistoryStore.shared.entries.first else {
            DebugLogger.shared.info("Actions: Reprocess requested but history is empty", source: "ContentView")
            return
        }

        let rawText = last.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else {
            DebugLogger.shared.info("Actions: Reprocess skipped because latest history raw text is empty", source: "ContentView")
            return
        }

        DebugLogger.shared.info("Actions: Reprocessing latest dictation history entry", source: "ContentView")
        Task { @MainActor in
            await self.reprocessDictationText(rawText)
        }
    }

    private func copyLastDictationFromHistory() {
        guard let last = TranscriptionHistoryStore.shared.entries.first else {
            DebugLogger.shared.info("Actions: Copy requested but history is empty", source: "ContentView")
            return
        }

        // Fallback to raw text when no processed text is available
        // (for example older entries or edge cases with AI enhancement off).
        let processed = last.processedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = last.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = processed.isEmpty ? raw : processed
        guard !text.isEmpty else {
            DebugLogger.shared.info("Actions: Copy skipped because latest history text is empty", source: "ContentView")
            return
        }

        _ = ClipboardService.copyToClipboard(text)
        DebugLogger.shared.info("Actions: Copied latest transcription to clipboard", source: "ContentView")
    }

    private func undoLastAIProcessingFromHistory() {
        guard let last = TranscriptionHistoryStore.shared.entries.first else {
            DebugLogger.shared.info("Actions: Undo AI requested but history is empty", source: "ContentView")
            return
        }

        let rawText = last.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else {
            DebugLogger.shared.info("Actions: Undo AI skipped because latest history raw text is empty", source: "ContentView")
            return
        }

        guard last.wasAIProcessed else {
            DebugLogger.shared.info("Actions: Undo AI skipped because latest entry was not AI processed", source: "ContentView")
            return
        }

        DebugLogger.shared.info("Actions: Restoring latest transcription raw text (undo AI)", source: "ContentView")
        Task { @MainActor in
            await self.applyHistoryTextOutput(rawText, saveToHistory: true)
        }
    }

    private func applyHistoryTextOutput(_ text: String, saveToHistory: Bool) async {
        // Keep hotkey/recording state deterministic before applying output text.
        if self.asr.isRunning {
            DebugLogger.shared.info("Actions: stopping active recording before history action output", source: "ContentView")
            await self.asr.stopWithoutTranscription()
        }

        let finalText = ASRService.applyGAAVFormatting(text)
        let appInfo = self.getCurrentAppInfo()

        if saveToHistory, SettingsStore.shared.saveTranscriptionHistory {
            TranscriptionHistoryStore.shared.addEntry(
                rawText: text,
                processedText: finalText,
                appName: appInfo.name,
                windowTitle: appInfo.windowTitle
            )
        }

        if SettingsStore.shared.copyTranscriptionToClipboard {
            ClipboardService.copyToClipboard(finalText)
        }

        let focusedPID = TypingService.captureSystemFocusedPID()
            ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        NotchContentState.shared.recordingTargetPID = focusedPID

        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let isSayItFrontmost = frontmostApp?.bundleIdentifier?.contains("sayit") == true
        let shouldTypeExternally = !isSayItFrontmost || self.isTranscriptionFocused == false
        if shouldTypeExternally {
            await self.restoreFocusToRecordingTarget()
            self.asr.typeTextToActiveField(
                finalText,
                preferredTargetPID: NotchContentState.shared.recordingTargetPID
            )
        }
    }

    private func reprocessDictationText(_ transcribedText: String) async {
        // If live recording is still active, stop it first so reprocess does not
        // leave ASR running in the background (which causes the next hotkey press
        // to behave like a stop instead of start).
        if self.asr.isRunning {
            DebugLogger.shared.info("Actions: stopping active recording before reprocess", source: "ContentView")
            await self.asr.stopWithoutTranscription()
        }

        self.setActiveRecordingMode(.dictate)
        self.menuBarManager.setProcessing(true)
        let cancelToken = NotchContentState.shared.cancellationCount
        NotchOverlayManager.shared.updateTranscriptionText(transcribedText)
        NotchOverlayManager.shared.present(.refining)
        await Task.yield()

        var finalText = transcribedText
        var aiFailed = false
        let shouldUseAI = DictationAIPostProcessingGate.isConfigured()
        if shouldUseAI {
            switch await self.processTextWithAI(transcribedText) {
            case let .success(output):
                finalText = output
            case let .failure(message):
                DebugLogger.shared.warning(
                    "AI reprocessing failed; using the original transcription: \(message)",
                    source: "ContentView"
                )
                aiFailed = true
            }
        }

        if self.wasCancelled(since: cancelToken) {
            self.menuBarManager.setProcessing(false)
            self.clearActiveRecordingMode()
            return
        }

        NotchOverlayManager.shared.present(.done(aiFailed ? .insertedOriginal : .inserted))
        self.menuBarManager.setProcessing(false)

        finalText = ASRService.applyGAAVFormatting(finalText)
        let appInfo = self.getCurrentAppInfo()

        if SettingsStore.shared.saveTranscriptionHistory {
            TranscriptionHistoryStore.shared.addEntry(
                rawText: transcribedText,
                processedText: finalText,
                appName: appInfo.name,
                windowTitle: appInfo.windowTitle
            )
        }

        if SettingsStore.shared.copyTranscriptionToClipboard {
            ClipboardService.copyToClipboard(finalText)
        }

        let focusedPID = TypingService.captureSystemFocusedPID()
            ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        NotchContentState.shared.recordingTargetPID = focusedPID

        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let isSayItFrontmost = frontmostApp?.bundleIdentifier?.contains("sayit") == true
        let shouldTypeExternally = !isSayItFrontmost || self.isTranscriptionFocused == false
        if shouldTypeExternally {
            await self.restoreFocusToRecordingTarget()
            self.asr.typeTextToActiveField(
                finalText,
                preferredTargetPID: NotchContentState.shared.recordingTargetPID
            )
        }

        self.clearActiveRecordingMode()
    }

    // MARK: - Rewrite Mode Voice Processing

    private func processRewriteWithVoiceInstruction(_ instruction: String) async {
        let hasOriginalText = !self.rewriteModeService.originalText.isEmpty
        DebugLogger.shared.info("Processing \(hasOriginalText ? "rewrite" : "write/improve") - instruction: '\(instruction)', originalText length: \(self.rewriteModeService.originalText.count)", source: "ContentView")

        // Show processing animation
        self.menuBarManager.setProcessing(true)
        let cancelToken = NotchContentState.shared.cancellationCount
        NotchOverlayManager.shared.present(.refining)

        // Process the request - service handles both cases:
        // - With originalText: rewrites existing text based on instruction
        // - Without originalText: improves/refines the spoken text
        await self.rewriteModeService.processRewriteRequest(instruction)

        if self.wasCancelled(since: cancelToken) {
            DebugLogger.shared.info("Edit cancelled while processing; not replacing text", source: "ContentView")
            self.menuBarManager.setProcessing(false)
            self.rewriteModeService.clearState()
            return
        }

        let succeeded = !self.rewriteModeService.rewrittenText.isEmpty
        NotchOverlayManager.shared.present(succeeded ? .done(.inserted) : .failed("Couldn’t Edit Text"))

        // Hide processing animation
        self.menuBarManager.setProcessing(false)

        // If rewrite was successful, type the result
        if succeeded {
            DebugLogger.shared.info("Rewrite successful, typing result (chars: \(self.rewriteModeService.rewrittenText.count))", source: "ContentView")

            // Copy to clipboard as backup
            if SettingsStore.shared.copyTranscriptionToClipboard {
                ClipboardService.copyToClipboard(self.rewriteModeService.rewrittenText)
                AnalyticsService.shared.capture(
                    .outputDelivered,
                    properties: [
                        "mode": AnalyticsMode.rewrite.rawValue,
                        "method": AnalyticsOutputMethod.clipboard.rawValue,
                    ]
                )
            }

            // Type the rewritten text
            await self.restoreFocusToRecordingTarget()
            self.asr.typeTextToActiveField(
                self.rewriteModeService.rewrittenText,
                preferredTargetPID: NotchContentState.shared.recordingTargetPID
            )
            AnalyticsService.shared.capture(
                .outputDelivered,
                properties: [
                    "mode": AnalyticsMode.rewrite.rawValue,
                    "method": AnalyticsOutputMethod.typed.rawValue,
                ]
            )

            // Clear the rewrite service state for next use
            self.rewriteModeService.clearState()

            Task { @MainActor in
                NotchOverlayManager.shared.hide()
            }
        } else {
            DebugLogger.shared.error("Rewrite failed - no result", source: "ContentView")
            AnalyticsService.shared.capture(
                .errorOccurred,
                properties: [
                    "domain": AnalyticsErrorDomain.llm.rawValue,
                    "category": "rewrite_no_result",
                ]
            )
        }
    }

    private func setActiveRecordingMode(_ mode: ActiveRecordingMode) {
        self.activeRecordingMode = mode
        switch mode {
        case .none, .dictate:
            self.isRecordingForCommand = false
            self.isRecordingForRewrite = false
        case .edit:
            self.isRecordingForCommand = false
            self.isRecordingForRewrite = true
        case .command:
            self.isRecordingForCommand = true
            self.isRecordingForRewrite = false
        }
    }

    private func clearActiveRecordingMode() {
        self.setActiveRecordingMode(.none)
    }

    private func handleLivePromptModeSwitch(_ mode: SettingsStore.PromptMode) {
        guard !NotchContentState.shared.isProcessing else { return }
        switch mode.normalized {
        case .dictate:
            guard self.activeRecordingMode != .dictate || NotchContentState.shared.mode != .dictation else { return }
            self.setActiveRecordingMode(.dictate)
            self.rewriteModeService.clearState()
            self.menuBarManager.setOverlayMode(.dictation)
        case .edit:
            guard self.activeRecordingMode != .edit || NotchContentState.shared.mode == .dictation else { return }
            self.setActiveRecordingMode(.edit)
            let hasOriginal = !self.rewriteModeService.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasContext = !self.rewriteModeService.selectedContextText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if !hasOriginal, !hasContext {
                let captured = self.rewriteModeService.captureSelectedText()
                DebugLogger.shared.info("Live switch to Edit Text attempted context capture: \(captured)", source: "ContentView")
                if !captured {
                    self.rewriteModeService.startWithoutSelection()
                }
            }
            self.menuBarManager.setOverlayMode(.edit)
        case .write, .rewrite:
            guard self.activeRecordingMode != .edit || NotchContentState.shared.mode == .dictation else { return }
            self.setActiveRecordingMode(.edit)
            let hasOriginal = !self.rewriteModeService.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasContext = !self.rewriteModeService.selectedContextText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if !hasOriginal, !hasContext {
                let captured = self.rewriteModeService.captureSelectedText()
                DebugLogger.shared.info("Live switch to Edit Text attempted context capture: \(captured)", source: "ContentView")
                if !captured {
                    self.rewriteModeService.startWithoutSelection()
                }
            }
            self.menuBarManager.setOverlayMode(.edit)
        }
    }

    private func handleLiveOverlayModeSwitch(_ mode: OverlayMode) {
        guard !NotchContentState.shared.isProcessing else { return }
        switch mode {
        case .dictation:
            self.handleLivePromptModeSwitch(.dictate)
        case .edit, .write, .rewrite:
            self.handleLivePromptModeSwitch(.edit)
        case .command:
            guard self.activeRecordingMode != .command || NotchContentState.shared.mode != .command else { return }
            self.rewriteModeService.clearState()
            self.setActiveRecordingMode(.command)
            self.menuBarManager.setOverlayMode(.command)
        }
    }

    // MARK: - Command Mode Voice Processing

    private func processCommandWithVoice(_ command: String) async {
        DebugLogger.shared.info("Processing voice command: '\(command)'", source: "ContentView")

        // Show processing animation
        self.menuBarManager.setProcessing(true)
        NotchOverlayManager.shared.present(.refining)

        // Process the command through CommandModeService
        // This stores the conversation history and executes any terminal commands
        await self.commandModeService.processUserCommand(command)

        // The expanded command output is the result surface; the regular overlay just leaves.
        NotchOverlayManager.shared.present(.idle)
        self.menuBarManager.setProcessing(false)

        DebugLogger.shared.info("Command processed, conversation stored in Command Mode", source: "ContentView")
    }

    // Capture app context at start to avoid mismatches if the user switches apps mid-session
    private func startRecording() {
        let model = SettingsStore.shared.selectedSpeechModel
        DebugLogger.shared.info(
            "ContentView: startRecording() for model=\(model.displayName), supportsStreaming=\(model.supportsStreaming)",
            source: "ContentView"
        )
        self.setActiveRecordingMode(.dictate)

        // Ensure normal dictation mode is set (command/rewrite modes set their own)
        if !self.isRecordingForCommand, !self.isRecordingForRewrite {
            self.menuBarManager.setOverlayMode(.dictation)
        }

        if !self.isRecordingForCommand, !self.isRecordingForRewrite {
            TranscriptionSoundPlayer.shared.playStartSound()
        }

        // Capture the focused target PID BEFORE any overlay/UI changes.
        // Used to restore focus when the user interacts with overlay dropdowns (e.g. prompt selection).
        let focusedPID = TypingService.captureSystemFocusedPID()
            ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        NotchContentState.shared.recordingTargetPID = focusedPID

        let info = self.getCurrentAppInfo()
        self.recordingAppInfo = info
        DebugLogger.shared.debug("Captured recording app context: app=\(info.name), bundleId=\(info.bundleId), title=\(info.windowTitle)", source: "ContentView")
        self.beginOverlaySession()
        Task {
            await self.asr.start()
        }

        // Pre-load model in background while recording (avoids 10s freeze on stop)
        Task {
            do {
                DebugLogger.shared.debug("ContentView: pre-load model task started", source: "ContentView")
                try await self.asr.ensureAsrReady()
                DebugLogger.shared.debug("Model pre-loaded during recording", source: "ContentView")
            } catch {
                DebugLogger.shared.error("Failed to pre-load model: \(error)", source: "ContentView")
            }
        }
    }

    /// Resets the overlay for a new recording: clears the previous transcript and shows
    /// “Starting…” until audio flows.
    private func beginOverlaySession() {
        NotchOverlayManager.shared.updateTranscriptionText("")
        NotchOverlayManager.shared.present(.starting)
    }

    /// Best-effort: re-activate the app that was focused when recording started.
    /// Adds a short delay after activation so macOS can deliver focus before typing begins.
    private func restoreFocusToRecordingTarget() async {
        guard let pid = NotchContentState.shared.recordingTargetPID else { return }
        let activated = TypingService.activateApp(pid: pid)
        if activated {
            // Small delay to allow window focus to settle before typing events fire.
            try? await Task.sleep(nanoseconds: 80_000_000) // 80ms
        }
    }

    // MARK: - ASR Model Preloading

    private func preloadASRModel() async {
        guard !ASRStartupPolicy.isModelPreloadDisabled(
            environment: ProcessInfo.processInfo.environment
        ) else {
            DebugLogger.shared.debug("Skipping startup model load for tests", source: "ContentView")
            return
        }

        await self.asr.checkIfModelsExistAsync()

        guard ASRStartupPolicy.shouldLoadCachedModel(
            isReady: self.asr.isAsrReady,
            modelsExistOnDisk: self.asr.modelsExistOnDisk
        ) else {
            DebugLogger.shared.debug(
                "Skipping startup model load - no cached model needs preparation",
                source: "ContentView"
            )
            return
        }

        DebugLogger.shared.info("Loading cached speech model on startup", source: "ContentView")
        do {
            try await self.asr.ensureAsrReady()
            DebugLogger.shared.info("Cached speech model is ready", source: "ContentView")
        } catch {
            DebugLogger.shared.error(
                "Failed to load cached speech model: \(error.localizedDescription)",
                source: "ContentView"
            )
            self.asr.errorTitle = "Speech Model Couldn’t Load"
            self.asr.errorMessage = error.localizedDescription
            self.asr.showError = true
        }
    }

    private func checkAccessibilityPermissions() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Requests Accessibility from an explicit user action (Home or General), after the
    /// UI has explained why: shows the system prompt and opens the Accessibility pane.
    private func openAccessibilitySettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AccessibilityPermissionAction.perform(
            prompt: {
                _ = AXIsProcessTrustedWithOptions(options)
            },
            openSettings: { url in
                _ = NSWorkspace.shared.open(url)
            }
        )
        UserDefaults.standard.set(true, forKey: self.accessibilityRestartFlagKey)
        self.startAccessibilityPolling()
    }

    private func restartApp() {
        let appPath = Bundle.main.bundlePath
        let process = Process()
        process.launchPath = "/usr/bin/open"
        process.arguments = ["-n", appPath]
        UserDefaults.standard.set(false, forKey: self.accessibilityRestartFlagKey)
        self.accessibilityNeedsRestart = false
        try? process.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
    }

    /// Watches for Accessibility being granted in System Settings. When it is, SayIt tries
    /// to start the shortcut listener in place; only if that fails does it ask to restart.
    private func startAccessibilityPolling() {
        guard !self.accessibilityEnabled else { return }

        self.accessibilityPollingTask?.cancel()
        self.accessibilityPollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)

                guard AXIsProcessTrusted() else { continue }
                await MainActor.run {
                    DebugLogger.shared.info("Accessibility permission granted", source: "ContentView")
                    self.accessibilityEnabled = true
                }

                // The hotkey manager reinitializes asynchronously (see onChange of
                // accessibilityEnabled): it waits before creating its event tap and retries.
                // Only ask for a restart if the listener still isn't up after that window.
                var healthy = false
                for _ in 0..<Self.listenerStartChecks {
                    try? await Task.sleep(nanoseconds: Self.listenerStartCheckInterval)
                    healthy = await MainActor.run { self.hotkeyManager?.validateEventTapHealth() ?? false }
                    if healthy { break }
                }
                await MainActor.run {
                    self.hotkeyManagerInitialized = healthy
                    guard !healthy else {
                        self.accessibilityNeedsRestart = false
                        return
                    }
                    self.accessibilityNeedsRestart = true
                    // Offer once per grant; Home keeps a Restart Now button afterwards.
                    if !UserDefaults.standard.bool(forKey: self.hasAutoRestartedForAccessibilityKey) {
                        UserDefaults.standard.set(true, forKey: self.hasAutoRestartedForAccessibilityKey)
                        self.showAccessibilityRestartAlert = true
                    }
                }
                break
            }
        }
    }

    private func revealAppInFinder() {
        let appPath = Bundle.main.bundlePath
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: appPath)])
    }

    private func openApplicationsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
    }

    private func initializeHotkeyManagerIfNeeded() {
        NotchContentState.shared.onPromptModeSwitchRequested = { mode in
            self.handleLivePromptModeSwitch(mode)
        }
        NotchContentState.shared.onOverlayModeSwitchRequested = { mode in
            self.handleLiveOverlayModeSwitch(mode)
        }
        NotchContentState.shared.onReprocessLastRequested = {
            self.reprocessLastDictationFromHistory()
        }
        NotchContentState.shared.onCopyLastRequested = {
            self.copyLastDictationFromHistory()
        }
        NotchContentState.shared.onUndoLastAIRequested = {
            self.undoLastAIProcessingFromHistory()
        }
        NotchContentState.shared.onToggleAIProcessingRequested = {
            _ = self.menuBarManager.toggleAIProcessingEnabled()
        }
        NotchContentState.shared.onOpenPreferencesRequested = {
            self.menuBarManager.openPreferencesFromUI()
        }

        guard self.hotkeyManager == nil else { return }

        self.hotkeyManager = GlobalHotkeyManager(
            asrService: self.asr,
            shortcut: self.hotkeyShortcut,
            commandModeShortcut: self.commandModeHotkeyShortcut,
            rewriteModeShortcut: self.rewriteModeHotkeyShortcut,
            commandModeShortcutEnabled: self.isCommandModeShortcutEnabled,
            rewriteModeShortcutEnabled: self.isRewriteModeShortcutEnabled,
            startRecordingCallback: {
                DebugLogger.shared.debug("ContentView: startRecordingCallback invoked by hotkey", source: "ContentView")
                self.startRecording()
            },
            dictationModeCallback: {
                DebugLogger.shared.info("Dictate mode triggered", source: "ContentView")
                DebugLogger.shared.debug(
                    "ContentView: selected model for dictate hotkey=\(SettingsStore.shared.selectedSpeechModel.displayName)",
                    source: "ContentView"
                )
                self.setActiveRecordingMode(.dictate)
                self.rewriteModeService.clearState()
                self.menuBarManager.setOverlayMode(.dictation)

                guard !self.asr.isRunning else { return }
                if SettingsStore.shared.enableTranscriptionSounds {
                    TranscriptionSoundPlayer.shared.playStartSound()
                }
                self.beginOverlaySession()
                Task {
                    await self.asr.start()
                }
            },
            stopAndProcessCallback: {
                await self.stopAndProcessTranscription()
            },
            commandModeCallback: {
                DebugLogger.shared.info("Command mode triggered", source: "ContentView")

                // Set flag so stopAndProcessTranscription knows to process as command
                self.setActiveRecordingMode(.command)

                // Set overlay mode to command
                self.menuBarManager.setOverlayMode(.command)

                guard !self.asr.isRunning else { return }

                // Start recording immediately for the command
                DebugLogger.shared.info(
                    "Starting voice recording for command",
                    source: "ContentView"
                )
                TranscriptionSoundPlayer.shared.playStartSound()
                self.beginOverlaySession()
                Task {
                    await self.asr.start()
                }
            },
            rewriteModeCallback: {
                // Try to capture text first while still in the other app
                let captured = self.rewriteModeService.captureSelectedText()
                DebugLogger.shared.info("Rewrite mode triggered, text captured: \(captured)", source: "ContentView")

                if !captured {
                    // No text selected - start in "write mode" where user speaks
                    // what to write
                    DebugLogger.shared
                        .info(
                            "No text selected - starting in write/improve mode",
                            source: "ContentView"
                        )
                    self.rewriteModeService.startWithoutSelection()
                    // Set overlay mode to edit
                    self.menuBarManager.setOverlayMode(.edit)
                } else {
                    // Text was selected - edit mode (with selected context)
                    self.menuBarManager.setOverlayMode(.edit)
                }

                // Set flag so stopAndProcessTranscription knows to process as rewrite
                self.setActiveRecordingMode(.edit)

                guard !self.asr.isRunning else { return }

                // Start recording immediately for the edit instruction
                DebugLogger.shared.info("Starting voice recording for edit mode", source: "ContentView")
                TranscriptionSoundPlayer.shared.playStartSound()
                self.beginOverlaySession()
                Task {
                    await self.asr.start()
                }
            },
            isDictateRecordingProvider: {
                self.activeRecordingMode == .dictate
            },
            isCommandRecordingProvider: {
                self.activeRecordingMode == .command
            },
            isRewriteRecordingProvider: {
                self.activeRecordingMode == .edit
            }
        )

        self.hotkeyManagerInitialized = self.hotkeyManager?.validateEventTapHealth() ?? false

        self.hotkeyManager?.enablePressAndHoldMode(self.pressAndHoldModeEnabled)

        // Set cancel callback for Escape key handling (closes mode views, resets recording state)
        // Returns true if it handled something (so GlobalHotkeyManager knows to consume the event)
        self.hotkeyManager?.setCancelCallback {
            var handled = false

            // Close expanded command notch if visible (highest priority)
            if NotchOverlayManager.shared.isCommandOutputExpanded {
                DebugLogger.shared.debug("Cancel callback: closing expanded command notch", source: "ContentView")
                NotchOverlayManager.shared.hideExpandedCommandOutput()
                handled = true
            }

            // Reset recording mode flags; a recording in progress ends as “Cancelled”.
            if self.activeRecordingMode != .none {
                NotchOverlayManager.shared.present(.cancelled)
                self.clearActiveRecordingMode()
                handled = true
            }

            return handled
        }

        // Monitor initialization status
        Task {
            // Give some time for initialization
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

            await MainActor.run {
                self.hotkeyManagerInitialized = self.hotkeyManager?.validateEventTapHealth() ?? false
                DebugLogger.shared.debug("Initial hotkey manager health check: \(self.hotkeyManagerInitialized)", source: "ContentView")

                // If still not initialized and accessibility is enabled, try reinitializing
                if !self.hotkeyManagerInitialized && self.accessibilityEnabled {
                    self.hotkeyManagerInitialized = self.hotkeyManager?.validateEventTapHealth() ?? false
                    DebugLogger.shared.debug("Initial hotkey manager health check: \(self.hotkeyManagerInitialized)", source: "ContentView")

                    // If still not initialized and accessibility is enabled, try reinitializing
                    if !self.hotkeyManagerInitialized && self.accessibilityEnabled {
                        DebugLogger.shared.debug("Hotkey manager not healthy, attempting reinitalization", source: "ContentView")
                        self.hotkeyManager?.reinitialize()
                    }
                }
            }
        }
    }

    // Deprecated: hotkey persistence is handled via SettingsStore
}

// MARK: - Card Appear Modifier

/// Entrance for cards when a page first appears: a short rise and fade, staggered by
/// `delay`. Honors Reduce Motion.
struct CardAppearAnimation: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let delay: Double
    @Binding var appear: Bool

    func body(content: Content) -> some View {
        content
            .offset(y: self.appear || self.reduceMotion ? 0 : Space.sm)
            .opacity(self.appear ? 1.0 : 0)
            .animation(
                Motion.resolved(Motion.enter, reduceMotion: self.reduceMotion).delay(self.delay),
                value: self.appear
            )
    }
}
