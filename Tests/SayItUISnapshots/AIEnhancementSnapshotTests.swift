import SwiftUI
import XCTest

@testable import SayIt

/// AI Enhancement page specimens. Built from the same presentational components as the
/// real page, with fixed in-memory data so rendering never touches settings or Keychain.
@MainActor
final class AIEnhancementSnapshotTests: XCTestCase {
    private let pageSize = CGSize(width: 760, height: 1180)

    func testPageWithVerifiedProvider() throws {
        try SnapshotRenderer.snapshot("ai-enhancement-page", size: self.pageSize) {
            AIEnhancementSpecimenPage(scenario: .configured)
        }
    }

    func testPageFirstRun() throws {
        try SnapshotRenderer.snapshot("ai-enhancement-first-run", size: CGSize(width: 760, height: 1320)) {
            AIEnhancementSpecimenPage(scenario: .firstRun)
        }
    }

    func testPageOff() throws {
        try SnapshotRenderer.snapshot("ai-enhancement-off", size: CGSize(width: 760, height: 300)) {
            AIEnhancementSpecimenPage(scenario: .off)
        }
    }

    func testProviderStates() throws {
        try SnapshotRenderer.snapshot("ai-enhancement-provider-states", size: CGSize(width: 680, height: 960)) {
            ProviderStatesSpecimen()
        }
    }

    func testPromptEditor() throws {
        try SnapshotRenderer.snapshot("ai-enhancement-prompt-editor", size: CGSize(width: 620, height: 760)) {
            PromptEditorSpecimen()
        }
    }

    func testPickerPopoverContent() throws {
        try SnapshotRenderer.snapshot("ai-enhancement-pickers", size: CGSize(width: 680, height: 220)) {
            PickerSpecimen()
        }
    }
}

// MARK: - Page Specimen

private struct AIEnhancementSpecimenPage: View {
    enum Scenario {
        case configured
        case firstRun
        case off
    }

    @Environment(\.theme) private var theme
    let scenario: Scenario
    @State private var linked = true

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            AIEnhancementPageHeader()
            AIEnhancementOverviewCard(isEnabled: .constant(self.scenario != .off), summary: self.summary)

            if self.scenario != .off {
                ThemedCard {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        AISectionHeading("Provider", subtitle: "Where AI Enhancement sends your transcript.") {
                            Button {} label: { Label("Setup Guide", systemImage: "questionmark.circle") }
                                .buttonStyle(.sayIt(.quiet, size: .small))
                        }
                        if self.scenario == .firstRun {
                            self.firstRunProviders
                        } else {
                            self.configuredProviders
                        }
                    }
                }
                if self.scenario == .configured {
                    self.prompts
                }
            }
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(self.theme.palette.contentBackground)
    }

    private var summary: AIEnhancementSummary {
        switch self.scenario {
        case .configured: return .ready(provider: "OpenAI", model: "gpt-4.1-mini")
        case .firstRun: return .incomplete(provider: "OpenAI")
        case .off: return .off
        }
    }

    private var configuredProviders: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.sm) {
                AIGroupLabel(title: "Ready to Use", count: 2)
                AIVerifiedProviderRow(
                    providerID: "openai",
                    name: "OpenAI",
                    isSelected: true,
                    isExpanded: false,
                    onSelect: {},
                    trailing: {
                        SearchableModelPicker(
                            models: ["gpt-4.1-mini"],
                            selectedModel: .constant("gpt-4.1-mini"),
                            onRefresh: {},
                            controlWidth: AIEnhancementLayout.modelPickerWidth
                        )
                        IconButton("Reasoning Settings", systemName: "brain") {}
                        Button("Edit") {}.buttonStyle(.sayIt(.quiet, size: .small))
                    },
                    expanded: { EmptyView() }
                )
                AIVerifiedProviderRow(
                    providerID: "ollama",
                    name: "Ollama",
                    isSelected: false,
                    isExpanded: false,
                    onSelect: {},
                    trailing: {
                        SearchableModelPicker(
                            models: ["qwen3:8b"],
                            selectedModel: .constant("qwen3:8b"),
                            onRefresh: {},
                            controlWidth: AIEnhancementLayout.modelPickerWidth
                        )
                        IconButton("Reasoning Settings (On)", systemName: "brain.fill", role: .quiet) {}
                        Button("Edit") {}.buttonStyle(.sayIt(.quiet, size: .small))
                    },
                    expanded: { EmptyView() }
                )
            }
            HStack(spacing: Space.xs) {
                Image(systemName: "chevron.right")
                    .font(AppFont.iconSmall)
                    .foregroundStyle(self.theme.palette.tertiaryText)
                AIGroupLabel(title: "Add Another Provider", count: 10)
            }
        }
    }

    private var firstRunProviders: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            AISetupGuide()
            VStack(alignment: .leading, spacing: Space.sm) {
                AIGroupLabel(title: "Ready to Use", count: 0)
                AIInlineNotice(
                    kind: .info,
                    text: "No provider is verified yet. Open one below, add its API key if it needs one, choose a model, then verify the connection."
                )
            }
            VStack(alignment: .leading, spacing: Space.sm) {
                AIGroupLabel(title: "All Providers", count: 12)
                AISearchField(label: "Search Providers", placeholder: "Search providers", text: .constant(""))
                AIProviderDisclosureRow(
                    providerID: "openai",
                    name: "OpenAI",
                    badges: [],
                    isExpanded: true,
                    onToggle: {},
                    details: {
                        AIProviderForm(
                            name: .constant(""),
                            baseURL: .constant("https://api.openai.com/v1"),
                            apiKey: .constant(""),
                            state: AIProviderFormState(
                                isCustom: false,
                                isLocal: false,
                                websiteLabel: "Get API Key",
                                websiteURL: URL(string: "https://platform.openai.com/api-keys"),
                                missingRequirement: "Enter an API key.",
                                canVerify: false,
                                isVerifying: false,
                                errorMessage: nil
                            ),
                            onVerify: {},
                            modelControl: {
                                SearchableModelPicker(
                                    models: ["gpt-4.1-mini", "gpt-4.1"],
                                    selectedModel: .constant("gpt-4.1-mini"),
                                    onRefresh: {},
                                    refreshEnabled: false,
                                    controlWidth: AIEnhancementLayout.modelPickerWidth
                                )
                            }
                        )
                    }
                )
                AIProviderDisclosureRow(providerID: "anthropic", name: "Anthropic", badges: [], isExpanded: false, onToggle: {}, details: { EmptyView() })
                AIProviderDisclosureRow(providerID: "ollama", name: "Ollama", badges: [.local], isExpanded: false, onToggle: {}, details: { EmptyView() })
            }
        }
    }

    private var prompts: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: Space.xl) {
                AISectionHeading("Prompts", subtitle: "The instructions AI Enhancement follows. Pick one for each mode.")
                VStack(alignment: .leading, spacing: Space.md) {
                    AIPromptModeHeader(mode: .dictate)
                    AIPromptRow(
                        title: "Default Prompt",
                        preview: "Fix punctuation and capitalization, remove filler words, keep the speaker's wording.",
                        isSelected: false,
                        onSelect: {},
                        menuItems: { Button("Edit Prompt…") {} }
                    )
                    AIPromptRow(
                        title: "Email",
                        preview: "Turn the dictation into a short, friendly email with a greeting and sign-off.",
                        isSelected: true,
                        onSelect: {},
                        menuItems: { Button("Edit Prompt…") {} }
                    )
                    Button {} label: { Label("New Dictate Prompt", systemImage: "plus") }
                        .buttonStyle(.sayIt(.quiet, size: .small))
                }
                Rectangle().fill(self.theme.palette.separator).frame(height: 1)
                VStack(alignment: .leading, spacing: Space.md) {
                    AIPromptModeHeader(mode: .edit)
                    AIEditModeModelSection(
                        hasVerifiedProviders: true,
                        isLinked: self.$linked,
                        linkedDescription: "OpenAI · gpt-4.1-mini",
                        pickers: { EmptyView() }
                    )
                    AIPromptRow(
                        title: "Default Prompt",
                        preview: "Apply the instruction to the selected text and return only the result.",
                        isSelected: true,
                        onSelect: {},
                        menuItems: { Button("Edit Prompt…") {} }
                    )
                }
            }
        }
    }
}

// MARK: - Provider States

private struct ProviderStatesSpecimen: View {
    @Environment(\.theme) private var theme
    @State private var reasoningEnabled = true
    @State private var parameterName = "reasoning_effort"
    @State private var parameterValue = "low"

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            AIProviderDisclosureRow(
                providerID: "groq",
                name: "Groq",
                badges: [.failed],
                isExpanded: true,
                onToggle: {},
                details: {
                    AIProviderForm(
                        name: .constant(""),
                        baseURL: .constant("https://api.groq.com/openai/v1"),
                        apiKey: .constant("gsk_••••••••"),
                        state: AIProviderFormState(
                            isCustom: false,
                            isLocal: false,
                            websiteLabel: "Get API Key",
                            websiteURL: URL(string: "https://console.groq.com/keys"),
                            missingRequirement: nil,
                            canVerify: true,
                            isVerifying: false,
                            errorMessage: "Groq didn't accept the API key. Check that it's correct and hasn't expired."
                        ),
                        onVerify: {},
                        modelControl: {
                            SearchableModelPicker(
                                models: ["llama-3.3-70b"],
                                selectedModel: .constant("llama-3.3-70b"),
                                onRefresh: {},
                                controlWidth: AIEnhancementLayout.modelPickerWidth
                            )
                        },
                        extra: {
                            AIReasoningPanel(
                                modelName: "llama-3.3-70b",
                                isEnabled: self.$reasoningEnabled,
                                parameterName: self.$parameterName,
                                parameterValue: self.$parameterValue,
                                onSave: {},
                                onCancel: {}
                            )
                        }
                    )
                }
            )
            AIProviderDisclosureRow(
                providerID: "apple-intelligence-disabled",
                name: "Apple Intelligence",
                badges: [.unavailable],
                isExpanded: true,
                onToggle: {},
                details: {
                    AIInlineNotice(
                        kind: .info,
                        text: "Apple Intelligence isn't available on this Mac. Turn it on in System Settings › Apple Intelligence & Siri, then come back to this page."
                    )
                }
            )
            AIProviderDisclosureRow(providerID: "custom:1", name: "Team Gateway", badges: [.verifying], isExpanded: false, onToggle: {}, details: { EmptyView() })
            AIAddCustomProviderButton {}
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(self.theme.palette.contentBackground)
    }
}

// MARK: - Prompt Editor

private struct PromptEditorSpecimen: View {
    @State private var mode: SettingsStore.PromptMode = .dictate
    @State private var name = "Email"
    @State private var text = "Turn the dictation into a short, friendly email with a greeting and sign-off."
    @State private var isTesting = true

    var body: some View {
        AIPromptEditorForm(
            kind: .edit,
            mode: self.$mode,
            name: self.$name,
            promptText: self.$text,
            isTesting: self.$isTesting,
            testState: AIPromptTestState(
                canTest: true,
                shortcut: "Right ⌥",
                isProcessing: false,
                error: "",
                transcript: "hey sam um can we move the review to thursday afternoon thanks",
                output: "Hi Sam,\n\nCould we move the review to Thursday afternoon?\n\nThanks!"
            ),
            contextTemplate: "",
            editorSessionID: UUID(),
            canSave: true,
            onCancel: {},
            onSave: {}
        )
    }
}

// MARK: - Pickers

private struct PickerSpecimen: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.md) {
                SearchableModelPicker(models: ["gpt-4.1"], selectedModel: .constant("gpt-4.1"), onRefresh: {}, controlWidth: 200)
                SearchableModelPicker(models: [], selectedModel: .constant(""), onRefresh: {}, refreshEnabled: false, selectionEnabled: false, controlWidth: 200)
                SearchableProviderPicker(builtInProviders: [("openai", "OpenAI")], savedProviders: [], selectedProviderID: .constant("openai"))
            }
            VStack(spacing: 0) {
                PickerSearchField(placeholder: "Search models", text: .constant("gpt")) {}
                Divider()
                PickerOptionRow(title: "gpt-4.1", isSelected: true, isMonospaced: true) {}
                PickerOptionRow(title: "gpt-4.1-mini", isSelected: false, isMonospaced: true) {}
            }
            .frame(width: PickerLayout.popoverWidth)
            .background(RoundedRectangle(cornerRadius: Radius.md).fill(self.theme.palette.surfaceRaised))
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(self.theme.palette.contentBackground)
    }
}
