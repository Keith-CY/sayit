//
//  WelcomeView.swift
//  SayIt
//
//  Welcome and setup guide view
//

import AppKit
import AVFoundation
import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var appServices: AppServices
    private var asr: ASRService { self.appServices.asr }
    @ObservedObject private var settings = SettingsStore.shared
    @Binding var selectedSidebarItem: SidebarItem?
    @Binding var playgroundUsed: Bool
    var isTranscriptionFocused: FocusState<Bool>.Binding
    @Environment(\.theme) private var theme

    let accessibilityEnabled: Bool
    let stopAndProcessTranscription: () async -> Void
    let startRecording: () -> Void
    let openAccessibilitySettings: () -> Void

    private var commandModeShortcutDisplay: String {
        self.settings.commandModeHotkeyShortcut.displayString
    }

    private var writeModeShortcutDisplay: String {
        self.settings.rewriteModeHotkeyShortcut.displayString
    }

    private var recordingControlAction: RecordingControlAction {
        RecordingControlPolicy.action(
            isRunning: self.asr.isRunning,
            isReady: self.asr.isAsrReady,
            isPreparingModel: self.asr.isDownloadingModel || self.asr.isLoadingModel,
            micStatus: self.asr.micStatus
        )
    }

    private var recordingButtonTitle: String {
        switch self.recordingControlAction {
        case .start:
            return "Start Recording"
        case .stop:
            return "Stop Recording"
        case .prepareAndStart:
            return "Start Recording"
        case .waitForModel:
            return "Preparing Voice Model…"
        case .requestMicrophoneAccess:
            return "Grant Microphone Access"
        case .openMicrophoneSettings:
            return "Open Microphone Settings"
        case .showMicrophoneRestriction:
            return "Microphone Access Restricted"
        }
    }

    private var recordingButtonIcon: String {
        switch self.recordingControlAction {
        case .start:
            return "mic.fill"
        case .stop:
            return "stop.fill"
        case .prepareAndStart:
            return "mic.fill"
        case .waitForModel:
            return "hourglass"
        case .requestMicrophoneAccess:
            return "mic.fill"
        case .openMicrophoneSettings:
            return "gear"
        case .showMicrophoneRestriction:
            return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 10) {
                    Image(systemName: "book.fill")
                        .font(.title2)
                        .foregroundStyle(self.theme.palette.accent)
                        Text((self.asr.isAsrReady || self.asr.modelsExistOnDisk) ? "Getting Started" : "Welcome to SayIt")
                        .font(.title2.weight(.bold))
                }
                .padding(.bottom, 4)

                // Quick Setup Checklist
                ThemedCard(style: .prominent) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Quick Setup", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(self.theme.palette.accent)

                        VStack(alignment: .leading, spacing: 8) {
                            SetupStepView(
                                step: 1,
                                // Consider model step complete if ready OR downloaded (even if not loaded)
                                title: (self.asr.isAsrReady || self.asr.modelsExistOnDisk) ? "Voice Model Ready" : "Download Voice Model",
                                description: self.asr.isAsrReady
                                    ? "Speech recognition model is loaded and ready"
                                    : (self.asr.modelsExistOnDisk
                                        ? "Model downloaded, will load when needed"
                                        : "Download \(self.settings.selectedSpeechModel.displayName) for offline voice transcription (\(self.settings.selectedSpeechModel.downloadSize))"),
                                status: (self.asr.isAsrReady || self.asr.modelsExistOnDisk) ? .completed : .pending,
                                action: {
                                    self.selectedSidebarItem = .voiceEngine
                                },
                                actionButtonTitle: "Go to Voice Engine",
                                showActionButton: !(self.asr.isAsrReady || self.asr.modelsExistOnDisk)
                            )

                            SetupStepView(
                                step: 2,
                                title: self.asr.micStatus == .authorized ? "Microphone Permission Granted" : "Grant Microphone Permission",
                                description: self.asr.micStatus == .authorized
                                    ? "SayIt has access to your microphone"
                                    : "Allow SayIt to access your microphone for voice input",
                                status: self.asr.micStatus == .authorized ? .completed : .pending,
                                action: {
                                    if self.asr.micStatus == .notDetermined {
                                        self.asr.requestMicAccess()
                                    } else if self.asr.micStatus == .denied {
                                        self.asr.openSystemSettingsForMic()
                                    }
                                },
                                actionButtonTitle: self.asr.micStatus == .notDetermined ? "Grant Access" : "Open Settings",
                                showActionButton: self.asr.micStatus != .authorized
                            )

                            SetupStepView(
                                step: 3,
                                title: self.accessibilityEnabled ? "Accessibility Enabled" : "Enable Accessibility",
                                description: self.accessibilityEnabled
                                    ? "Accessibility permission granted for typing into apps"
                                    : "Enable SayIt to use the global shortcut and type into other apps. After an update, switch SayIt off and on again if it is already listed.",
                                status: self.accessibilityEnabled ? .completed : .pending,
                                action: {
                                    self.openAccessibilitySettings()
                                },
                                actionButtonTitle: "Open Settings",
                                showActionButton: !self.accessibilityEnabled
                            )

                            SetupStepView(
                                step: 4,
                                title: self.settings.isAIConfigured ? "AI Enhancement Configured" : "Set Up AI Enhancement (Optional)",
                                description: self.settings.isAIConfigured
                                    ? "AI-powered text enhancement is ready to use"
                                    : "Configure API keys for AI-powered text enhancement",
                                status: self.settings.isAIConfigured ? .completed : .pending,
                                action: {
                                    self.selectedSidebarItem = .aiEnhancements
                                },
                                actionButtonTitle: "Configure AI"
                            )

                            SetupStepView(
                                step: 5,
                                title: self.playgroundUsed ? "Setup Tested Successfully" : "Test Your Setup",
                                description: self.playgroundUsed
                                    ? "You've successfully tested voice transcription"
                                    : "Try the playground below to test your complete setup",
                                status: self.playgroundUsed ? .completed : .pending,
                                action: {
                                    // Scroll to playground or focus on it
                                    withAnimation {
                                        self.isTranscriptionFocused.wrappedValue = true
                                    }
                                },
                                actionButtonTitle: "Go to Playground",
                                showActionButton: !self.playgroundUsed
                            )
                            .id("playground-step-\(self.playgroundUsed)")
                        }
                    }
                    .padding(14)
                }

                // How to Use
                ThemedCard(style: .standard) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("How to Use", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundStyle(Color.fluidGreen)

                        VStack(alignment: .leading, spacing: 10) {
                            self.howToStep(number: 1, title: "Start Recording", description: "Press your hotkey (default: Right Option/Alt) or click the button")
                            self.howToStep(number: 2, title: "Speak Clearly", description: "Speak naturally - works best in quiet environments")
                            self.howToStep(number: 3, title: "Auto-Type Result", description: "Transcription is automatically typed into your focused app")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                .frame(maxWidth: .infinity)

                // Command Mode
                ThemedCard(style: .standard) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Label("Command Mode", systemImage: "terminal.fill")
                                .font(.headline)
                                .foregroundStyle(Color(red: 1.0, green: 0.35, blue: 0.35))

                            self.featureBadge("New", color: Color(red: 1.0, green: 0.35, blue: 0.35))
                            self.featureBadge("Alpha", color: Color(red: 1.0, green: 0.35, blue: 0.35).opacity(0.7))

                            Spacer()

                            Button("Open") {
                                self.selectedSidebarItem = .commandMode
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Text("Control your Mac with voice commands. Execute terminal commands, open apps, and more.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Getting Started")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.orange)

                            HStack(spacing: 4) {
                                Text("Press")
                                self.keyboardBadge(self.commandModeShortcutDisplay)
                                Text("to open, speak your command, then press again to send.")
                            }
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.8))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Examples")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.orange)
                            self.commandModeExample(icon: "folder", text: "\"List files in my Downloads folder\"")
                            self.commandModeExample(icon: "plus.rectangle.on.folder", text: "\"Create a folder called Projects on Desktop\"")
                            self.commandModeExample(icon: "network", text: "\"What's my IP address?\"")
                            self.commandModeExample(icon: "safari", text: "\"Open Safari\"")
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text("AI can make mistakes. Avoid destructive commands.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                }
                .frame(maxWidth: .infinity)

                // Edit Mode
                ThemedCard(style: .standard) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Label("Edit Mode", systemImage: "pencil.and.outline")
                                .font(.headline)
                                .foregroundStyle(.blue)

                            self.featureBadge("New", color: .blue)

                            Spacer()

                            Button("Open AI Settings") {
                                self.selectedSidebarItem = .aiEnhancements
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Text("AI-powered editing assistant. Write fresh content or edit selected text with voice.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Create New Text")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.blue)

                                HStack(spacing: 4) {
                                    Text("Press")
                                    self.keyboardBadge(self.writeModeShortcutDisplay)
                                    Text("and speak what you want to write.")
                                }
                                .font(.caption)
                                .foregroundStyle(.primary.opacity(0.8))

                                self.writeModeExample(text: "\"Write an email asking for time off\"")
                                self.writeModeExample(text: "\"Draft a thank you note\"")
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Edit Selected Text")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.blue)

                                HStack(spacing: 4) {
                                    Text("Select text first, then press")
                                    self.keyboardBadge(self.writeModeShortcutDisplay)
                                    Text("and speak your instruction.")
                                }
                                .font(.caption)
                                .foregroundStyle(.primary.opacity(0.8))

                                self.writeModeExample(text: "\"Make this more formal\"")
                                self.writeModeExample(text: "\"Fix grammar and spelling\"")
                                self.writeModeExample(text: "\"Summarize this\"")
                            }
                        }
                    }
                    .padding(16)
                }
                .frame(maxWidth: .infinity)

                // Test Playground
                ThemedCard(hoverEffect: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Test Playground")
                                        .font(.headline)
                                    Text("Click record, speak, and see your transcription")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "text.bubble")
                                    .font(.title3)
                            }

                            Spacer()

                            if self.asr.isRunning {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 6, height: 6)
                                    Text("Recording...")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.red)
                                }
                            } else if !self.asr.finalText.isEmpty {
                                Text("\(self.asr.finalText.count) characters")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if !self.asr.finalText.isEmpty {
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(self.asr.finalText, forType: .string)
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }

                        if self.settings.selectedSpeechModel == .parakeetTDT {
                            HStack(spacing: 6) {
                                Image(systemName: "text.magnifyingglass")
                                    .font(.caption)
                                    .foregroundStyle(self.theme.palette.accent)
                                Text(self.asr.wordBoostStatusText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(self.theme.palette.contentBackground.opacity(0.6))
                            )
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            // Recording Control
                            VStack(spacing: 10) {
                                Button {
                                    switch self.recordingControlAction {
                                    case .stop:
                                        Task {
                                            await self.stopAndProcessTranscription()
                                        }
                                    case .start:
                                        self.startRecording()
                                    case .prepareAndStart:
                                        Task {
                                            do {
                                                try await self.asr.ensureAsrReady()
                                                self.startRecording()
                                            } catch {
                                                self.asr.errorTitle = "Voice Model Failed to Prepare"
                                                self.asr.errorMessage = error.localizedDescription
                                                self.asr.showError = true
                                            }
                                        }
                                    case .waitForModel:
                                        break
                                    case .requestMicrophoneAccess:
                                        self.startRecording()
                                    case .openMicrophoneSettings:
                                        self.asr.openSystemSettingsForMic()
                                    case .showMicrophoneRestriction:
                                        self.startRecording()
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: self.recordingButtonIcon)
                                        Text(self.recordingButtonTitle)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(PremiumButtonStyle(isRecording: self.asr.isRunning))
                                .buttonHoverEffect()
                                .scaleEffect(self.asr.isRunning ? 1.02 : 1.0)
                                .animation(.spring(response: 0.3), value: self.asr.isRunning)
                                .disabled(self.recordingControlAction == .waitForModel)

                                if !self.asr.isRunning && !self.asr.finalText.isEmpty {
                                    Button("Clear Results") {
                                        self.asr.finalText = ""
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }

                            // Text Area
                            VStack(alignment: .leading, spacing: 8) {
                                TextEditor(text: Binding(
                                    get: { self.asr.finalText },
                                    set: { self.asr.finalText = $0 }
                                ))
                                .font(.body)
                                .focused(self.isTranscriptionFocused)
                                .frame(height: 140)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(
                                            self.asr.isRunning ? self.theme.palette.accent.opacity(0.06) : self.theme.palette.cardBackground
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(
                                                    self.asr.isRunning ? self.theme.palette.accent.opacity(0.4) : self.theme.palette.cardBorder.opacity(0.6),
                                                    lineWidth: self.asr.isRunning ? 2 : 1
                                                )
                                        )
                                )
                                .scrollContentBackground(.hidden)
                                .overlay(
                                    VStack(spacing: 8) {
                                        if self.asr.isRunning {
                                            Image(systemName: "waveform")
                                                .font(.title2)
                                                .foregroundStyle(self.theme.palette.accent)
                                            Text("Listening... Speak now!")
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(self.theme.palette.accent)
                                            Text("Transcription will appear when you stop recording")
                                                .font(.caption)
                                                .foregroundStyle(self.theme.palette.accent.opacity(0.7))
                                        } else if self.recordingControlAction == .waitForModel {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text("Preparing the voice model…")
                                                .font(.subheadline.weight(.medium))
                                            Text("Recording will be available when preparation completes")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else if self.asr.finalText.isEmpty {
                                            Image(systemName: "text.bubble")
                                                .font(.title2)
                                                .foregroundStyle(.secondary.opacity(0.5))
                                            Text("Ready to test!")
                                                .font(.subheadline.weight(.medium))
                                            Text("Click 'Start Recording' or press your hotkey")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .allowsHitTesting(false)
                                )

                                if !self.asr.finalText.isEmpty {
                                    HStack(spacing: 8) {
                                        Button {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(self.asr.finalText, forType: .string)
                                        } label: {
                                            Label("Copy Text", systemImage: "doc.on.doc")
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(self.theme.palette.accent)
                                        .controlSize(.small)

                                        Button("Clear & Test Again") {
                                            self.asr.finalText = ""
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)

                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .padding(16)
        }
        .onAppear {
            // CRITICAL FIX: Refresh microphone and model status immediately on appear
            // This prevents the Quick Setup from showing stale status before ASRService.initialize() runs
            Task { @MainActor in
                // Check microphone status without triggering the full initialize() delay
                self.asr.micStatus = AVCaptureDevice.authorizationStatus(for: .audio)

                // Check if models exist on disk (async for accurate detection with AppleSpeechAnalyzerProvider)
                await self.asr.checkIfModelsExistAsync()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            self.asr.refreshMicAuthorizationStatus()
        }
        .onChange(of: self.asr.isRunning) { _, isRunning in
            guard isRunning else { return }
            self.playgroundUsed = true
            SettingsStore.shared.playgroundUsed = true
        }
    }

    // MARK: - Helper Views

    private func howToStep(number: Int, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(self.theme.palette.accent.opacity(0.15))
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(self.theme.palette.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func featureBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func keyboardBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(self.theme.palette.cardBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func commandModeExample(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.orange.opacity(0.8))
                .frame(width: 14)
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.8))
        }
    }

    private func writeModeExample(text: String) -> some View {
        HStack(spacing: 6) {
            Text("•")
                .foregroundStyle(.blue.opacity(0.6))
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.8))
        }
    }
}
