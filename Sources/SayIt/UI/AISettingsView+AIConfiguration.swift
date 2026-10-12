//
//  AISettingsView+AIConfiguration.swift
//  SayIt
//
//  AI Enhancement page: overview and provider configuration. Presentational pieces live
//  in UI/AISettings/AIEnhancementComponents.swift and AIEnhancementForms.swift.
//

import AppKit
import SwiftUI

extension AIEnhancementSettingsView {
    typealias ProviderItem = AIEnhancementSettingsViewModel.ProviderItemData

    static let appleIntelligenceID = "apple-intelligence"
    static let appleIntelligenceUnavailableID = "apple-intelligence-disabled"

    // MARK: - Page

    var enhancementPage: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            AIEnhancementPageHeader()

            AIEnhancementOverviewCard(
                isEnabled: self.$viewModel.enableAIProcessing,
                summary: self.enhancementSummary
            )

            if self.viewModel.enableAIProcessing {
                self.providersCard
                    .motionTransition()
                self.promptsCard
                    .motionTransition()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .motion(Motion.state, value: self.viewModel.enableAIProcessing)
    }

    /// What AI Enhancement will do on the next dictation. Mirrors
    /// `DictationAIPostProcessingGate` without touching the Keychain on every render.
    var enhancementSummary: AIEnhancementSummary {
        guard self.viewModel.enableAIProcessing else { return .off }

        let providerID = self.viewModel.selectedProviderID
        let name = self.displayName(forProviderID: providerID)
        let isVerified = self.viewModel.connectionStatus(for: providerID) == .success

        if providerID == Self.appleIntelligenceID {
            guard self.viewModel.appleIntelligenceAvailable else { return .incomplete(provider: name) }
            return isVerified ? .ready(provider: name, model: "") : .unverified(provider: name, model: "")
        }

        let requirements = self.requirements(for: providerID)
        guard requirements.isConfigured else { return .incomplete(provider: name) }
        let model = requirements.selectedModel.isEmpty
            ? (ModelRepository.shared.defaultModels(for: providerID).first ?? "")
            : requirements.selectedModel
        return isVerified ? .ready(provider: name, model: model) : .unverified(provider: name, model: model)
    }

    // MARK: - Providers Card

    var providersCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: Space.xl) {
                AISectionHeading("Provider", subtitle: "Where AI Enhancement sends your transcript.") {
                    Button {
                        withMotion { self.viewModel.showHelp.toggle() }
                    } label: {
                        Label(self.viewModel.showHelp ? "Hide Guide" : "Setup Guide", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.sayIt(.quiet, size: .small))
                }

                if self.viewModel.showHelp {
                    AISetupGuide()
                        .motionTransition(edge: .top)
                }

                self.verifiedProvidersSection
                self.otherProvidersSection
            }
        }
    }

    private var verifiedProvidersSection: some View {
        let verified = self.viewModel.cachedVerifiedProviderItems
        return VStack(alignment: .leading, spacing: Space.sm) {
            AIGroupLabel(title: "Ready to Use", count: verified.count)
            if verified.isEmpty {
                AIInlineNotice(
                    kind: .info,
                    text: "No provider is verified yet. Open one below, add its API key if it needs one, choose a model, then verify the connection."
                )
            } else {
                ForEach(verified) { item in
                    self.verifiedProviderRow(item)
                }
            }
        }
    }

    private var otherProvidersSection: some View {
        let items = self.viewModel.cachedUnverifiedProviderItems
        let query = self.providerSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty
            ? items
            : items.filter {
                self.displayName(for: $0).localizedCaseInsensitiveContains(query) ||
                    $0.id.localizedCaseInsensitiveContains(query)
            }
        let hasVerified = !self.viewModel.cachedVerifiedProviderItems.isEmpty
        let containsExpanded = items.contains { $0.id == self.expandedProviderID }
        let isOpen = !hasVerified || containsExpanded || self.showsAllProviders

        return VStack(alignment: .leading, spacing: Space.sm) {
            if hasVerified {
                Button {
                    withMotion {
                        if isOpen {
                            self.showsAllProviders = false
                            if containsExpanded { self.expandedProviderID = nil }
                        } else {
                            self.showsAllProviders = true
                        }
                    }
                } label: {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "chevron.right")
                            .font(AppFont.iconSmall)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                            .foregroundStyle(self.theme.palette.tertiaryText)
                        AIGroupLabel(title: "Add Another Provider", count: items.count)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add Another Provider")
                .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
            } else {
                AIGroupLabel(title: "All Providers", count: items.count)
            }

            if isOpen {
                VStack(alignment: .leading, spacing: Space.sm) {
                    AISearchField(
                        label: "Search Providers",
                        placeholder: "Search providers",
                        text: self.$providerSearchText,
                        onSubmit: {
                            if let first = filtered.first { self.toggleProviderExpansion(first.id) }
                        }
                    )

                    ForEach(filtered) { item in
                        self.providerRow(item)
                    }

                    if filtered.isEmpty, !query.isEmpty {
                        Text("No providers match “\(query)”.")
                            .font(AppFont.caption)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .padding(.vertical, Space.sm)
                    }

                    AIAddCustomProviderButton { self.startCustomProvider() }
                }
                .motionTransition(edge: .top)
            }
        }
        .motion(Motion.state, value: isOpen)
    }

    // MARK: - Verified Rows

    private func verifiedProviderRow(_ item: ProviderItem) -> some View {
        let isSelected = item.id == self.viewModel.selectedProviderID
        let isEditing = self.viewModel.showingEditProvider && isSelected
        let showsReasoning = self.viewModel.showingReasoningConfig && isSelected
        let isApple = item.id == Self.appleIntelligenceID

        return AIVerifiedProviderRow(
            providerID: item.id,
            name: self.displayName(for: item),
            isSelected: isSelected,
            isExpanded: isEditing || showsReasoning,
            onSelect: {
                self.activateProvider(item.id)
                self.expandedProviderID = nil
            },
            trailing: {
                if isApple {
                    Text("System model")
                        .font(AppFont.caption)
                        .foregroundStyle(self.theme.palette.secondaryText)
                } else {
                    self.modelPicker(for: item.id)
                    self.reasoningButton(for: item.id)
                }
                Button(isEditing ? "Done" : "Edit") {
                    self.toggleEditing(item.id, isEditing: isEditing)
                }
                .buttonStyle(.sayIt(.quiet, size: .small))
                .accessibilityLabel(isEditing ? "Done Editing \(self.displayName(for: item))" : "Edit \(self.displayName(for: item))")
            },
            expanded: {
                if isEditing {
                    self.editProviderSection
                } else if showsReasoning {
                    self.reasoningPanel
                }
            }
        )
    }

    private func toggleEditing(_ providerID: String, isEditing: Bool) {
        self.activateProvider(providerID)
        withMotion {
            if isEditing {
                self.viewModel.showingEditProvider = false
                self.viewModel.editProviderName = ""
                self.viewModel.editProviderBaseURL = ""
                self.viewModel.setEditingAPIKey(false, for: providerID)
            } else {
                self.viewModel.showingReasoningConfig = false
                self.viewModel.startEditingProvider()
                self.viewModel.setEditingAPIKey(true, for: providerID)
            }
        }
    }

    var editProviderSection: some View {
        let providerID = self.viewModel.selectedProviderID
        let providerKey = self.viewModel.providerKey(for: providerID)
        let isBuiltIn = ModelRepository.shared.isBuiltIn(providerID)
        let isApple = providerID == Self.appleIntelligenceID
        let website = self.websiteLink(for: providerID)
        let name = self.viewModel.editProviderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = self.viewModel.editProviderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSave = isBuiltIn ? !isApple : (!name.isEmpty && !baseURL.isEmpty)
        let deleteAction: (() -> Void)? = isBuiltIn ? nil : { self.pendingProviderDeletionID = providerID }

        return AIEditProviderForm(
            name: self.$viewModel.editProviderName,
            baseURL: self.$viewModel.editProviderBaseURL,
            apiKey: Binding(
                get: { self.viewModel.providerAPIKeys[providerKey] ?? "" },
                set: { self.viewModel.providerAPIKeys[providerKey] = $0 }
            ),
            isBuiltIn: isBuiltIn,
            isAppleIntelligence: isApple,
            isVerified: self.viewModel.connectionStatus(for: providerID) == .success,
            websiteLabel: website?.label,
            websiteURL: website?.url,
            canSave: canSave,
            onSave: {
                self.viewModel.saveProviderAPIKeys()
                self.viewModel.saveEditedProvider()
            },
            onCancel: {
                withMotion {
                    self.viewModel.showingEditProvider = false
                    self.viewModel.editProviderName = ""
                    self.viewModel.editProviderBaseURL = ""
                }
            },
            onResetVerification: {
                withMotion {
                    self.viewModel.resetVerification(for: providerID)
                    self.viewModel.showingEditProvider = false
                }
            },
            onDelete: deleteAction
        )
    }

    // MARK: - Unverified Rows

    private func providerRow(_ item: ProviderItem) -> some View {
        AIProviderDisclosureRow(
            providerID: item.id,
            name: self.displayName(for: item),
            badges: self.badges(for: item),
            isExpanded: self.expandedProviderID == item.id,
            onToggle: { self.toggleProviderExpansion(item.id) },
            details: { self.providerDetails(for: item) }
        )
        .id(item.id)
    }

    @ViewBuilder
    private func providerDetails(for item: ProviderItem) -> some View {
        switch item.id {
        case Self.appleIntelligenceUnavailableID:
            AIInlineNotice(
                kind: .info,
                text: "Apple Intelligence isn't available on this Mac. Turn it on in System Settings › Apple Intelligence & Siri, then come back to this page."
            )
        case Self.appleIntelligenceID:
            VStack(alignment: .leading, spacing: Space.md) {
                AIInlineNotice(kind: .success, text: "Runs entirely on this Mac. No API key or base URL needed, and your words never leave the device.")
                Button("Use Apple Intelligence") {
                    self.activateProvider(item.id)
                    self.viewModel.verifyAppleIntelligence()
                }
                .buttonStyle(.sayItPrimary)
            }
        default:
            self.providerForm(for: item)
        }
    }

    private func providerForm(for item: ProviderItem) -> some View {
        let providerKey = self.viewModel.providerKey(for: item.id)
        let requirements = self.requirements(for: item.id)
        let isSelected = self.viewModel.selectedProviderID == item.id
        let isVerifying = isSelected && self.viewModel.isTestingConnection
        let failed = self.viewModel.connectionStatus(for: item.id) == .failed
        let website = self.websiteLink(for: item.id)
        let deleteAction: (() -> Void)? = requirements.isCustom ? { self.pendingProviderDeletionID = item.id } : nil

        var errorMessage: String?
        if isSelected, failed, !self.viewModel.connectionErrorMessage.isEmpty {
            errorMessage = self.viewModel.connectionErrorMessage
        } else if isSelected, let fetchError = self.viewModel.fetchModelsError, !fetchError.isEmpty {
            errorMessage = fetchError
        }

        let state = AIProviderFormState(
            isCustom: requirements.isCustom,
            isLocal: requirements.isLocal,
            websiteLabel: website?.label,
            websiteURL: website?.url,
            missingRequirement: requirements.missing,
            canVerify: requirements.missing == nil,
            isVerifying: isVerifying,
            errorMessage: errorMessage
        )

        return AIProviderForm(
            name: Binding(
                get: { self.viewModel.savedProviders.first(where: { $0.id == item.id })?.name ?? "" },
                set: { self.viewModel.updateCustomProviderName($0, for: item.id) }
            ),
            baseURL: Binding(
                get: {
                    self.viewModel.savedProviders.first(where: { $0.id == item.id })?.baseURL
                        ?? self.viewModel.resolvedBaseURL(for: item.id)
                },
                set: { self.viewModel.updateProviderBaseURL($0, for: item.id) }
            ),
            apiKey: Binding(
                get: { self.viewModel.providerAPIKeys[providerKey] ?? "" },
                set: { self.viewModel.providerAPIKeys[providerKey] = $0 }
            ),
            state: state,
            onVerify: {
                self.activateProvider(item.id)
                self.viewModel.saveProviderAPIKeys()
                Task { await self.viewModel.testAPIConnection() }
            },
            onDelete: deleteAction,
            modelControl: {
                HStack(spacing: Space.sm) {
                    self.modelPicker(for: item.id, savesKeysOnRefresh: true)
                    self.reasoningButton(for: item.id)
                }
            },
            extra: {
                if self.viewModel.showingReasoningConfig, isSelected {
                    self.reasoningPanel
                        .motionTransition(edge: .top)
                }
            }
        )
    }

    // MARK: - Provider Requirements

    struct ProviderRequirements {
        var isCustom: Bool
        var isLocal: Bool
        var selectedModel: String
        /// The first missing piece, phrased as an instruction; nil when ready to verify.
        var missing: String?
        var canFetchModels: Bool
        /// Matches `SettingsStore.isAIConfigured`: dictation will be enhanced.
        var isConfigured: Bool
    }

    func requirements(for providerID: String) -> ProviderRequirements {
        let providerKey = self.viewModel.providerKey(for: providerID)
        let isCustom = !ModelRepository.shared.isBuiltIn(providerID)
        let baseURL = self.viewModel.resolvedBaseURL(for: providerID).trimmingCharacters(in: .whitespacesAndNewlines)
        let isLocal = self.viewModel.isLocalEndpoint(baseURL)
        let apiKey = (self.viewModel.providerAPIKeys[providerKey] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let models = self.viewModel.models(for: providerID)
        let selectedModel = (self.viewModel.selectedModelByProvider[providerKey] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let customName = self.viewModel.savedProviders.first { $0.id == providerID }?.name ?? ""
        let hasName = !isCustom || !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasCredentials = !baseURL.isEmpty && (isLocal || !apiKey.isEmpty)

        let missing: String?
        if !hasName {
            missing = "Name this provider."
        } else if baseURL.isEmpty {
            missing = "Enter the base URL."
        } else if !isLocal, apiKey.isEmpty {
            missing = "Enter an API key."
        } else if models.isEmpty {
            missing = "Refresh the model list."
        } else if selectedModel.isEmpty {
            missing = "Choose a model."
        } else {
            missing = nil
        }

        let hasDefaultModel = !ModelRepository.shared.defaultModels(for: providerID).isEmpty
        return ProviderRequirements(
            isCustom: isCustom,
            isLocal: isLocal,
            selectedModel: selectedModel,
            missing: missing,
            canFetchModels: hasName && hasCredentials,
            isConfigured: hasCredentials && (!selectedModel.isEmpty || hasDefaultModel)
        )
    }

    // MARK: - Shared Controls

    func modelPicker(for providerID: String, savesKeysOnRefresh: Bool = false) -> some View {
        let models = self.viewModel.models(for: providerID)
        return SearchableModelPicker(
            models: models,
            selectedModel: self.modelBinding(for: providerID),
            onRefresh: {
                self.activateProvider(providerID)
                if savesKeysOnRefresh { self.viewModel.saveProviderAPIKeys() }
                await self.viewModel.fetchModels(for: providerID)
            },
            isRefreshing: self.viewModel.refreshingProviderID == providerID,
            refreshEnabled: self.requirements(for: providerID).canFetchModels,
            selectionEnabled: !models.isEmpty,
            controlWidth: AIEnhancementLayout.modelPickerWidth
        )
    }

    func reasoningButton(for providerID: String) -> some View {
        let isConfigured = self.viewModel.isReasoningEnabled(for: providerID)
        let isOpen = self.viewModel.showingReasoningConfig && self.viewModel.selectedProviderID == providerID
        return IconButton(
            isConfigured ? "Reasoning Settings (On)" : "Reasoning Settings",
            systemName: isConfigured ? "brain.fill" : "brain",
            role: isConfigured || isOpen ? .quiet : .secondary
        ) {
            if isOpen {
                withMotion { self.viewModel.showingReasoningConfig = false }
            } else {
                self.activateProvider(providerID)
                withMotion {
                    self.viewModel.showingEditProvider = false
                    self.viewModel.openReasoningConfig()
                }
            }
        }
    }

    var reasoningPanel: some View {
        AIReasoningPanel(
            modelName: self.viewModel.selectedModel,
            isEnabled: self.$viewModel.editingReasoningEnabled,
            parameterName: self.$viewModel.editingReasoningParamName,
            parameterValue: self.$viewModel.editingReasoningParamValue,
            onSave: { withMotion { self.viewModel.saveReasoningConfig() } },
            onCancel: { withMotion { self.viewModel.showingReasoningConfig = false } }
        )
    }

    // MARK: - Helpers

    func displayName(for item: ProviderItem) -> String {
        item.id == Self.appleIntelligenceUnavailableID ? "Apple Intelligence" : item.name
    }

    func displayName(forProviderID providerID: String) -> String {
        if let item = self.viewModel.cachedProviderItems.first(where: { $0.id == providerID }) {
            return self.displayName(for: item)
        }
        return self.viewModel.providerDisplayName(for: providerID)
    }

    private func badges(for item: ProviderItem) -> [AIStatusKind] {
        switch item.id {
        case Self.appleIntelligenceUnavailableID:
            return [.unavailable]
        case Self.appleIntelligenceID:
            return [.onDevice]
        default:
            switch self.viewModel.connectionStatus(for: item.id) {
            case .failed: return [.failed]
            case .testing: return [.verifying]
            case .success: return [.verified]
            case .unknown: return self.requirements(for: item.id).isLocal ? [.local] : []
            }
        }
    }

    private func websiteLink(for providerID: String) -> (label: String, url: URL)? {
        guard let info = ModelRepository.shared.providerWebsiteURL(for: providerID),
              let url = URL(string: info.url)
        else { return nil }
        return (info.label, url)
    }

    private func toggleProviderExpansion(_ providerID: String) {
        withMotion {
            if self.expandedProviderID == providerID {
                self.expandedProviderID = nil
                self.viewModel.showingEditProvider = false
                self.viewModel.showingReasoningConfig = false
                self.viewModel.editProviderName = ""
                self.viewModel.editProviderBaseURL = ""
                self.viewModel.setEditingAPIKey(false, for: providerID)
            } else {
                self.expandedProviderID = providerID
                self.viewModel.showingReasoningConfig = false
                // The unavailable Apple Intelligence row only explains why; it must never
                // become the active provider.
                if providerID != Self.appleIntelligenceUnavailableID {
                    self.viewModel.selectProvider(providerID)
                }
            }
        }
    }

    func activateProvider(_ providerID: String) {
        guard providerID != Self.appleIntelligenceUnavailableID else { return }
        self.viewModel.selectedProviderID = providerID
        self.viewModel.handleProviderChange(providerID)
        self.viewModel.connectionStatus = self.viewModel.connectionStatus(for: providerID)
    }

    private func startCustomProvider() {
        let name = self.uniqueCustomProviderName()
        if let providerID = self.viewModel.createDraftProvider(named: name) {
            withMotion {
                self.showsAllProviders = true
                self.expandedProviderID = providerID
            }
        }
    }

    private func uniqueCustomProviderName() -> String {
        let base = "Custom Provider"
        let existing = Set(self.viewModel.savedProviders.map { $0.name.lowercased() })
        if !existing.contains(base.lowercased()) { return base }
        var index = 2
        while existing.contains("\(base) \(index)".lowercased()) {
            index += 1
        }
        return "\(base) \(index)"
    }

    private func modelBinding(for providerID: String) -> Binding<String> {
        Binding(
            get: {
                let key = self.viewModel.providerKey(for: providerID)
                return self.viewModel.selectedModelByProvider[key] ?? ""
            },
            set: { newValue in
                let key = self.viewModel.providerKey(for: providerID)
                self.viewModel.selectedModelByProvider[key] = newValue
                self.viewModel.settings.selectedModelByProvider = self.viewModel.selectedModelByProvider
                if providerID == self.viewModel.selectedProviderID {
                    self.viewModel.selectedModel = newValue
                }
            }
        )
    }
}
