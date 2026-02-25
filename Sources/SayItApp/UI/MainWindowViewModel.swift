import Foundation

@MainActor
final class MainWindowViewModel: ObservableObject {
    @Published var selectedTab: AppTabID = .live
}
