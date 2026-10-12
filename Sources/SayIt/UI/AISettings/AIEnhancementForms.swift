import AppKit
import SwiftUI

// Form-level components for the AI Enhancement page. Plain inputs and closures only.

// MARK: - Verified Provider Row

/// A provider that passed verification. Selecting the row makes it the active provider.
struct AIVerifiedProviderRow<Trailing: View, Expanded: View>: View {
    @Environment(\.theme) private var theme
    @State private var isHovered = false

    let providerID: String
    let name: String
    let isSelected: Bool
    let isExpanded: Bool
    let onSelect: () -> Void
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var expanded: Expanded

    init(
        providerID: String,
        name: String,
        isSelected: Bool,
        isExpanded: Bool,
        onSelect: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder expanded: () -> Expanded
    ) {
        self.providerID = providerID
        self.name = name
        self.isSelected = isSelected
        self.isExpanded = isExpanded
        self.onSelect = onSelect
        self.trailing = trailing()
        self.expanded = expanded()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.md) {
                Button(action: self.onSelect) {
                    HStack(spacing: Space.md) {
                        AIRadioMark(isOn: self.isSelected)
                        AIProviderRowLabel(
                            providerID: self.providerID,
                            name: self.name,
                            badges: self.isSelected ? [.verified, .active] : [.verified]
                        )
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(self.name)
                .accessibilityValue(self.isSelected ? "Verified, in use" : "Verified")
                .accessibilityAddTraits(self.isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityHint("Makes AI Enhancement use this provider")

                self.trailing
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm + Space.xxs)

            if self.isExpanded {
                Rectangle()
                    .fill(self.theme.palette.separator)
                    .frame(height: 1)
                    .padding(.horizontal, Space.md)
                self.expanded
                    .padding(Space.lg)
                    .motionTransition(edge: .top)
            }
        }
        .aiRowSurface(isSelected: self.isSelected, isHovered: self.isHovered)
        .onHover { self.isHovered = $0 }
        .motion(Motion.snappy, value: self.isHovered)
        .motion(Motion.state, value: self.isExpanded)
        .motion(Motion.state, value: self.isSelected)
    }
}

// MARK: - Provider Website Link

struct AIProviderWebsiteLink: View {
    let label: String
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(self.url)
        } label: {
            Label(self.label, systemImage: "arrow.up.right")
                .labelStyle(TrailingIconLabelStyle())
        }
        .buttonStyle(.sayIt(.quiet, size: .small))
        .help(self.url.absoluteString)
        .accessibilityHint("Opens \(self.url.host ?? "the provider's website") in your browser")
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.xs) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}

// MARK: - Provider Form

struct AIProviderFormState: Equatable {
    var isCustom: Bool
    var isLocal: Bool
    var websiteLabel: String?
    var websiteURL: URL?
    /// The first thing the user still has to do before verifying, if any.
    var missingRequirement: String?
    var canVerify: Bool
    var isVerifying: Bool
    var errorMessage: String?
}

/// Settings for a provider that has not been verified yet.
struct AIProviderForm<ModelControl: View, Extra: View>: View {
    @Binding var name: String
    @Binding var baseURL: String
    @Binding var apiKey: String
    let state: AIProviderFormState
    let onVerify: () -> Void
    var onDelete: (() -> Void)?
    @ViewBuilder var modelControl: ModelControl
    @ViewBuilder var extra: Extra

    init(
        name: Binding<String>,
        baseURL: Binding<String>,
        apiKey: Binding<String>,
        state: AIProviderFormState,
        onVerify: @escaping () -> Void,
        onDelete: (() -> Void)? = nil,
        @ViewBuilder modelControl: () -> ModelControl,
        @ViewBuilder extra: () -> Extra = { EmptyView() }
    ) {
        self._name = name
        self._baseURL = baseURL
        self._apiKey = apiKey
        self.state = state
        self.onVerify = onVerify
        self.onDelete = onDelete
        self.modelControl = modelControl()
        self.extra = extra()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            if self.state.isCustom {
                AIField("Name") {
                    TextField("Name", text: self.$name, prompt: Text("My Provider"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .frame(maxWidth: AIEnhancementLayout.fieldMaxWidth)
                }
            }

            AIField("Base URL") {
                TextField("Base URL", text: self.$baseURL, prompt: Text(verbatim: "https://api.example.com/v1"))
                    .textFieldStyle(.roundedBorder)
                    .font(AppFont.mono)
                    .labelsHidden()
                    .frame(maxWidth: AIEnhancementLayout.fieldMaxWidth)
            }

            AIField("API Key", helper: self.state.isLocal ? "Optional for local servers" : nil) {
                HStack(spacing: Space.sm) {
                    SecureField("API Key", text: self.$apiKey, prompt: Text("Paste your API key"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .frame(maxWidth: AIEnhancementLayout.apiKeyFieldWidth)
                    if let label = self.state.websiteLabel, let url = self.state.websiteURL {
                        AIProviderWebsiteLink(label: label, url: url)
                    }
                }
            }

            AIField("Model") {
                self.modelControl
            }

            self.extra

            if let error = self.state.errorMessage, !error.isEmpty {
                AIInlineNotice(kind: .error, text: error)
                    .motionTransition(edge: .top)
            }

            HStack(spacing: Space.md) {
                Button(action: self.onVerify) {
                    HStack(spacing: Space.sm) {
                        if self.state.isVerifying {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityHidden(true)
                        }
                        Text(self.state.isVerifying ? "Verifying…" : "Verify Connection")
                    }
                }
                .buttonStyle(.sayItPrimary)
                .disabled(!self.state.canVerify || self.state.isVerifying)

                if let requirement = self.state.missingRequirement {
                    AIHint(text: requirement)
                }

                Spacer(minLength: Space.md)

                if let onDelete {
                    Button("Delete Provider…", action: onDelete)
                        .buttonStyle(.sayItDestructive)
                }
            }
        }
    }
}

// MARK: - Edit Verified Provider

struct AIEditProviderForm: View {
    @Binding var name: String
    @Binding var baseURL: String
    @Binding var apiKey: String
    let isBuiltIn: Bool
    let isAppleIntelligence: Bool
    let isVerified: Bool
    var websiteLabel: String?
    var websiteURL: URL?
    let canSave: Bool
    let onSave: () -> Void
    let onCancel: () -> Void
    let onResetVerification: () -> Void
    var onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            if self.isAppleIntelligence {
                AIInlineNotice(kind: .info, text: "Apple Intelligence runs on this Mac and doesn't need an API key or base URL.")
            } else {
                if !self.isBuiltIn {
                    AIField("Name") {
                        TextField("Name", text: self.$name, prompt: Text("My Provider"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .frame(maxWidth: AIEnhancementLayout.fieldMaxWidth)
                    }
                }
                AIField("Base URL") {
                    TextField("Base URL", text: self.$baseURL, prompt: Text(verbatim: "http://localhost:11434/v1"))
                        .textFieldStyle(.roundedBorder)
                        .font(AppFont.mono)
                        .labelsHidden()
                        .frame(maxWidth: AIEnhancementLayout.fieldMaxWidth)
                }
                AIField("API Key") {
                    HStack(spacing: Space.sm) {
                        SecureField("API Key", text: self.$apiKey, prompt: Text("Paste your API key"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .frame(maxWidth: AIEnhancementLayout.apiKeyFieldWidth)
                        if let label = self.websiteLabel, let url = self.websiteURL {
                            AIProviderWebsiteLink(label: label, url: url)
                        }
                    }
                }
                AIHint(text: "Saving changes to the base URL or API key resets verification.")
            }

            HStack(spacing: Space.md) {
                if !self.isAppleIntelligence {
                    Button("Save", action: self.onSave)
                        .buttonStyle(.sayItPrimary)
                        .disabled(!self.canSave)
                    Button("Cancel", action: self.onCancel)
                        .buttonStyle(.sayItSecondary)
                }
                Spacer(minLength: Space.md)
                if self.isVerified {
                    Button("Reset Verification", action: self.onResetVerification)
                        .buttonStyle(.sayItSecondary)
                }
                if let onDelete {
                    Button("Delete Provider…", action: onDelete)
                        .buttonStyle(.sayItDestructive)
                }
            }
        }
    }
}

// MARK: - Custom Provider Button

struct AIAddCustomProviderButton: View {
    @Environment(\.theme) private var theme
    @State private var isHovered = false
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: Space.md) {
                Image(systemName: "plus")
                    .font(AppFont.icon)
                    .foregroundStyle(self.theme.palette.accentForeground)
                    .frame(width: AIEnhancementLayout.logoTile, height: AIEnhancementLayout.logoTile)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(
                                self.theme.palette.accent.opacity(0.6),
                                style: StrokeStyle(lineWidth: 1, dash: AIEnhancementLayout.dashPattern)
                            )
                    )
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Add Custom Provider")
                        .font(AppFont.rowTitle)
                        .foregroundStyle(self.theme.palette.primaryText)
                    Text("Any OpenAI-compatible endpoint")
                        .font(AppFont.caption)
                        .foregroundStyle(self.theme.palette.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm + Space.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .aiRowSurface(isHovered: self.isHovered)
        .onHover { self.isHovered = $0 }
        .motion(Motion.snappy, value: self.isHovered)
    }
}

// MARK: - Search Field

struct AISearchField: View {
    @Environment(\.theme) private var theme
    let label: String
    let placeholder: String
    @Binding var text: String
    var onSubmit: (() -> Void)?

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(self.theme.palette.tertiaryText)
                .accessibilityHidden(true)
            TextField(self.label, text: self.$text, prompt: Text(self.placeholder))
                .textFieldStyle(.plain)
                .font(AppFont.body)
                .labelsHidden()
                .onSubmit { self.onSubmit?() }
            if !self.text.isEmpty {
                IconButton("Clear Search", systemName: "xmark.circle.fill", size: Space.xl) {
                    self.text = ""
                }
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(self.theme.palette.surfaceSunken)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(self.theme.palette.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Reasoning Panel

/// Optional reasoning parameter sent with each request for one model.
struct AIReasoningPanel: View {
    @Environment(\.theme) private var theme
    let modelName: String
    @Binding var isEnabled: Bool
    @Binding var parameterName: String
    @Binding var parameterValue: String
    let onSave: () -> Void
    let onCancel: () -> Void

    private static let effortParameter = "reasoning_effort"
    private static let thinkingParameter = "enable_thinking"
    private static let customTag = "custom"
    private static let effortValues = ["none", "minimal", "low", "medium", "high"]
    private static let thinkingValues = ["true", "false"]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Reasoning")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(self.theme.palette.primaryText)
                        .accessibilityAddTraits(.isHeader)
                    Text(self.modelName.isEmpty ? "For the selected model" : "For \(self.modelName)")
                        .font(AppFont.caption)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                IconButton("Close Reasoning Settings", systemName: "xmark", size: Space.xl + Space.xs, action: self.onCancel)
            }

            HStack(spacing: Space.md) {
                Text("Send a reasoning parameter with each request")
                    .font(AppFont.callout)
                    .foregroundStyle(self.theme.palette.primaryText)
                Spacer(minLength: Space.md)
                Toggle("Send a reasoning parameter with each request", isOn: self.$isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            if self.isEnabled {
                Grid(alignment: .leading, horizontalSpacing: Space.md, verticalSpacing: Space.sm) {
                    GridRow {
                        self.rowLabel("Parameter")
                        Picker("Parameter", selection: self.parameterKindBinding) {
                            Text(verbatim: Self.effortParameter).tag(Self.effortParameter)
                            Text(verbatim: Self.thinkingParameter).tag(Self.thinkingParameter)
                            Text("Custom…").tag(Self.customTag)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                    }

                    if self.isCustomParameter {
                        GridRow {
                            self.rowLabel("Name")
                            TextField("Parameter Name", text: self.$parameterName, prompt: Text(verbatim: "thinking_budget"))
                                .textFieldStyle(.roundedBorder)
                                .font(AppFont.mono)
                                .labelsHidden()
                                .frame(width: AIEnhancementLayout.reasoningControlWidth)
                        }
                    }

                    GridRow {
                        self.rowLabel("Value")
                        self.valueControl
                    }
                }
                .motionTransition(edge: .top)
            }

            HStack(spacing: Space.sm) {
                Button("Save", action: self.onSave)
                    .buttonStyle(.sayIt(.primary, size: .small))
                Button("Cancel", action: self.onCancel)
                    .buttonStyle(.sayIt(.secondary, size: .small))
            }
        }
        .padding(Space.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(self.theme.palette.surfaceSunken)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(self.theme.palette.hairline, lineWidth: 1)
        )
        .motion(Motion.state, value: self.isEnabled)
    }

    private var isCustomParameter: Bool {
        self.parameterName != Self.effortParameter && self.parameterName != Self.thinkingParameter
    }

    @ViewBuilder
    private var valueControl: some View {
        switch self.parameterName {
        case Self.effortParameter:
            Picker("Value", selection: self.$parameterValue) {
                ForEach(Self.effortValues, id: \.self) { Text(verbatim: $0).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        case Self.thinkingParameter:
            Picker("Value", selection: self.$parameterValue) {
                ForEach(Self.thinkingValues, id: \.self) { Text(verbatim: $0).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        default:
            TextField("Value", text: self.$parameterValue, prompt: Text("Value"))
                .textFieldStyle(.roundedBorder)
                .font(AppFont.mono)
                .labelsHidden()
                .frame(width: AIEnhancementLayout.reasoningControlWidth)
        }
    }

    private var parameterKindBinding: Binding<String> {
        Binding(
            get: { self.isCustomParameter ? Self.customTag : self.parameterName },
            set: { newValue in
                if newValue == Self.customTag {
                    if !self.isCustomParameter { self.parameterName = "" }
                    return
                }
                self.parameterName = newValue
                if newValue == Self.effortParameter, !Self.effortValues.contains(self.parameterValue) {
                    self.parameterValue = "low"
                } else if newValue == Self.thinkingParameter, !Self.thinkingValues.contains(self.parameterValue) {
                    self.parameterValue = "true"
                }
            }
        )
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFont.caption)
            .foregroundStyle(self.theme.palette.secondaryText)
            .frame(width: AIEnhancementLayout.reasoningLabelWidth, alignment: .leading)
    }
}

// MARK: - Edit Mode Model

/// Which provider and model Edit Mode uses.
struct AIEditModeModelSection<Pickers: View>: View {
    @Environment(\.theme) private var theme
    let hasVerifiedProviders: Bool
    @Binding var isLinked: Bool
    /// "OpenAI · gpt-4.1", shown while linked.
    let linkedDescription: String
    @ViewBuilder var pickers: Pickers

    init(
        hasVerifiedProviders: Bool,
        isLinked: Binding<Bool>,
        linkedDescription: String,
        @ViewBuilder pickers: () -> Pickers
    ) {
        self.hasVerifiedProviders = hasVerifiedProviders
        self._isLinked = isLinked
        self.linkedDescription = linkedDescription
        self.pickers = pickers()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Model for Edit Mode")
                .font(AppFont.captionEmphasis)
                .foregroundStyle(self.theme.palette.secondaryText)

            if !self.hasVerifiedProviders {
                AIHint(text: "Verify a provider above to choose a model for Edit Mode.")
            } else {
                Toggle("Use the same provider and model as Dictate Mode", isOn: self.$isLinked)
                    .toggleStyle(.checkbox)
                    .font(AppFont.callout)
                if self.isLinked {
                    Text(self.linkedDescription.isEmpty ? "Uses the Dictate Mode model." : "Uses \(self.linkedDescription).")
                        .font(AppFont.caption)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .motionTransition(edge: .top)
                } else {
                    self.pickers
                        .motionTransition(edge: .top)
                }
            }
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(self.theme.palette.surfaceSunken)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(self.theme.palette.hairline, lineWidth: 1)
        )
        .motion(Motion.state, value: self.isLinked)
    }
}

// MARK: - Read-only Transcript Box

/// Selectable, read-only text set in the transcript face (spoken words read as written).
struct AITranscriptBox: View {
    @Environment(\.theme) private var theme
    let text: String
    let placeholder: String
    var minHeight: CGFloat = AIEnhancementLayout.promptTestOutputMinHeight

    var body: some View {
        ScrollView {
            Text(self.text.isEmpty ? self.placeholder : self.text)
                .font(AppFont.transcript)
                .foregroundStyle(self.text.isEmpty ? self.theme.palette.tertiaryText : self.theme.palette.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(Space.md)
        }
        .frame(minHeight: self.minHeight)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(self.theme.palette.surfaceSunken)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(self.theme.palette.hairline, lineWidth: 1)
        )
    }
}

// MARK: - Prompt Editor

enum AIPromptEditorKind: Equatable {
    case builtIn(SettingsStore.PromptMode)
    case new
    case edit
}

struct AIPromptTestState: Equatable {
    var canTest: Bool
    var shortcut: String
    var isProcessing: Bool
    var error: String
    var transcript: String
    var output: String
}

struct AIPromptEditorForm: View {
    @Environment(\.theme) private var theme
    let kind: AIPromptEditorKind
    @Binding var mode: SettingsStore.PromptMode
    @Binding var name: String
    @Binding var promptText: String
    @Binding var isTesting: Bool
    let testState: AIPromptTestState
    let contextTemplate: String
    let editorSessionID: UUID
    let canSave: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(self.title)
                    .font(AppFont.pageTitle)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text(self.subtitle)
                    .font(AppFont.callout)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !self.isBuiltIn {
                HStack(alignment: .top, spacing: Space.lg) {
                    AIField("Name") {
                        TextField("Name", text: self.$name, prompt: Text("Prompt name"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                    }
                    AIField("Mode") {
                        Picker("Mode", selection: self.$mode) {
                            ForEach(SettingsStore.PromptMode.visiblePromptModes) { mode in
                                Text(AIPromptModeHeader.shortName(for: mode)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }

            AIField("Instructions") {
                PromptTextView(
                    text: self.$promptText,
                    isEditable: true,
                    font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular),
                    accessibilityLabel: "Prompt instructions"
                )
                .id(self.editorSessionID)
                .frame(minHeight: AIEnhancementLayout.promptEditorMinHeight)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(self.theme.palette.surfaceSunken)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(self.theme.palette.hairline, lineWidth: 1)
                )
            }

            if self.mode.normalized == .dictate {
                self.testSection
            } else {
                AIField("Added Automatically", helper: "When text is selected") {
                    Text(verbatim: self.contextTemplate)
                        .font(AppFont.mono)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .textSelection(.enabled)
                        .padding(Space.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(self.theme.palette.surfaceSunken)
                        )
                }
            }

            HStack(spacing: Space.md) {
                Spacer()
                Button("Cancel", action: self.onCancel)
                    .buttonStyle(.sayItSecondary)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: self.onSave)
                    .buttonStyle(.sayItPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!self.canSave)
            }
        }
        .padding(Space.xxl)
        .frame(minWidth: AIEnhancementLayout.sheetMinWidth, minHeight: AIEnhancementLayout.sheetMinHeight, alignment: .topLeading)
        .background(self.theme.palette.contentBackground)
        .motion(Motion.state, value: self.mode)
        .motion(Motion.state, value: self.isTesting)
    }

    private var isBuiltIn: Bool {
        if case .builtIn = self.kind { return true }
        return false
    }

    private var title: String {
        switch self.kind {
        case let .builtIn(mode): return "Default \(AIPromptModeHeader.shortName(for: mode)) Prompt"
        case .new: return "New \(AIPromptModeHeader.shortName(for: self.mode)) Prompt"
        case .edit: return "Edit Prompt"
        }
    }

    private var subtitle: String {
        switch self.kind {
        case let .builtIn(mode):
            return "Your changes replace SayIt's default \(AIPromptModeHeader.shortName(for: mode)) prompt. You can reset it from the prompt's menu."
        case .new, .edit:
            return "Your instructions are added after SayIt's built-in instructions for this mode."
        }
    }

    private var testSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .top, spacing: Space.md) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Test This Prompt")
                        .font(AppFont.rowTitle)
                        .foregroundStyle(self.theme.palette.primaryText)
                    Text(self.testState.canTest
                        ? "Press \(self.testState.shortcut) to record. The result appears here — nothing is typed into other apps."
                        : "Set up and verify a provider to test prompts.")
                        .font(AppFont.caption)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.md)
                Toggle("Test This Prompt", isOn: self.$isTesting)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(!self.testState.canTest)
            }

            if self.isTesting {
                if self.testState.isProcessing {
                    HStack(spacing: Space.sm) {
                        ProgressView().controlSize(.small)
                        Text("Enhancing…")
                            .font(AppFont.caption)
                            .foregroundStyle(self.theme.palette.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                }
                if !self.testState.error.isEmpty {
                    AIInlineNotice(kind: .error, text: self.testState.error)
                }
                HStack(alignment: .top, spacing: Space.md) {
                    AIField("Transcript") {
                        AITranscriptBox(text: self.testState.transcript, placeholder: "What you say appears here.")
                    }
                    AIField("Enhanced Text") {
                        AITranscriptBox(text: self.testState.output, placeholder: "The enhanced text appears here.")
                    }
                }
                .motionTransition(edge: .top)
            }
        }
        .padding(Space.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(self.theme.palette.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(self.theme.palette.hairline, lineWidth: 1)
        )
    }
}
