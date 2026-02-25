import SwiftUI

struct MainContentView: View {
    @ObservedObject var windowViewModel: MainWindowViewModel
    @ObservedObject var liveViewModel: LiveTranscriptionViewModel
    @ObservedObject var historyViewModel: HistoryViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var modelsViewModel: LocalModelsViewModel
    @EnvironmentObject private var language: AppLanguageCenter
    @State private var transitionDirection: Int = 1

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                tabButton(.live, title: language.text("tab.live"))
                tabButton(.history, title: language.text("tab.history"))
                tabButton(.settings, title: language.text("tab.settings"))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ZStack {
                currentTabContent
                    .id(windowViewModel.selectedTab)
                    .transition(tabTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeInOut(duration: 0.18), value: windowViewModel.selectedTab)
        .id(language.localeCode)
        .onChange(of: windowViewModel.selectedTab) { oldValue, newValue in
            transitionDirection = tabOrder(newValue) >= tabOrder(oldValue) ? 1 : -1
        }
    }

    @ViewBuilder
    private var currentTabContent: some View {
        switch windowViewModel.selectedTab {
        case .live:
            LiveContentView(viewModel: liveViewModel)
        case .history:
            HistoryContentView(viewModel: historyViewModel)
        case .settings:
            SettingsContentView(viewModel: settingsViewModel, modelsViewModel: modelsViewModel)
        }
    }

    private var tabTransition: AnyTransition {
        if transitionDirection >= 0 {
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        }
        return .asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }

    private func tabOrder(_ tab: AppTabID) -> Int {
        switch tab {
        case .live:
            return 0
        case .history:
            return 1
        case .settings:
            return 2
        }
    }

    private func tabButton(_ tab: AppTabID, title: String) -> some View {
        Button {
            windowViewModel.selectedTab = tab
        } label: {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(windowViewModel.selectedTab == tab ? Color.accentColor : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(windowViewModel.selectedTab == tab ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}
