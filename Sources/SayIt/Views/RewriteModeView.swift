import SwiftUI

/// "Edit Mode": write new text, or edit text selected in another app.
struct RewriteModeView: View {
    @ObservedObject var service: RewriteModeService
    @EnvironmentObject var appServices: AppServices
    private var asr: ASRService { self.appServices.asr }
    @ObservedObject var settings = SettingsStore.shared
    @Environment(\.theme) private var theme
    var onClose: (() -> Void)?

    @State private var inputText: String = ""

    // Local state for available models (derived from shared AI Settings pool)
    @State private var availableModels: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            self.header

            Divider()

            ScrollView {
                EditModeContent(
                    originalText: self.service.originalText,
                    resultText: self.service.rewrittenText,
                    errorText: self.errorText,
                    isProcessing: self.service.isProcessing,
                    shortcut: self.settings.rewriteModeShortcutEnabled ? self.settings.rewriteModeHotkeyShortcut.displayString : nil,
                    onTryAgain: { withMotion(Motion.exit) { self.service.rewrittenText = "" } },
                    onAccept: {
                        self.service.acceptRewrite()
                        self.onClose?()
                    },
                    onExample: { self.inputText = $0 }
                )
                .frame(maxWidth: ActivityUI.contentMaxWidth, alignment: .leading)
                .padding(.horizontal, Space.xxl)
                .padding(.vertical, Space.xl)
                .frame(maxWidth: .infinity)
            }

            if self.service.isProcessing, self.settings.showThinkingTokens, !self.service.streamingThinkingText.isEmpty {
                ReasoningDisclosure(text: self.service.streamingThinkingText, isLive: true)
                    .padding(.horizontal, Space.xxl)
                    .padding(.bottom, Space.sm)
                    .motionTransition()
            }

            Divider()

            self.inputBar
        }
        .background(self.theme.palette.contentBackground)
        .motion(Motion.state, value: self.service.rewrittenText.isEmpty)
        .onChange(of: self.asr.finalText) { _, newText in
            if !newText.isEmpty {
                self.inputText = newText
            }
        }
        .onExitCommand {
            self.onClose?()
        }
        .onAppear {
            // Note: Overlay mode is now set centrally by ContentView.handleModeTransition()
            self.updateAvailableModels()
        }
    }

    /// The last assistant message is an error when no result was produced.
    private var errorText: String? {
        guard self.service.rewrittenText.isEmpty,
              !self.service.isProcessing,
              let last = self.service.conversationHistory.last,
              last.role == .assistant
        else { return nil }
        return last.content
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: Space.md) {
            ActivityUI.Header(
                "Edit Mode",
                subtitle: "Write something new, or select text in any app and say how to change it."
            )
            if let onClose = self.onClose {
                IconButton("Close", systemName: "xmark", action: onClose)
            }
        }
        .padding(.horizontal, Space.xxl)
        .padding(.vertical, Space.lg)
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: Space.sm) {
            SearchableProviderPicker(
                builtInProviders: self.builtInProvidersList,
                savedProviders: self.settings.savedProviders,
                selectedProviderID: Binding(
                    get: { self.settings.rewriteModeSelectedProviderID },
                    set: { newValue in
                        // Prevent selecting disabled Apple Intelligence
                        if newValue == "apple-intelligence-disabled" {
                            self.settings.rewriteModeSelectedProviderID = "openai"
                        } else {
                            self.settings.rewriteModeSelectedProviderID = newValue
                        }
                        self.updateAvailableModels()
                    }
                )
            )

            if self.settings.rewriteModeSelectedProviderID != "apple-intelligence" {
                SearchableModelPicker(
                    models: self.availableModels,
                    selectedModel: Binding(
                        get: { self.settings.rewriteModeSelectedModel ?? self.availableModels.first ?? "" },
                        set: { self.settings.rewriteModeSelectedModel = $0 }
                    ),
                    onRefresh: nil,
                    isRefreshing: false
                )
            }

            TextField(
                self.service.originalText.isEmpty ? "Describe what to write…" : "Describe how to change it…",
                text: self.$inputText
            )
            .textFieldStyle(.roundedBorder)
            .font(AppFont.body)
            .onSubmit(self.submitRequest)

            if self.service.isProcessing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Working")
            } else {
                IconButton("Send", systemName: "arrow.up.circle.fill", role: .primary, action: self.submitRequest)
                    .disabled(self.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            IconButton(
                self.asr.isRunning ? "Stop Voice Input" : "Start Voice Input",
                systemName: self.asr.isRunning ? "stop.circle.fill" : "mic",
                role: self.asr.isRunning ? .destructive : .secondary,
                action: self.toggleRecording
            )
        }
        .padding(.horizontal, Space.xxl)
        .padding(.vertical, Space.md)
        .background(self.theme.palette.windowBackground)
    }

    // MARK: - Actions

    private func toggleRecording() {
        if self.asr.isRunning {
            Task { await self.asr.stop() }
        } else {
            Task { await self.asr.start() }
        }
    }

    private func submitRequest() {
        let prompt = self.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !self.service.isProcessing else { return }
        self.inputText = ""
        Task {
            await self.service.processRewriteRequest(prompt)
        }
    }

    // MARK: - Model Management (pulls from shared AI Settings pool)

    private func updateAvailableModels() {
        let currentProviderID = self.settings.rewriteModeSelectedProviderID
        let currentModel = self.settings.rewriteModeSelectedModel ?? "gpt-4.1"

        // Apple Intelligence has only one model
        if currentProviderID == "apple-intelligence" {
            self.availableModels = ["System Model"]
            return
        }

        let possibleKeys = ModelRepository.shared.providerKeys(for: currentProviderID)
        let storedList = possibleKeys.lazy
            .compactMap { SettingsStore.shared.availableModelsByProvider[$0] }
            .first { !$0.isEmpty }

        if let stored = storedList {
            self.availableModels = stored
        } else {
            self.availableModels = ModelRepository.shared.defaultModels(for: currentProviderID)
        }

        // If current model not in list, select first available
        if !self.availableModels.contains(currentModel) {
            self.settings.rewriteModeSelectedModel = self.availableModels.first ?? "gpt-4.1"
        }
    }

    private var builtInProvidersList: [(id: String, name: String)] {
        ModelRepository.shared.builtInProvidersList(
            includeAppleIntelligence: true,
            appleIntelligenceAvailable: AppleIntelligenceService.isAvailable
        )
    }
}

// MARK: - Content

/// Selected text, the result and the empty state. Pure presentation.
struct EditModeContent: View {
    @Environment(\.theme) private var theme

    let originalText: String
    let resultText: String
    let errorText: String?
    let isProcessing: Bool
    let shortcut: String?
    let onTryAgain: () -> Void
    let onAccept: () -> Void
    var onExample: (String) -> Void = { _ in }

    @State private var showOriginal = true

    private var isEditingSelection: Bool {
        !self.originalText.isEmpty
    }

    static let writeExamples = ["Write an email asking for Friday off", "Draft a thank-you note to the team"]
    static let editExamples = ["Make this more formal", "Fix the grammar and spelling", "Summarize this in two sentences"]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            if self.isEditingSelection {
                self.selectedTextSection
            } else if self.resultText.isEmpty, self.errorText == nil {
                self.emptyState
            }

            if self.isProcessing, self.resultText.isEmpty {
                HStack(spacing: Space.sm) {
                    ProgressView().controlSize(.small)
                    Text(self.isEditingSelection ? "Editing…" : "Writing…")
                        .font(AppFont.callout)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .ambientPulse(isActive: true)
                }
                .accessibilityElement(children: .combine)
                .motionTransition()
            }

            if !self.resultText.isEmpty {
                self.resultSection
                    .motionTransition()
            }

            if let errorText = self.errorText {
                ActivityUI.Banner(.error, title: "Couldn’t complete the request", message: errorText)
                    .motionTransition()
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            ActivityUI.EmptyState(
                systemImage: "pencil.line",
                title: "Write or Edit by Voice",
                message: "Ask SayIt to write anything — emails, replies, summaries, answers. Or select text in any app first to edit it."
            )

            HStack(alignment: .top, spacing: Space.xl) {
                self.examples(title: "Write Something New", examples: Self.writeExamples)
                self.examples(title: "Edit Selected Text", examples: Self.editExamples)
            }

            if let shortcut = self.shortcut {
                HStack(spacing: Space.xs) {
                    Text("From any app, press")
                    ActivityUI.KeyCap(shortcut)
                    Text("and say what you want.")
                }
                .font(AppFont.caption)
                .foregroundStyle(self.theme.palette.secondaryText)
            }
        }
    }

    private func examples(title: String, examples: [String]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title)
                .font(AppFont.captionEmphasis)
                .foregroundStyle(self.theme.palette.secondaryText)
            ForEach(examples, id: \.self) { example in
                Button {
                    self.onExample(example)
                } label: {
                    Text("“\(example)”")
                        .font(AppFont.transcript)
                }
                .buttonStyle(.sayIt(.quiet, size: .small))
                .accessibilityHint("Puts this request in the message field")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectedTextSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                Text("Selected Text")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(self.theme.palette.secondaryText)
                Spacer()
                if !self.resultText.isEmpty {
                    Button(self.showOriginal ? "Hide" : "Show") {
                        withMotion(Motion.state) { self.showOriginal.toggle() }
                    }
                    .buttonStyle(.sayIt(.quiet, size: .small))
                    .accessibilityLabel(self.showOriginal ? "Hide Selected Text" : "Show Selected Text")
                }
            }
            if self.showOriginal || self.resultText.isEmpty {
                ActivityUI.TranscriptBlock(text: self.originalText, emphasis: false)
                    .motionTransition(edge: .top)
            }
        }
    }

    private var resultSection: some View {
        ThemedCard(style: .prominent) {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack {
                    Text(self.isEditingSelection ? "Edited Text" : "Draft")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(self.theme.palette.secondaryText)
                    Spacer()
                    ActivityUI.CopyButton(text: self.resultText)
                }
                Text(self.resultText)
                    .font(AppFont.transcriptLarge)
                    .lineSpacing(Space.xs)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Space.sm) {
                    Button("Try Again", action: self.onTryAgain)
                        .buttonStyle(.sayItSecondary)
                    Spacer()
                    Button(self.isEditingSelection ? "Replace Selection" : "Insert Text", action: self.onAccept)
                        .buttonStyle(.sayItPrimary)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
    }
}
