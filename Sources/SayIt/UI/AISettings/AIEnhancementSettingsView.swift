import SwiftUI

struct AIEnhancementSettingsView: View {
    @ObservedObject var viewModel: AIEnhancementSettingsViewModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var promptTest: DictationPromptTestCoordinator
    let theme: AppTheme
    @State var expandedProviderID: String? = nil
    @State var providerSearchText: String = ""
    /// Whether "Add Another Provider" is open while at least one provider is verified.
    @State var showsAllProviders: Bool = false
    /// Provider waiting for the delete confirmation.
    @State var pendingProviderDeletionID: String? = nil
    /// Mode whose default-prompt override is waiting for the reset confirmation.
    @State var pendingDefaultPromptReset: SettingsStore.PromptMode? = nil

    var body: some View {
        self.enhancementPage
            .onAppear {
                self.viewModel.onAppear()
            }
            .onChange(of: self.viewModel.connectionStatus) { oldValue, newValue in
                if oldValue == .success && newValue != .success {
                    self.expandedProviderID = self.viewModel.selectedProviderID
                }
            }
            .onChange(of: self.viewModel.showKeychainPermissionAlert) { _, isPresented in
                guard isPresented else { return }
                self.viewModel.presentKeychainAccessAlert(message: self.viewModel.keychainPermissionMessage)
                self.viewModel.showKeychainPermissionAlert = false
            }
            .confirmationDialog(
                self.deletePromptTitle,
                isPresented: self.$viewModel.showingDeletePromptConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Prompt", role: .destructive) {
                    withMotion { self.viewModel.deletePendingPrompt() }
                }
                Button("Cancel", role: .cancel) {
                    self.viewModel.clearPendingDeletePrompt()
                }
            } message: {
                Text("Its instructions will be removed. This can't be undone.")
            }
            .confirmationDialog(
                self.deleteProviderTitle,
                isPresented: self.isConfirmingProviderDeletion,
                titleVisibility: .visible
            ) {
                Button("Delete Provider", role: .destructive) {
                    self.deletePendingProvider()
                }
                Button("Cancel", role: .cancel) {
                    self.pendingProviderDeletionID = nil
                }
            } message: {
                Text("Its base URL, API key and model list will be removed from SayIt.")
            }
            .confirmationDialog(
                self.resetPromptTitle,
                isPresented: self.isConfirmingPromptReset,
                titleVisibility: .visible
            ) {
                Button("Reset Prompt", role: .destructive) {
                    if let mode = self.pendingDefaultPromptReset {
                        withMotion { self.viewModel.resetDefaultPromptOverride(for: mode) }
                    }
                    self.pendingDefaultPromptReset = nil
                }
                Button("Cancel", role: .cancel) {
                    self.pendingDefaultPromptReset = nil
                }
            } message: {
                Text("Your changes to the default prompt will be lost.")
            }
    }

    // MARK: - Confirmations

    private var deletePromptTitle: String {
        let name = self.viewModel.pendingDeletePromptName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Delete this prompt?" : "Delete “\(name)”?"
    }

    private var deleteProviderTitle: String {
        guard let id = self.pendingProviderDeletionID else { return "Delete this provider?" }
        return "Delete “\(self.displayName(forProviderID: id))”?"
    }

    private var resetPromptTitle: String {
        guard let mode = self.pendingDefaultPromptReset else { return "Reset the default prompt?" }
        return "Reset the default \(AIPromptModeHeader.shortName(for: mode)) prompt?"
    }

    private var isConfirmingProviderDeletion: Binding<Bool> {
        Binding(
            get: { self.pendingProviderDeletionID != nil },
            set: { if !$0 { self.pendingProviderDeletionID = nil } }
        )
    }

    private var isConfirmingPromptReset: Binding<Bool> {
        Binding(
            get: { self.pendingDefaultPromptReset != nil },
            set: { if !$0 { self.pendingDefaultPromptReset = nil } }
        )
    }

    private func deletePendingProvider() {
        guard let id = self.pendingProviderDeletionID else { return }
        // `deleteCurrentProvider` removes the selected provider, so select it first.
        self.activateProvider(id)
        withMotion {
            self.viewModel.deleteCurrentProvider()
            self.viewModel.showingEditProvider = false
            self.expandedProviderID = nil
        }
        self.pendingProviderDeletionID = nil
    }
}
