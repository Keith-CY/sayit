//
//  NotchContentViews.swift
//  SayIt
//
//  Created by Assistant
//

import Combine
import SwiftUI

// MARK: - Observable state for notch content (Singleton)

@MainActor
class NotchContentState: ObservableObject {
    static let shared = NotchContentState()
    // Keep overlay state bounded even during very long recordings.
    private static let maxStoredTranscriptionCharacters = SettingsStore.transcriptionPreviewCharLimitRange.upperBound

    @Published var transcriptionText: String = ""
    @Published var mode: OverlayMode = .dictation
    @Published var promptPickerMode: SettingsStore.PromptMode = .dictate
    @Published var isProcessing: Bool = false // AI processing state
    /// Single source of truth for what the overlay is communicating.
    @Published var phase: OverlayPhase = .idle
    /// When `phase` last changed; used to keep terminal phases on screen long enough to read.
    private(set) var phaseChangedAt = Date.distantPast

    func setPhase(_ phase: OverlayPhase) {
        guard phase != self.phase else { return }
        self.phase = phase
        self.phaseChangedAt = Date()
        if phase.isWorking {
            self.isProcessing = true
        } else if phase.isTerminal || phase == .idle || phase == .listening {
            self.isProcessing = false
        }
    }

    // Icon of the target app (where text will be typed)
    @Published var targetAppIcon: NSImage?

    /// The PID of the app we should restore focus to after interacting with overlays.
    /// Captured at recording start to keep the target stable for the session.
    @Published var recordingTargetPID: pid_t? = nil

    // Cached transcription preview text to avoid recomputing on every render
    @Published private(set) var cachedPreviewText: String = ""

    // MARK: - Expanded Command Output State

    @Published var isExpandedForCommandOutput: Bool = false
    @Published var commandOutput: String = "" // Final or streaming output
    @Published var commandStreamingText: String = "" // Real-time streaming text
    @Published var commandInputText: String = "" // User's follow-up input
    @Published var commandConversationHistory: [CommandOutputMessage] = []
    @Published var isCommandProcessing: Bool = false

    // MARK: - Chat History State

    @Published var recentChats: [ChatSession] = []
    @Published var currentChatTitle: String = "New Chat"

    // Command output message model
    struct CommandOutputMessage: Identifiable, Equatable {
        let id = UUID()
        let role: Role
        let content: String
        let timestamp: Date = .init()

        enum Role: Equatable {
            case user
            case assistant
            case status // For "Running…", "Checking…", etc.
        }
    }

    // Callback for submitting follow-up commands from the notch
    var onSubmitFollowUp: ((String) async -> Void)?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        let previewLimitChanged = NotificationCenter.default.publisher(
            for: NSNotification.Name("TranscriptionPreviewCharLimitChanged")
        )
        let defaultsChanged = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)

        Publishers.Merge(previewLimitChanged, defaultsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recomputeTranscriptionLines()
            }
            .store(in: &self.cancellables)
    }

    /// Set AI processing state
    func setProcessing(_ processing: Bool) {
        self.isProcessing = processing
    }

    /// Update transcription and recompute cached lines
    func updateTranscription(_ text: String) {
        let boundedText = Self.tailCharacters(in: text, maxCharacters: Self.maxStoredTranscriptionCharacters)
        guard boundedText != self.transcriptionText else { return }

        self.transcriptionText = boundedText
        self.recomputeTranscriptionLines()
    }

    /// Recompute cached transcription lines (called only when text changes)
    private func recomputeTranscriptionLines() {
        let text = self.transcriptionText

        guard !text.isEmpty else {
            if !self.cachedPreviewText.isEmpty {
                self.cachedPreviewText = ""
            }
            return
        }

        let maxChars = SettingsStore.shared.transcriptionPreviewCharLimit
        let previewText = Self.tailCharacters(in: text, maxCharacters: maxChars)
        guard previewText != self.cachedPreviewText else { return }
        self.cachedPreviewText = previewText
    }

    private static func tailCharacters(in text: String, maxCharacters: Int) -> String {
        guard maxCharacters > 0, !text.isEmpty else { return "" }

        let start = text.index(text.endIndex, offsetBy: -maxCharacters, limitedBy: text.startIndex) ?? text.startIndex
        return String(text[start..<text.endIndex])
    }

    // MARK: - Recording State for Expanded View

    @Published var isRecordingInExpandedMode: Bool = false

    /// Called when the user requests a live mode switch from the prompt picker tabs.
    var onPromptModeSwitchRequested: ((SettingsStore.PromptMode) -> Void)?
    /// Called when the user requests a live overlay mode switch from the mode picker.
    var onOverlayModeSwitchRequested: ((OverlayMode) -> Void)?
    /// Called when the user requests reprocessing the latest saved dictation entry.
    var onReprocessLastRequested: (() -> Void)?
    /// Called when the user requests copying the latest saved transcription entry.
    var onCopyLastRequested: (() -> Void)?
    /// Called when the user requests undoing AI processing for the latest entry.
    var onUndoLastAIRequested: (() -> Void)?
    /// Called when the user requests toggling dictation AI enhancement.
    var onToggleAIProcessingRequested: (() -> Void)?
    /// Called when the user requests opening Settings.
    var onOpenPreferencesRequested: (() -> Void)?

    /// Set recording state (for meter visibility in the expanded command view)
    func setRecordingInExpandedMode(_ recording: Bool) {
        self.isRecordingInExpandedMode = recording
        if !recording {
            OverlayAudioMeter.shared.set(0)
        }
    }

    /// Update audio level for the expanded command view meter
    func updateExpandedModeAudioLevel(_ level: CGFloat) {
        guard self.isRecordingInExpandedMode else { return }
        OverlayAudioMeter.shared.set(level)
    }

    // MARK: - Command Output Methods

    /// Show expanded output view with content
    func showExpandedCommandOutput(output: String) {
        self.commandOutput = output
        self.commandStreamingText = ""
        self.isExpandedForCommandOutput = true
        self.isRecordingInExpandedMode = false // Not recording when first showing output
    }

    /// Update streaming text in real-time
    func updateCommandStreamingText(_ text: String) {
        self.commandStreamingText = text
    }

    /// Add a message to the conversation history
    func addCommandMessage(role: CommandOutputMessage.Role, content: String) {
        let message = CommandOutputMessage(role: role, content: content)
        self.commandConversationHistory.append(message)
    }

    /// Set command processing state
    func setCommandProcessing(_ processing: Bool) {
        self.isCommandProcessing = processing
    }

    /// Clear command output and hide expanded view
    func clearCommandOutput() {
        self.isExpandedForCommandOutput = false
        self.commandOutput = ""
        self.commandStreamingText = ""
        self.commandInputText = ""
        self.commandConversationHistory.removeAll()
        self.isCommandProcessing = false
    }

    /// Hide expanded view but keep history
    func collapseCommandOutput() {
        self.isExpandedForCommandOutput = false
    }

    // MARK: - Chat History Methods

    /// Refresh recent chats from store
    func refreshRecentChats() {
        self.recentChats = ChatHistoryStore.shared.getRecentChats(excludingCurrent: false)
        if let current = ChatHistoryStore.shared.currentSession {
            self.currentChatTitle = current.title
        }
    }
}

// MARK: - Notch Overlay (expanded)

/// Root of the notch overlay. Applies the always-dark overlay theme.
struct NotchExpandedView: View {
    var body: some View {
        NotchOverlayContent()
            .sayItOverlayTheme()
    }
}

/// Notch layout: indicator + status + cancel on top, transcript in the middle, prompt
/// selector at the bottom so its menu opens outside the notch instead of over the words.
struct NotchOverlayContent: View {
    @ObservedObject private var contentState = NotchContentState.shared
    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.theme) private var theme
    @State private var promptChipFrame: CGRect = .zero
    @State private var promptChipWindow: NSWindow?

    private static let contentWidth: CGFloat = 288
    private static let appIconSize: CGFloat = 16
    private static let transcriptLines = 2

    private var mode: OverlayMode {
        self.contentState.mode.normalized
    }

    private var phase: OverlayPhase {
        self.contentState.phase
    }

    private var canExpandCommandHistory: Bool {
        self.mode == .command && !self.contentState.commandConversationHistory.isEmpty
    }

    private var selectedPromptLabel: String {
        guard let promptMode = self.mode.promptMode else { return "" }
        if let profile = self.settings.selectedPromptProfile(for: promptMode) {
            let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Untitled" : name
        }
        return "Default"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                if let appIcon = self.contentState.targetAppIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: Self.appIconSize, height: Self.appIconSize)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
                        .accessibilityHidden(true)
                }

                OverlayIndicator(phase: self.phase, mode: self.mode, meterStyle: .notch)

                OverlayStatusLabel(phase: self.phase, mode: self.mode, showsModeGlyph: false)
                    .layoutPriority(1)

                Spacer(minLength: Space.xs)

                OverlayCancelControl(size: 20)
            }

            OverlayTranscriptText(
                text: self.contentState.cachedPreviewText,
                font: AppFont.Overlay.transcriptCompact,
                lines: Self.transcriptLines,
                isDimmed: self.phase.isWorking
            )

            self.footer
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .frame(width: Self.contentWidth, alignment: .leading)
        .background(self.theme.overlay.surface) // Pure black to blend with the hardware notch
        .onChange(of: self.contentState.mode) { _, newMode in
            OverlayMenuController.shared.hide()
            switch newMode {
            case .dictation: self.contentState.promptPickerMode = .dictate
            case .edit, .write, .rewrite: self.contentState.promptPickerMode = .edit
            case .command: break
            }
        }
        .onChange(of: self.contentState.isProcessing) { _, processing in
            if processing { OverlayMenuController.shared.hide() }
        }
        .motion(Motion.state, value: self.contentState.mode)
    }

    @ViewBuilder
    private var footer: some View {
        if let promptMode = self.mode.promptMode {
            Button {
                OverlayMenuController.shared.toggle(
                    .prompt(promptMode),
                    anchor: self.promptChipFrame,
                    parent: self.promptChipWindow,
                    direction: .below
                )
            } label: {
                OverlayChipLabel(title: "Prompt", value: self.selectedPromptLabel)
            }
            .buttonStyle(OverlayChipButtonStyle())
            .background(
                OverlayAnchorReader { frame, window in
                    self.promptChipFrame = frame
                    self.promptChipWindow = window
                }
                .allowsHitTesting(false)
            )
            .disabled(self.phase.isWorking || self.phase.isTerminal)
            .accessibilityLabel("Prompt: \(self.selectedPromptLabel)")
            .accessibilityHint("Choose the prompt used for this dictation")
        } else if self.canExpandCommandHistory {
            Button {
                NotchOverlayManager.shared.onNotchClicked?()
            } label: {
                OverlayChipLabel(value: "Show Conversation", systemImage: "bubble.left.and.bubble.right", showsChevron: false)
            }
            .buttonStyle(OverlayChipButtonStyle())
        }
    }
}

// MARK: - Expanded Command Output View (Interactive Notch)

struct NotchCommandOutputExpandedView: View {
    let maxHeight: CGFloat
    let onDismiss: () -> Void
    let onSubmit: (String) async -> Void
    let onNewChat: () -> Void
    let onSwitchChat: (String) -> Void
    let onClearChat: () -> Void

    var body: some View {
        CommandOutputContent(
            maxHeight: self.maxHeight,
            onDismiss: self.onDismiss,
            onSubmit: self.onSubmit,
            onNewChat: self.onNewChat,
            onSwitchChat: self.onSwitchChat,
            onClearChat: self.onClearChat
        )
        .sayItOverlayTheme()
    }
}

private struct CommandOutputContent: View {
    let maxHeight: CGFloat
    let onDismiss: () -> Void
    let onSubmit: (String) async -> Void
    let onNewChat: () -> Void
    let onSwitchChat: (String) -> Void
    let onClearChat: () -> Void

    @ObservedObject private var contentState = NotchContentState.shared
    @Environment(\.theme) private var theme
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var isConfirmingDelete = false

    private static let width: CGFloat = 380
    private static let minHeight: CGFloat = 120
    private static let userBubbleMaxWidth: CGFloat = 280
    private static let assistantBubbleMaxWidth: CGFloat = 320
    private static let previewLines = 3
    private static let deleteConfirmationWindow: Double = 3

    private var commandColor: Color {
        self.theme.overlay.command
    }

    @State private var headerAndPreviewHeight: CGFloat = 0
    @State private var inputHeight: CGFloat = 0
    @State private var conversationHeight: CGFloat = 0

    private var chromeHeight: CGFloat {
        self.headerAndPreviewHeight + self.inputHeight
    }

    /// Height follows the measured conversation, capped by the target screen (set by the manager).
    private var dynamicHeight: CGFloat {
        min(max(Self.minHeight, self.chromeHeight + self.conversationHeight), self.maxHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                self.headerView

                if self.contentState.isRecordingInExpandedMode, !self.contentState.cachedPreviewText.isEmpty {
                    OverlayTranscriptText(
                        text: self.contentState.cachedPreviewText,
                        font: AppFont.Overlay.transcriptCompact,
                        lines: Self.previewLines
                    )
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.sm)
                    .background(self.commandColor.opacity(0.08))
                    .motionTransition(edge: .top)
                }

                Rectangle()
                    .fill(self.theme.overlay.hairline)
                    .frame(height: 1)
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { self.headerAndPreviewHeight = $0 }

            self.conversationArea

            self.inputArea
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { self.inputHeight = $0 }
        }
        .frame(width: Self.width, height: self.dynamicHeight)
        .background(self.theme.overlay.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .motion(Motion.state, value: self.contentState.commandConversationHistory.count)
        .motion(Motion.state, value: self.contentState.isRecordingInExpandedMode)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                LevelMeter(
                    color: self.commandColor,
                    style: .commandHeader,
                    isLive: self.contentState.isRecordingInExpandedMode
                )
                .opacity(self.contentState.isRecordingInExpandedMode ? 1 : 0.4)

                if self.contentState.isRecordingInExpandedMode {
                    Text("Listening")
                        .font(AppFont.Overlay.status)
                        .foregroundStyle(self.commandColor)
                } else if self.contentState.isCommandProcessing {
                    OverlayShimmerText(text: "Working…", color: self.commandColor)
                } else {
                    Text("Command")
                        .font(AppFont.Overlay.status)
                        .foregroundStyle(self.commandColor)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer()

            HStack(spacing: Space.xs) {
                IconButton("New Chat", systemName: "plus", size: 24, action: self.onNewChat)
                    .disabled(self.contentState.isCommandProcessing)

                self.recentChatsMenu

                if self.isConfirmingDelete {
                    Button("Delete Chat?", action: self.confirmDelete)
                        .buttonStyle(.sayIt(.destructive, size: .small))
                        .transition(.opacity)
                } else {
                    IconButton("Delete Chat", systemName: "trash", role: .destructive, size: 24) {
                        self.requestDelete()
                    }
                    .disabled(self.contentState.isCommandProcessing)
                }

                Rectangle()
                    .fill(self.theme.overlay.hairline)
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, Space.xxs)

                OverlayKeyCap(text: "esc")
                IconButton("Close (Esc)", systemName: "xmark", size: 24, action: self.onDismiss)
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .onAppear {
            self.contentState.refreshRecentChats()
        }
    }

    private var recentChatsMenu: some View {
        Menu {
            let recentChats = self.contentState.recentChats
            let currentID = ChatHistoryStore.shared.currentChatID
            if recentChats.isEmpty {
                Text("No Recent Chats")
            } else {
                ForEach(recentChats) { chat in
                    Button {
                        if chat.id != currentID {
                            self.onSwitchChat(chat.id)
                        }
                    } label: {
                        if chat.id == currentID {
                            Label("\(chat.title) — \(chat.relativeTimeString)", systemImage: "checkmark")
                        } else {
                            Text("\(chat.title) — \(chat.relativeTimeString)")
                        }
                    }
                    .disabled(self.contentState.isCommandProcessing)
                }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(AppFont.icon)
                .foregroundStyle(self.theme.overlay.secondaryText)
                .frame(width: 24, height: 24)
        }
        .menuIndicator(.hidden)
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Recent Chats")
        .accessibilityLabel("Recent Chats")
    }

    /// Deleting is two clicks: the trash button turns into "Delete Chat?" for a few
    /// seconds, so a stray click cannot remove a conversation.
    private func requestDelete() {
        withMotion(Motion.state) { self.isConfirmingDelete = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.deleteConfirmationWindow) {
            withMotion(Motion.state) { self.isConfirmingDelete = false }
        }
    }

    private func confirmDelete() {
        self.isConfirmingDelete = false
        self.onClearChat()
    }

    // MARK: - Conversation

    private var conversationArea: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: Space.sm) {
                    ForEach(self.contentState.commandConversationHistory) { message in
                        self.messageView(for: message)
                            .id(message.id)
                    }

                    if !self.contentState.commandStreamingText.isEmpty {
                        self.streamingMessageView
                            .id("streaming")
                    }

                    if self.contentState.isCommandProcessing, self.contentState.commandStreamingText.isEmpty {
                        self.awaitingReplyIndicator
                            .id("processing")
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.sm)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { self.conversationHeight = $0 }
            }
            .onAppear {
                self.scrollToBottom(proxy, animated: false)
            }
            .onChange(of: self.contentState.commandConversationHistory.count) { _, _ in
                self.scrollToBottom(proxy, animated: true)
            }
            .onChange(of: self.contentState.commandStreamingText) { _, _ in
                // No animation while streaming: it updates many times per second.
                self.scrollToBottom(proxy, animated: false)
            }
            .onChange(of: self.contentState.isCommandProcessing) { _, _ in
                self.scrollToBottom(proxy, animated: true)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        DispatchQueue.main.async {
            if animated {
                withMotion(Motion.state) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func messageView(for message: NotchContentState.CommandOutputMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: Space.xl)
                Text(message.content)
                    .font(AppFont.callout)
                    .foregroundStyle(self.theme.overlay.primaryText)
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .fill(self.commandColor.opacity(0.18))
                    )
                    .frame(maxWidth: Self.userBubbleMaxWidth, alignment: .trailing)
                    .textSelection(.enabled)
            }

        case .assistant:
            HStack {
                Text(message.content)
                    .font(AppFont.callout)
                    .foregroundStyle(self.theme.overlay.primaryText)
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .fill(self.theme.overlay.surfaceRaised)
                    )
                    .frame(maxWidth: Self.assistantBubbleMaxWidth, alignment: .leading)
                    .textSelection(.enabled)
                Spacer(minLength: Space.xl)
            }

        case .status:
            HStack(spacing: Space.xs) {
                Circle()
                    .fill(self.commandColor.opacity(0.7))
                    .frame(width: Space.xs, height: Space.xs)
                    .accessibilityHidden(true)
                Text(message.content)
                    .font(AppFont.Overlay.label)
                    .foregroundStyle(self.theme.overlay.tertiaryText)
                Spacer()
            }
            .padding(.vertical, Space.xxs)
        }
    }

    private var streamingMessageView: some View {
        HStack(alignment: .top) {
            Text(self.contentState.commandStreamingText)
                .font(AppFont.callout)
                .foregroundStyle(self.theme.overlay.primaryText)
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(self.theme.overlay.surfaceRaised)
                )
                .frame(maxWidth: Self.assistantBubbleMaxWidth, alignment: .leading)
            Spacer(minLength: Space.xl)
        }
    }

    /// Static marker while waiting for the first token; the header shimmer is the only
    /// moving element during work.
    private var awaitingReplyIndicator: some View {
        HStack(spacing: Space.xs) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(self.commandColor.opacity(0.5))
                    .frame(width: Space.xs, height: Space.xs)
            }
        }
        .padding(.vertical, Space.xs)
        .accessibilityLabel("Waiting for a reply")
    }

    // MARK: - Input

    private var inputArea: some View {
        HStack(spacing: Space.sm) {
            TextField("Ask a follow-up…", text: self.$inputText)
                .textFieldStyle(.plain)
                .font(AppFont.callout)
                .foregroundStyle(self.theme.overlay.primaryText)
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(self.theme.overlay.surfaceRaised)
                )
                .focused(self.$isInputFocused)
                .onSubmit {
                    self.submitFollowUp()
                }
                .accessibilityLabel("Follow-up command")

            Button(action: self.submitFollowUp) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(AppFont.iconLarge)
                    .foregroundStyle(self.inputText.isEmpty ? self.theme.overlay.tertiaryText : self.commandColor)
            }
            .buttonStyle(.plain)
            .disabled(self.inputText.isEmpty || self.contentState.isCommandProcessing)
            .help("Send")
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
    }

    private func submitFollowUp() {
        guard !self.inputText.isEmpty else { return }
        let text = self.inputText
        self.inputText = ""

        Task {
            await self.onSubmit(text)
        }
    }
}
