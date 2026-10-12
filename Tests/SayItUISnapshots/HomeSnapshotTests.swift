import AVFoundation
import SwiftUI
import XCTest

@testable import SayIt

/// Home in its main states, plus the sidebar at the minimum window size.
/// All state is injected; nothing reads or writes the user's settings or history.
@MainActor
final class HomeSnapshotTests: XCTestCase {
    private let pageSize = CGSize(width: 760, height: 1180)

    func testHomeFreshInstall() throws {
        try SnapshotRenderer.snapshot("home-1-fresh-install", size: self.pageSize) {
            HomeHarness(state: .fixture(), testArea: .idle(.requestMicrophoneAccess))
        }
    }

    func testHomePartiallySetUpDownloading() throws {
        var state = HomeState.fixture()
        state.micStatus = .authorized
        state.accessibilityEnabled = true
        state.modelState = .downloading(fraction: 0.42, cancellable: true)
        try SnapshotRenderer.snapshot("home-2-downloading", size: self.pageSize) {
            HomeHarness(state: state, testArea: .idle(.waitForModel))
        }
    }

    func testHomeEdgeStates() throws {
        var state = HomeState.fixture()
        state.micStatus = .restricted
        state.accessibilityEnabled = true
        state.accessibilityNeedsRestart = true
        state.modelState = .failed("The network connection was lost.")
        try SnapshotRenderer.snapshot("home-3-edge-states", size: self.pageSize) {
            HomeHarness(state: state, testArea: .idle(.showMicrophoneRestriction))
        }
    }

    func testHomeSetupComplete() throws {
        var state = HomeState.fixture()
        state.micStatus = .authorized
        state.accessibilityEnabled = true
        state.modelState = .ready
        state.firstDictationDone = true
        state.aiEnhancementConfigured = true
        state.aiEnhancementEnabled = true
        state.recent = [
            RecentDictation(
                id: UUID(),
                text: "Please review this pull request, then deploy it to staging.",
                appName: "Slack",
                date: Date().addingTimeInterval(-120)
            ),
            RecentDictation(
                id: UUID(),
                text: "请帮我 review 这个 pull request，然后 deploy 到 staging。",
                appName: "Mail",
                date: Date().addingTimeInterval(-3600)
            ),
            RecentDictation(
                id: UUID(),
                text: "Let's move the design review to Thursday afternoon so the whole team can join.",
                appName: "Notes",
                date: Date().addingTimeInterval(-86400)
            ),
        ]
        var testArea = HomeTestAreaState.idle(.start)
        testArea.transcript = "Say it, and it's written — this is the test area."
        try SnapshotRenderer.snapshot("home-4-complete", size: CGSize(width: 760, height: 1260)) {
            HomeHarness(state: state, testArea: testArea)
        }
    }

    func testHomeRecording() throws {
        var state = HomeState.fixture()
        state.micStatus = .authorized
        state.accessibilityEnabled = true
        state.modelState = .ready
        var testArea = HomeTestAreaState.idle(.stop)
        testArea.isRunning = true
        try SnapshotRenderer.snapshot("home-5-recording", size: CGSize(width: 760, height: 900)) {
            HomeHarness(state: state, testArea: testArea)
        }
    }

    func testSidebar() throws {
        try SnapshotRenderer.snapshot("home-7-sidebar", size: CGSize(width: 240, height: 560)) {
            SidebarHarness()
        }
    }

    func testWindowAtMinimumSize() throws {
        try SnapshotRenderer.snapshot("home-6-window-min-800x560", size: CGSize(width: 800, height: 560)) {
            MinimumWindowHarness()
        }
    }
}

// MARK: - Fixtures

extension HomeState {
    static func fixture() -> HomeState {
        HomeState(
            micStatus: .notDetermined,
            accessibilityEnabled: false,
            accessibilityNeedsRestart: false,
            model: SpeechModelSummary(name: "Qwen3-ASR 1.7B · 8bit", sizeText: "About 2.47 GB"),
            modelState: .missing,
            firstDictationDone: false,
            aiEnhancementConfigured: false,
            aiEnhancementEnabled: false,
            shortcut: "Right ⌥",
            commandShortcut: "⌃⌥C",
            editShortcut: "⌃⌥E",
            historyEnabled: true,
            recent: []
        )
    }
}

extension HomeTestAreaState {
    static func idle(_ action: RecordingControlAction) -> HomeTestAreaState {
        HomeTestAreaState(action: action, isRunning: false, transcript: "", wordBoostText: nil)
    }
}

private struct HomeHarness: View {
    let state: HomeState
    let testArea: HomeTestAreaState
    @State private var transcript: String
    @FocusState private var focused: Bool

    init(state: HomeState, testArea: HomeTestAreaState) {
        self.state = state
        self.testArea = testArea
        _transcript = State(initialValue: testArea.transcript)
    }

    var body: some View {
        HomeView(
            state: self.state,
            testArea: self.testArea,
            transcript: self.$transcript,
            isTranscriptFocused: self.$focused,
            actions: HomeActions()
        )
    }
}

private struct SidebarHarness: View {
    @State private var selection: SidebarItem? = .home

    var body: some View {
        MainSidebar(selection: self.$selection)
    }
}

private struct MinimumWindowHarness: View {
    @State private var selection: SidebarItem? = .home

    var body: some View {
        NavigationSplitView {
            MainSidebar(selection: self.$selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            HomeHarness(state: .fixture(), testArea: .idle(.requestMicrophoneAccess))
        }
    }
}
