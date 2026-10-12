//
//  AISettingsView+AdvancedSettings.swift
//  SayIt
//
//  AI Enhancement page: prompts per mode, Edit Mode model, and the prompt editor sheet.
//

import AppKit
import SwiftUI

extension AIEnhancementSettingsView {
    // MARK: - Prompts Card

    var promptsCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: Space.xl) {
                AISectionHeading(
                    "Prompts",
                    subtitle: "The instructions AI Enhancement follows. Pick one for each mode."
                )

                ForEach(Array(SettingsStore.PromptMode.visiblePromptModes.enumerated()), id: \.element) { index, mode in
                    if index > 0 {
                        Rectangle()
                            .fill(self.theme.palette.separator)
                            .frame(height: 1)
                    }
                    self.promptModeSection(mode: mode)
                }
            }
        }
        .sheet(item: self.$viewModel.promptEditorMode) { mode in
            self.promptEditorSheet(mode: mode)
                .sayItTheme()
        }
    }

    private func promptModeSection(mode: SettingsStore.PromptMode) -> some View {
        let normalized = mode.normalized
        let customProfiles = self.viewModel.dictationPromptProfiles.filter { $0.mode.normalized == normalized }
        let selectedID = self.viewModel.selectedPromptID(for: normalized)

        return VStack(alignment: .leading, spacing: Space.md) {
            AIPromptModeHeader(mode: normalized)

            if normalized == .edit {
                self.editModeModelSection
            }

            VStack(spacing: Space.sm) {
                AIPromptRow(
                    title: "Default Prompt",
                    preview: self.viewModel.promptPreview(self.viewModel.defaultPromptBodyPreview(for: normalized)),
                    isSelected: selectedID == nil,
                    onSelect: { withMotion { self.viewModel.setSelectedPromptID(nil, for: normalized) } },
                    menuItems: {
                        Button("Edit Prompt…") { self.viewModel.openDefaultPromptViewer(for: normalized) }
                        if self.viewModel.hasDefaultPromptOverride(for: normalized) {
                            Divider()
                            Button("Reset to SayIt’s Default…", role: .destructive) {
                                self.pendingDefaultPromptReset = normalized
                            }
                        }
                    }
                )

                ForEach(customProfiles) { profile in
                    let promptBody = SettingsStore.stripBasePrompt(for: profile.mode, from: profile.prompt)
                    AIPromptRow(
                        title: profile.name.isEmpty ? "Untitled Prompt" : profile.name,
                        preview: promptBody.isEmpty
                            ? "No instructions yet — the default prompt applies."
                            : self.viewModel.promptPreview(promptBody),
                        isSelected: selectedID == profile.id,
                        onSelect: { withMotion { self.viewModel.setSelectedPromptID(profile.id, for: profile.mode) } },
                        menuItems: {
                            Button("Edit Prompt…") { self.viewModel.openEditor(for: profile) }
                            Divider()
                            Button("Delete Prompt…", role: .destructive) {
                                self.viewModel.requestDeletePrompt(profile)
                            }
                        }
                    )
                }
            }

            Button {
                self.viewModel.openNewPromptEditor(prefillMode: normalized)
            } label: {
                Label("New \(AIPromptModeHeader.shortName(for: normalized)) Prompt", systemImage: "plus")
            }
            .buttonStyle(.sayIt(.quiet, size: .small))
        }
    }

    // MARK: - Edit Mode Model

    private var editModeModelSection: some View {
        let verified = self.editModeVerifiedProviders
        let providerID = self.activeEditModeProviderID
        let models = self.viewModel.models(for: providerID)

        return AIEditModeModelSection(
            hasVerifiedProviders: !verified.isEmpty,
            isLinked: self.editModeLinkedToGlobalBinding,
            linkedDescription: self.linkedEditModeDescription,
            pickers: {
                HStack(spacing: Space.sm) {
                    Picker("Edit Mode Provider", selection: self.editModeProviderBinding) {
                        ForEach(verified) { provider in
                            Text(self.displayName(for: provider)).tag(provider.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: AIEnhancementLayout.providerPickerWidth)

                    SearchableModelPicker(
                        models: models,
                        selectedModel: self.editModeModelBinding(for: providerID),
                        onRefresh: { await self.viewModel.fetchModels(for: providerID) },
                        isRefreshing: self.viewModel.refreshingProviderID == providerID,
                        refreshEnabled: self.requirements(for: providerID).canFetchModels,
                        selectionEnabled: !models.isEmpty,
                        controlWidth: AIEnhancementLayout.modelPickerWidth
                    )
                }
                .onAppear { self.normalizeEditModeProviderSelection() }
            }
        )
        .onAppear { self.ensureDefaultEditModeSyncState() }
        .onChange(of: self.settings.rewriteModeLinkedToGlobal) { _, linked in
            if linked {
                self.syncEditModeToGlobalSelection()
            } else {
                self.normalizeEditModeProviderSelection()
            }
        }
    }

    private var linkedEditModeDescription: String {
        let providerID = self.activeEditModeProviderID
        let name = self.displayName(forProviderID: providerID)
        let model = self.editModeModelBinding(for: providerID).wrappedValue
        if providerID == Self.appleIntelligenceID || model.isEmpty { return name }
        return "\(name) · \(model)"
    }

    private var editModeVerifiedProviders: [ProviderItem] {
        self.viewModel.cachedVerifiedProviderItems.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var editModeSelectedProviderID: String {
        let current = self.settings.rewriteModeSelectedProviderID
        if self.editModeVerifiedProviders.contains(where: { $0.id == current }) {
            return current
        }
        return self.editModeVerifiedProviders.first?.id ?? current
    }

    private var activeEditModeProviderID: String {
        if self.settings.rewriteModeLinkedToGlobal {
            let global = self.viewModel.selectedProviderID
            if self.editModeVerifiedProviders.contains(where: { $0.id == global }) {
                return global
            }
        }
        return self.editModeSelectedProviderID
    }

    private var editModeLinkedToGlobalBinding: Binding<Bool> {
        Binding(
            get: { self.settings.rewriteModeLinkedToGlobal },
            set: { self.settings.rewriteModeLinkedToGlobal = $0 }
        )
    }

    private var editModeProviderBinding: Binding<String> {
        Binding(
            get: { self.activeEditModeProviderID },
            set: { newProviderID in
                guard !self.settings.rewriteModeLinkedToGlobal else { return }
                self.settings.rewriteModeSelectedProviderID = newProviderID
                let models = self.viewModel.models(for: newProviderID)
                let current = self.settings.rewriteModeSelectedModel ?? ""
                if !models.contains(current) {
                    self.settings.rewriteModeSelectedModel = models.first
                }
            }
        )
    }

    private func editModeModelBinding(for providerID: String) -> Binding<String> {
        Binding(
            get: {
                if self.settings.rewriteModeLinkedToGlobal {
                    let key = self.viewModel.providerKey(for: providerID)
                    return self.settings.selectedModelByProvider[key]
                        ?? self.settings.selectedModel
                        ?? self.viewModel.models(for: providerID).first
                        ?? ""
                }
                return self.settings.rewriteModeSelectedModel ?? self.viewModel.models(for: providerID).first ?? ""
            },
            set: { newModel in
                guard !self.settings.rewriteModeLinkedToGlobal else { return }
                self.settings.rewriteModeSelectedModel = newModel
            }
        )
    }

    private func normalizeEditModeProviderSelection() {
        guard let first = self.editModeVerifiedProviders.first else { return }
        let current = self.settings.rewriteModeSelectedProviderID
        if !self.editModeVerifiedProviders.contains(where: { $0.id == current }) {
            self.settings.rewriteModeSelectedProviderID = first.id
        }

        let providerID = self.settings.rewriteModeSelectedProviderID
        let models = self.viewModel.models(for: providerID)
        let currentModel = self.settings.rewriteModeSelectedModel ?? ""
        if !models.contains(currentModel) {
            self.settings.rewriteModeSelectedModel = models.first
        }
    }

    private func syncEditModeToGlobalSelection() {
        let global = self.viewModel.selectedProviderID
        let providerID: String
        if self.editModeVerifiedProviders.contains(where: { $0.id == global }) {
            providerID = global
        } else if let fallback = self.editModeVerifiedProviders.first?.id {
            providerID = fallback
        } else {
            providerID = global
        }
        self.settings.rewriteModeSelectedProviderID = providerID

        let key = self.viewModel.providerKey(for: providerID)
        let model = self.settings.selectedModelByProvider[key]
            ?? self.settings.selectedModel
            ?? self.viewModel.models(for: providerID).first
        self.settings.rewriteModeSelectedModel = model
    }

    private func ensureDefaultEditModeSyncState() {
        // If no persisted value exists yet, default Sync to ON.
        if UserDefaults.standard.object(forKey: "RewriteModeLinkedToGlobal") == nil {
            self.settings.rewriteModeLinkedToGlobal = true
            self.syncEditModeToGlobalSelection()
        }
    }

    // MARK: - Prompt Editor

    func promptEditorSheet(mode: PromptEditorMode) -> some View {
        let kind: AIPromptEditorKind = {
            switch mode {
            case let .defaultPrompt(promptMode): return .builtIn(promptMode.normalized)
            case .newPrompt: return .new
            case .edit: return .edit
            }
        }()
        let canTest = self.viewModel.isAIPostProcessingConfiguredForDictation()

        return AIPromptEditorForm(
            kind: kind,
            mode: self.$viewModel.draftPromptMode,
            name: self.$viewModel.draftPromptName,
            promptText: self.$viewModel.draftPromptText,
            isTesting: Binding(
                get: { self.promptTest.isActive },
                set: { enabled in
                    if enabled {
                        let combined = self.viewModel.combinedDraftPrompt(
                            self.viewModel.draftPromptText,
                            mode: self.viewModel.draftPromptMode
                        )
                        self.promptTest.activate(draftPromptText: combined)
                    } else {
                        self.promptTest.deactivate()
                    }
                }
            ),
            testState: AIPromptTestState(
                canTest: canTest,
                shortcut: self.settings.hotkeyShortcut.displayString,
                isProcessing: self.promptTest.isProcessing,
                error: self.promptTest.lastError,
                transcript: self.promptTest.lastTranscriptionText,
                output: self.promptTest.lastOutputText
            ),
            contextTemplate: SettingsStore.contextTemplateText(),
            editorSessionID: self.viewModel.promptEditorSessionID,
            canSave: mode.isDefault || !self.viewModel.draftPromptName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onCancel: { self.viewModel.closePromptEditor() },
            onSave: { self.viewModel.savePromptEditor(mode: mode) }
        )
        .onChange(of: self.viewModel.draftPromptText) { _, newValue in
            guard self.viewModel.draftPromptMode == .dictate else { return }
            let combined = self.viewModel.combinedDraftPrompt(newValue, mode: self.viewModel.draftPromptMode)
            self.promptTest.updateDraftPromptText(combined)
        }
        .onChange(of: self.viewModel.draftPromptMode) { _, newMode in
            if newMode.normalized != .dictate { self.promptTest.deactivate() }
        }
        .onDisappear {
            self.promptTest.deactivate()
        }
        .onChange(of: self.viewModel.enableAIProcessing) { _, _ in
            self.autoDisablePromptTestIfNeeded()
        }
        .onChange(of: self.viewModel.selectedProviderID) { _, _ in
            self.autoDisablePromptTestIfNeeded()
        }
        .onChange(of: self.viewModel.providerAPIKeys) { _, _ in
            self.autoDisablePromptTestIfNeeded()
        }
        .onChange(of: self.viewModel.savedProviders) { _, _ in
            self.autoDisablePromptTestIfNeeded()
        }
    }

    private func autoDisablePromptTestIfNeeded() {
        guard self.promptTest.isActive else { return }
        if !self.viewModel.isAIPostProcessingConfiguredForDictation() {
            self.promptTest.deactivate()
        }
    }
}
