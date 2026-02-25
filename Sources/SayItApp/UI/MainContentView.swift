import SwiftUI

struct MainContentView: View {
    @ObservedObject var windowViewModel: MainWindowViewModel
    @ObservedObject var liveViewModel: LiveTranscriptionViewModel
    @ObservedObject var historyViewModel: HistoryViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var modelsViewModel: LocalModelsViewModel
    @EnvironmentObject private var language: AppLanguageCenter

    var body: some View {
        ZStack {
            LiquidGlassCanvas()

            NavigationSplitView {
                sidebar
            } detail: {
                ZStack {
                    LiquidGlassCanvas()

                    currentTabContent
                        .padding(18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .navigationSplitViewStyle(.balanced)
        }
        .id(language.localeCode)
    }

    private var sidebar: some View {
        VStack(spacing: 12) {
            LiquidGlassCard(cornerRadius: 18) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LiquidGlassTheme.chromeGradient)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(LiquidGlassTheme.hairline, lineWidth: 1)
                            )
                        Image(systemName: "waveform.and.mic")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(LiquidGlassTheme.accentGradient)
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("SayIt")
                            .font(.title3.weight(.semibold))
                        Text(language.text("app.sidebarSubtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)

            List(selection: sidebarSelection) {
                ForEach(navigationItems, id: \.id) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item.id)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .tint(LiquidGlassTheme.hotPink)
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 260, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sidebarSelection: Binding<AppTabID?> {
        Binding(
            get: { windowViewModel.selectedTab },
            set: { newValue in
                guard let newValue else { return }
                windowViewModel.selectedTab = newValue
            }
        )
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

    private var navigationItems: [(id: AppTabID, title: String, systemImage: String)] {
        [
            (.live, language.text("tab.live"), "waveform"),
            (.history, language.text("tab.history"), "clock.arrow.circlepath"),
            (.settings, language.text("tab.settings"), "slider.horizontal.3"),
        ]
    }
}
