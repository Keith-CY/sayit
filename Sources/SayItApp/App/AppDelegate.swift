import AppKit
import SayItCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var onboardingWindow: NSWindow?
    private var hotkeyManager: GlobalHotkeyManager?
    private var windowViewModel: MainWindowViewModel?
    private var liveViewModel: LiveTranscriptionViewModel?
    private var historyViewModel: HistoryViewModel?
    private var settingsViewModel: SettingsViewModel?
    private var modelsViewModel: LocalModelsViewModel?
    private var languageCenter: AppLanguageCenter?
    private var runtime: SayItCoreRuntime?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupWindows()
        setupHotkey()
    }

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "SayIt"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Live", action: #selector(openLiveWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "History", action: #selector(openHistoryWindow), keyEquivalent: "h"))
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettingsWindow), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Permissions", action: #selector(openOnboardingWindow), keyEquivalent: "p"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func setupWindows() {
        do {
            runtime = try SayItCoreRuntime()
        } catch {
            runtime = nil
            NSLog("Failed to initialize SayItCoreRuntime: \(error.localizedDescription)")
        }

        let locale = (try? runtime?.configManager.load().locale) ?? "zh-Hans"
        let languageCenter = AppLanguageCenter(localeCode: locale)
        self.languageCenter = languageCenter

        let windowViewModel = MainWindowViewModel()
        self.windowViewModel = windowViewModel

        let historyViewModel = HistoryViewModel(runtime: runtime)
        self.historyViewModel = historyViewModel

        let liveViewModel = LiveTranscriptionViewModel(runtime: runtime) { [weak historyViewModel] in
            historyViewModel?.refresh()
        }
        self.liveViewModel = liveViewModel

        let settingsViewModel = SettingsViewModel(runtime: runtime) { [weak self, weak historyViewModel, weak languageCenter] config in
            languageCenter?.setLocale(config.locale)
            historyViewModel?.refresh()
            self?.setupHotkey()
        }
        self.settingsViewModel = settingsViewModel

        let modelsViewModel = LocalModelsViewModel(runtime: runtime)
        self.modelsViewModel = modelsViewModel

        let rootView = MainContentView(
            windowViewModel: windowViewModel,
            liveViewModel: liveViewModel,
            historyViewModel: historyViewModel,
            settingsViewModel: settingsViewModel,
            modelsViewModel: modelsViewModel
        )
        .environmentObject(languageCenter)

        let liveWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        liveWindow.center()
        liveWindow.title = "SayIt"
        liveWindow.minSize = NSSize(width: 900, height: 620)
        liveWindow.setFrameAutosaveName("SayItMainWindow")
        liveWindow.contentView = NSHostingView(rootView: rootView)
        self.window = liveWindow

        let onboardingView = OnboardingView()
        let onboardingWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        onboardingWindow.center()
        onboardingWindow.title = "SayIt Permissions"
        onboardingWindow.minSize = NSSize(width: 500, height: 300)
        onboardingWindow.contentView = NSHostingView(rootView: onboardingView)
        self.onboardingWindow = onboardingWindow
    }

    private func setupHotkey() {
        let manager = GlobalHotkeyManager()
        manager.onHotkey = { [weak self] in
            self?.openLiveWindow()
            self?.liveViewModel?.toggleHotkeyCapture()
        }
        do {
            let hotkey = (try? runtime?.configManager.load().hotkey) ?? AppConfig.HotkeyConfig()
            try manager.register(keyCode: hotkey.keyCode, modifiers: hotkey.modifiers)
        } catch {
            NSLog("Failed to register global hotkey: \(error.localizedDescription)")
        }
        self.hotkeyManager = manager
    }

    @objc private func openLiveWindow() {
        windowViewModel?.selectedTab = .live
        window?.title = "SayIt Live"
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openHistoryWindow() {
        windowViewModel?.selectedTab = .history
        window?.title = "SayIt History"
        historyViewModel?.refresh()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettingsWindow() {
        windowViewModel?.selectedTab = .settings
        window?.title = "SayIt Settings"
        settingsViewModel?.load(includeSecrets: true)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openOnboardingWindow() {
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
