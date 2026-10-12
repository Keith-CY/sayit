import SwiftUI

struct VoiceEngineSettingsScreen: View {
    let appServices: AppServices
    let theme: AppTheme

    @StateObject private var viewModel: VoiceEngineSettingsViewModel

    init(appServices: AppServices, theme: AppTheme) {
        self.appServices = appServices
        self.theme = theme
        _viewModel = StateObject(wrappedValue: VoiceEngineSettingsViewModel(
            settings: SettingsStore.shared,
            appServices: appServices
        ))
    }

    var body: some View {
        SettingsKit.Page(
            title: "Voice Engine",
            subtitle: "The speech model that turns your voice into text. Everything runs on this Mac."
        ) {
            VoiceEngineSettingsView(
                viewModel: self.viewModel,
                settings: self.viewModel.settings
            )
        }
    }
}

struct AIEnhancementSettingsScreen: View {
    let menuBarManager: MenuBarManager
    let theme: AppTheme

    @StateObject private var viewModel: AIEnhancementSettingsViewModel

    init(menuBarManager: MenuBarManager, theme: AppTheme) {
        self.menuBarManager = menuBarManager
        self.theme = theme
        _viewModel = StateObject(wrappedValue: AIEnhancementSettingsViewModel(
            settings: SettingsStore.shared,
            menuBarManager: menuBarManager,
            promptTest: DictationPromptTestCoordinator.shared
        ))
    }

    var body: some View {
        SettingsKit.Page(
            title: "AI Enhancement",
            subtitle: AIEnhancementCopy.pageSubtitle
        ) {
            AIEnhancementSettingsView(
                viewModel: self.viewModel,
                settings: self.viewModel.settings,
                promptTest: self.viewModel.promptTest,
                theme: self.theme
            )
        }
    }
}
