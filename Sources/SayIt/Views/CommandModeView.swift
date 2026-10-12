import SwiftUI

struct CommandModeView: View {
    @ObservedObject var service: CommandModeService
    @EnvironmentObject var appServices: AppServices
    private var asr: ASRService { self.appServices.asr }
    @ObservedObject var settings = SettingsStore.shared
    var onClose: (() -> Void)?
    @State private var inputText: String = ""

    // Local state for available models (derived from shared AI Settings pool)
    @State private var availableModels: [String] = []

    @State private var showingDeleteConfirmation = false

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            self.header

            Divider()

            CommandConversationView(
                messages: self.service.conversationHistory,
                isProcessing: self.service.isProcessing,
                stepLabel: Self.stepLabel(for: self.service.currentStep),
                streamingText: self.service.streamingText,
                thinkingText: self.service.streamingThinkingText,
                showThinking: self.settings.showThinkingTokens,
                shortcut: self.settings.commandModeShortcutEnabled ? self.settings.commandModeHotkeyShortcut.displayString : nil,
                scrollTrigger: self.service.currentStep.map { "\($0)" } ?? "",
                onExample: { self.inputText = $0 }
            )

            if let pending = self.service.pendingCommand {
                CommandConfirmationCard(
                    command: pending.command,
                    purpose: pending.purpose,
                    onCancel: { self.service.cancelPendingCommand() },
                    onRun: { Task { await self.service.confirmAndExecute() } }
                )
                .motionTransition()
            }

            Divider()

            self.inputBar
        }
        .background(self.theme.palette.contentBackground)
        .motion(Motion.state, value: self.service.pendingCommand?.id)
        .onAppear {
            self.updateAvailableModels()
            // Disable notch output when using in-app UI (conversation is shared but notch shouldn't show)
            self.service.enableNotchOutput = false
        }
        .onDisappear {
            // Re-enable notch output when leaving in-app UI
            self.service.enableNotchOutput = true
        }
        .onChange(of: self.asr.finalText) { _, newText in
            if !newText.isEmpty {
                self.inputText = newText
            }
        }
        .onChange(of: self.settings.commandModeSelectedProviderID) { _, _ in
            self.updateAvailableModels()
        }
        .onExitCommand {
            guard self.service.pendingCommand == nil else { return }
            self.onClose?()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.sm) {
                    Text("Command Mode")
                        .font(AppFont.pageTitle)
                        .foregroundStyle(self.theme.palette.primaryText)
                        .accessibilityAddTraits(.isHeader)
                    ActivityUI.Badge(text: "Alpha", tint: self.theme.palette.secondaryText)
                }
                Text("Ask SayIt to run commands and answer questions on your Mac.")
                    .font(AppFont.callout)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }

            Spacer(minLength: Space.md)

            Toggle("Confirm before running", isOn: self.$settings.commandModeConfirmBeforeExecute)
                .toggleStyle(.checkbox)
                .font(AppFont.callout)
                .help("Ask before running each command")

            HStack(spacing: Space.xxs) {
                IconButton("New Chat", systemName: "square.and.pencil") {
                    self.service.createNewChat()
                }
                .disabled(self.service.isProcessing)

                self.recentChatsMenu

                IconButton("Delete Chat", systemName: "trash", role: .destructive) {
                    self.showingDeleteConfirmation = true
                }
                .disabled(self.service.isProcessing || self.service.conversationHistory.isEmpty)
            }
        }
        .padding(.horizontal, Space.xxl)
        .padding(.vertical, Space.lg)
        .confirmationDialog(
            "Delete this chat?",
            isPresented: self.$showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Chat", role: .destructive) {
                self.service.deleteCurrentChat()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“\(self.currentChatTitle)” and its \(CopyFormat.count(self.service.conversationHistory.count, "message")) are removed from this Mac.")
        }
    }

    private var currentChatTitle: String {
        self.service.getRecentChats().first { $0.id == self.service.currentChatID }?.title ?? "This chat"
    }

    private var recentChatsMenu: some View {
        Menu {
            let recentChats = self.service.getRecentChats()
            if recentChats.isEmpty {
                Text("No recent chats")
            } else {
                ForEach(recentChats) { chat in
                    Button {
                        if chat.id != self.service.currentChatID {
                            _ = self.service.switchToChat(id: chat.id)
                        }
                    } label: {
                        if chat.id == self.service.currentChatID {
                            Label("\(chat.title) — \(chat.relativeTimeString)", systemImage: "checkmark")
                        } else {
                            Text("\(chat.title) — \(chat.relativeTimeString)")
                        }
                    }
                    .disabled(self.service.isProcessing)
                }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(AppFont.icon)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Recent Chats")
        .accessibilityLabel("Recent Chats")
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: Space.sm) {
            SearchableProviderPicker(
                builtInProviders: self.builtInProvidersList,
                savedProviders: self.settings.savedProviders,
                selectedProviderID: Binding(
                    get: { self.settings.commandModeSelectedProviderID },
                    set: { newValue in
                        // Prevent selecting disabled Apple Intelligence
                        if newValue == "apple-intelligence-disabled" || newValue == "apple-intelligence" {
                            self.settings.commandModeSelectedProviderID = "openai"
                        } else {
                            self.settings.commandModeSelectedProviderID = newValue
                        }
                        self.updateAvailableModels()
                    }
                )
            )

            SearchableModelPicker(
                models: self.availableModels,
                selectedModel: Binding(
                    get: { self.settings.commandModeSelectedModel ?? self.availableModels.first ?? "" },
                    set: { self.settings.commandModeSelectedModel = $0 }
                ),
                onRefresh: nil,
                isRefreshing: false
            )

            TextField("Type a command or ask a question…", text: self.$inputText)
                .textFieldStyle(.roundedBorder)
                .font(AppFont.body)
                .onSubmit(self.submitCommand)

            IconButton("Send", systemName: "arrow.up.circle.fill", role: .primary, action: self.submitCommand)
                .disabled(self.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || self.service.isProcessing)

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

    private func submitCommand() {
        let text = self.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !self.service.isProcessing else { return }
        self.inputText = ""
        Task {
            await self.service.processUserCommand(text)
        }
    }

    private func updateAvailableModels() {
        let currentProviderID = self.settings.commandModeSelectedProviderID
        let currentModel = self.settings.commandModeSelectedModel ?? "gpt-4.1"

        // Pull models from the shared pool configured in AI Settings
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
            self.settings.commandModeSelectedModel = self.availableModels.first ?? "gpt-4.1"
        }
    }

    private var builtInProvidersList: [(id: String, name: String)] {
        // Apple Intelligence disabled for Command Mode (no tool support)
        ModelRepository.shared.builtInProvidersList(
            includeAppleIntelligence: true,
            appleIntelligenceAvailable: false,
            appleIntelligenceDisabledReason: "No tool support"
        )
    }

    static func stepLabel(for step: CommandModeService.AgentStep?) -> String {
        guard let step else { return "Working…" }
        switch step {
        case .thinking: return "Thinking…"
        case let .checking(cmd): return "Checking \(Self.truncate(cmd, to: 32))…"
        case let .executing(cmd): return "Running \(Self.truncate(cmd, to: 32))…"
        case .verifying: return "Verifying…"
        case let .completed(success): return success ? "Done" : "Stopped"
        }
    }

    private static func truncate(_ text: String, to limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }
}

// MARK: - Conversation

/// The chat transcript, the working indicator and the empty state. Pure presentation.
struct CommandConversationView: View {
    @Environment(\.theme) private var theme

    let messages: [CommandModeService.Message]
    let isProcessing: Bool
    let stepLabel: String
    let streamingText: String
    let thinkingText: String
    let showThinking: Bool
    let shortcut: String?
    var scrollTrigger: String = ""
    var onExample: (String) -> Void = { _ in }

    static let examples = [
        "List the files in my Downloads folder",
        "Create a folder called Projects on the Desktop",
        "What’s my IP address?",
        "Open Safari",
    ]

    private static let columnMaxWidth: CGFloat = 640

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    if self.messages.isEmpty, !self.isProcessing {
                        self.emptyState
                    }

                    ForEach(self.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    if self.isProcessing {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            WorkingIndicator(label: self.stepLabel)

                            if self.showThinking, !self.thinkingText.isEmpty {
                                ReasoningDisclosure(text: self.thinkingText, isLive: true)
                            }

                            if !self.streamingText.isEmpty {
                                Text(self.streamingText)
                                    .font(AppFont.body)
                                    .foregroundStyle(self.theme.palette.primaryText)
                                    .frame(maxWidth: MessageBubble.agentMaxWidth, alignment: .leading)
                            }
                        }
                        .id("processing")
                        .motionTransition()
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: Self.columnMaxWidth, alignment: .leading)
                .padding(.horizontal, Space.xxl)
                .padding(.vertical, Space.xl)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: self.messages.count) { _, _ in self.scrollToBottom(proxy) }
            .onChange(of: self.isProcessing) { _, processing in
                if processing { self.scrollToBottom(proxy) }
            }
            .onChange(of: self.scrollTrigger) { _, _ in self.scrollToBottom(proxy) }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            ActivityUI.EmptyState(
                systemImage: "terminal",
                title: "Ask Your Mac",
                message: "Type or say a request. SayIt shows every command it runs, and asks before running anything destructive."
            )

            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Try")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(self.theme.palette.secondaryText)
                ForEach(Self.examples, id: \.self) { example in
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

            if let shortcut = self.shortcut {
                HStack(spacing: Space.xs) {
                    Text("From any app, press")
                    ActivityUI.KeyCap(shortcut)
                    Text("and speak your request.")
                }
                .font(AppFont.caption)
                .foregroundStyle(self.theme.palette.secondaryText)
            }

            HStack(alignment: .top, spacing: Space.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(self.theme.palette.warning)
                    .accessibilityHidden(true)
                Text("AI can make mistakes. Read each command before it runs, and don’t ask it to delete files you need.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(AppFont.caption)
            .foregroundStyle(self.theme.palette.secondaryText)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            withMotion(Motion.state) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}

// MARK: - Confirmation

/// Shown when a command needs approval. Run is ⌘↩ so a stray Return never runs it.
struct CommandConfirmationCard: View {
    @Environment(\.theme) private var theme

    let command: String
    let purpose: String?
    let onCancel: () -> Void
    let onRun: () -> Void

    var body: some View {
        let tint = self.theme.palette.warning
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Image(systemName: "exclamationmark.shield")
                    .font(AppFont.icon)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Run This Command?")
                        .font(AppFont.sectionTitle)
                        .foregroundStyle(self.theme.palette.primaryText)
                    if let purpose = self.purpose, !purpose.isEmpty {
                        Text(purpose)
                            .font(AppFont.callout)
                            .foregroundStyle(self.theme.palette.secondaryText)
                    }
                }
            }

            Text(self.command)
                .font(AppFont.mono)
                .foregroundStyle(self.theme.palette.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.md)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(self.theme.palette.surfaceSunken)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(tint.opacity(0.4), lineWidth: 1)
                )
                .accessibilityLabel("Command: \(self.command)")

            HStack(spacing: Space.sm) {
                Spacer()
                Button("Cancel", action: self.onCancel)
                    .buttonStyle(.sayItSecondary)
                    .keyboardShortcut(.cancelAction)
                Button(action: self.onRun) {
                    HStack(spacing: Space.sm) {
                        Text("Run Command")
                        Text("⌘↩")
                            .font(AppFont.micro)
                            .opacity(0.8)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.sayItPrimary)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.horizontal, Space.xxl)
        .padding(.vertical, Space.lg)
        .background(self.theme.palette.subtle(tint))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Working Indicator

/// Current agent step, breathing gently while work is in progress (static with Reduce Motion).
private struct WorkingIndicator: View {
    @Environment(\.theme) private var theme
    let label: String

    var body: some View {
        HStack(spacing: Space.sm) {
            ProgressView()
                .controlSize(.small)
            Text(self.label)
                .font(AppFont.callout)
                .foregroundStyle(self.theme.palette.secondaryText)
                .contentTransition(.opacity)
                .ambientPulse(isActive: true)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(
            Capsule().fill(self.theme.palette.surfaceRaised)
        )
        .overlay(Capsule().strokeBorder(self.theme.palette.hairline, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.label)
    }
}

// MARK: - Reasoning

/// The model's reasoning tokens, collapsed to a one-line preview by default.
struct ReasoningDisclosure: View {
    @Environment(\.theme) private var theme

    let text: String
    var isLive: Bool = false

    @State private var isExpanded = false

    private static let expandedMaxHeight: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Button {
                withMotion(Motion.state) { self.isExpanded.toggle() }
            } label: {
                HStack(spacing: Space.xs) {
                    Image(systemName: "chevron.right")
                        .font(AppFont.micro)
                        .rotationEffect(.degrees(self.isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                    Text(self.isLive ? "Thinking" : "Reasoning")
                        .font(AppFont.captionEmphasis)
                        .ambientPulse(isActive: self.isLive)
                    Text(CopyFormat.count(self.text.count, "character"))
                        .font(AppFont.caption)
                        .foregroundStyle(self.theme.palette.tertiaryText)
                }
                .foregroundStyle(self.theme.palette.secondaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(self.isLive ? "Thinking" : "Reasoning")
            .accessibilityValue(self.isExpanded ? "Expanded" : "Collapsed")

            if self.isExpanded {
                ScrollView(.vertical) {
                    Text(self.text)
                        .font(AppFont.caption)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: Self.expandedMaxHeight)
                .motionTransition(edge: .top)
            } else {
                Text(self.text)
                    .font(AppFont.caption)
                    .foregroundStyle(self.theme.palette.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(Space.sm + Space.xxs)
        .frame(maxWidth: MessageBubble.agentMaxWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(self.theme.palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(self.theme.palette.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: CommandModeService.Message
    @Environment(\.theme) private var theme

    static let userMaxWidth: CGFloat = 420
    static let agentMaxWidth: CGFloat = 560
    private static let outputMaxHeight: CGFloat = 160

    var body: some View {
        HStack(alignment: .top) {
            if self.message.role == .user {
                Spacer(minLength: Space.xxxl)
                self.userMessageView
            } else {
                self.agentMessageView
                Spacer(minLength: Space.xxxl)
            }
        }
    }

    // MARK: - User

    private var userMessageView: some View {
        Text(self.message.content)
            .font(AppFont.transcript)
            .foregroundStyle(self.theme.palette.primaryText)
            .textSelection(.enabled)
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(self.theme.palette.accentSubtle)
            )
            .frame(maxWidth: Self.userMaxWidth, alignment: .trailing)
            .accessibilityLabel("You: \(self.message.content)")
    }

    // MARK: - Agent

    private var agentMessageView: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if let thinking = self.message.thinking, !thinking.isEmpty, SettingsStore.shared.showThinkingTokens {
                ReasoningDisclosure(text: thinking)
            }

            if let toolCall = self.message.toolCall, let purpose = toolCall.purpose, !purpose.isEmpty {
                Text(purpose)
                    .font(AppFont.caption)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }

            if self.message.role == .tool {
                self.toolOutputView
            } else if let toolCall = self.message.toolCall {
                self.commandCallView(toolCall)
            } else if !self.message.content.isEmpty {
                Text(Self.markdown(self.message.content))
                    .font(AppFont.body)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: Self.agentMaxWidth, alignment: .leading)
    }

    private func commandCallView(_ toolCall: CommandModeService.Message.ToolCall) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            let content = self.message.content.lowercased()
            if !self.message.content.isEmpty,
               !content.starts(with: "checking"),
               !content.starts(with: "executing"),
               !content.starts(with: "i'll")
            {
                Text(self.message.content)
                    .font(AppFont.callout)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }

            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Image(systemName: "terminal")
                    .font(AppFont.iconSmall)
                    .foregroundStyle(self.theme.palette.tertiaryText)
                    .accessibilityHidden(true)
                Text(toolCall.command)
                    .font(AppFont.mono)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, Space.sm + Space.xxs)
            .padding(.vertical, Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(self.theme.palette.surfaceSunken)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Command: \(toolCall.command)")
        }
    }

    private var toolOutputView: some View {
        let parsed = Self.parseToolOutput(self.message.content)
        let tint = parsed.success ? self.theme.palette.success : self.theme.palette.error

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.xs) {
                Image(systemName: parsed.success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(parsed.success ? "Succeeded" : "Failed")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(self.theme.palette.primaryText)
                if !parsed.success, parsed.exitCode != 0, parsed.exitCode != -1 {
                    Text("Exit code \(parsed.exitCode)")
                        .font(AppFont.caption)
                        .foregroundStyle(self.theme.palette.secondaryText)
                }
                Spacer()
                if parsed.executionTime > 0 {
                    Text("\(parsed.executionTime.formatted()) ms")
                        .font(AppFont.caption)
                        .foregroundStyle(self.theme.palette.tertiaryText)
                }
            }
            .padding(.horizontal, Space.sm + Space.xxs)
            .padding(.vertical, Space.sm - Space.xxs)

            if !parsed.output.isEmpty || !(parsed.error ?? "").isEmpty {
                Divider()
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        if !parsed.output.isEmpty {
                            Text(Self.markdown(parsed.output))
                                .font(AppFont.mono)
                                .foregroundStyle(self.theme.palette.secondaryText)
                                .textSelection(.enabled)
                        }
                        if let error = parsed.error, !error.isEmpty {
                            Text(error)
                                .font(AppFont.mono)
                                .foregroundStyle(self.theme.palette.error)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.horizontal, Space.sm + Space.xxs)
                    .padding(.vertical, Space.sm - Space.xxs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: Self.outputMaxHeight)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(parsed.success ? self.theme.palette.surface : self.theme.palette.subtle(self.theme.palette.error))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(parsed.success ? self.theme.palette.hairline : self.theme.palette.error.opacity(0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(parsed.success ? "Command succeeded" : "Command failed")
    }

    // MARK: - Helpers

    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    private struct ParsedOutput {
        let success: Bool
        let output: String
        let error: String?
        let exitCode: Int
        let executionTime: Int
    }

    private static func parseToolOutput(_ json: String) -> ParsedOutput {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ParsedOutput(success: false, output: json, error: nil, exitCode: -1, executionTime: 0)
        }

        return ParsedOutput(
            success: parsed["success"] as? Bool ?? false,
            output: parsed["output"] as? String ?? "",
            error: parsed["error"] as? String,
            exitCode: parsed["exitCode"] as? Int ?? 0,
            executionTime: parsed["executionTimeMs"] as? Int ?? 0
        )
    }
}
