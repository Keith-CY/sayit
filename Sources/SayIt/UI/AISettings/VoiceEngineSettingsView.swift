import SwiftUI

struct VoiceEngineSettingsView: View {
    @ObservedObject var viewModel: VoiceEngineSettingsViewModel
    @ObservedObject var settings: SettingsStore
    @Environment(\.theme) var theme

    /// Model awaiting delete confirmation.
    @State var pendingDeletion: SettingsStore.SpeechModel? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            self.inUseCard
            self.modelsSection
            self.languageSection
            self.cleanUpSection
            self.vocabularySection
        }
        .onAppear { self.viewModel.onAppear() }
        .onChange(of: self.settings.selectedSpeechModel) { _, newValue in
            self.viewModel.handleSelectedSpeechModelChange(newValue)
        }
        .confirmationDialog(
            self.pendingDeletion.map { "Delete \($0.uiName)?" } ?? "",
            isPresented: Binding(
                get: { self.pendingDeletion != nil },
                set: { if !$0 { self.pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: self.pendingDeletion
        ) { model in
            Button("Delete Download", role: .destructive) {
                self.viewModel.deleteSpeechModel(model)
                self.pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                self.pendingDeletion = nil
            }
        } message: { model in
            Text("This removes \(model.uiSizePhrase) from this Mac. You can download it again at any time.")
        }
    }
}
