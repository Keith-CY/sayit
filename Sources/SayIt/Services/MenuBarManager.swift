import AppKit
import Combine
import SwiftUI

enum MenuBarNavigationDestination: String {
    case preferences
}

@MainActor
final class MenuBarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var isSetup: Bool = false
    private var hostedWindow: NSWindow?

    // Cached menu items to avoid rebuilding entire menu
    private var statusMenuItem: NSMenuItem?
    private var aiMenuItem: NSMenuItem?

    // References to app state
    private weak var asrService: ASRService?
    private var cancellables = Set<AnyCancellable>()
    private var menuBarAnimator: MenuBarAnimator?

    // Overlay management (persistent, independent of window lifecycle)
    private var overlayVisible: Bool = false

    // Track when AI processing is active.
    // When recording stops, ASRService flips `isRunning` to false, which would normally hide the
    // overlay. During post-processing we want the overlay to stay visible until processing ends.
    private var isProcessingActive: Bool = false

    @Published var isRecording: Bool = false
    @Published var aiProcessingEnabled: Bool = false

    /// One-shot navigation requests from the menu bar into the main window UI.
    /// `ContentView` consumes this and clears it.
    @Published var requestedNavigationDestination: MenuBarNavigationDestination? = nil

    // Track current overlay mode for notch
    private var currentOverlayMode: OverlayMode = .dictation

    // Track pending overlay operations to prevent spam
    private var pendingShowOperation: DispatchWorkItem?
    private var pendingHideOperation: DispatchWorkItem?

    // Subscription for forwarding audio levels to expanded command notch
    private var expandedModeAudioSubscription: AnyCancellable?
    private let menuBarIconSize = NSSize(width: 18, height: 18)

    init() {
        // Don't setup menu bar immediately - defer until app is ready
        // Initialize from persisted setting
        self.aiProcessingEnabled = SettingsStore.shared.enableAIProcessing
        // Reflect changes to menu when toggled from elsewhere (e.g., General tab)
        self.$aiProcessingEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenu()
            }
            .store(in: &self.cancellables)
    }

    func initializeMenuBar() {
        guard !self.isSetup else { return }

        // Ensure we're on main thread and app is active
        DispatchQueue.main.async { [weak self] in
            self?.setupMenuBarSafely()
        }
    }

    deinit {
        statusItem = nil
    }

    func configure(asrService: ASRService) {
        self.asrService = asrService

        // Subscribe to recording state changes
        asrService.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRunning in
                self?.isRecording = isRunning
                if isRunning {
                    self?.menuBarAnimator?.start(.recording)
                } else if self?.isProcessingActive == false {
                    self?.menuBarAnimator?.stop()
                }
                self?.updateMenuBarIcon()
                self?.updateMenu()

                // Handle overlay lifecycle (independent of window state)
                self?.handleOverlayState(isRunning: isRunning, asrService: asrService)
            }
            .store(in: &self.cancellables)

        // Subscribe to partial transcription updates for streaming preview
        asrService.$partialTranscription
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newText in
                guard self != nil else { return }
                // CRITICAL FIX: Check if streaming preview is enabled before updating notch
                // The "Show Live Preview" toggle in Preferences should control this behavior
                if SettingsStore.shared.enableStreamingPreview {
                    NotchOverlayManager.shared.updateTranscriptionText(newText)
                }
            }
            .store(in: &self.cancellables)

        // Subscribe to AI processing state
        self.aiProcessingEnabled = SettingsStore.shared.enableAIProcessing
    }

    private func handleOverlayState(isRunning: Bool, asrService: ASRService) {
        // Don't hide the overlay while AI processing is active.
        // Without this, the notch can disappear during the short "Refining..." phase because
        // `isRunning` becomes false before post-processing completes.
        if !isRunning, self.isProcessingActive {
            return
        }

        // Prevent rapid state changes that could cause cycles
        guard self.overlayVisible != isRunning else { return }

        let delay: DispatchTimeInterval = .milliseconds(30)
        if isRunning {
            // Cancel any pending hide operation
            self.pendingHideOperation?.cancel()
            self.pendingHideOperation = nil

            self.overlayVisible = true

            // If expanded command output is showing, check if we should keep it or close it
            if NotchOverlayManager.shared.isCommandOutputExpanded {
                // Only keep expanded notch if this is a command mode recording (follow-up)
                // For other modes (dictation, rewrite), close it and show regular notch
                if self.currentOverlayMode == .command {
                    // Enable recording visualization in the expanded notch
                    NotchContentState.shared.setRecordingInExpandedMode(true)

                    // Subscribe to audio levels and forward to expanded notch
                    self.expandedModeAudioSubscription = asrService.audioLevelPublisher
                        .receive(on: DispatchQueue.main)
                        .sink { level in
                            NotchContentState.shared.updateExpandedModeAudioLevel(level)
                        }

                    self.pendingShowOperation = nil
                    return
                } else {
                    // Close expanded command notch to transition to regular notch
                    NotchOverlayManager.shared.hideExpandedCommandOutput()
                }
            }

            let showItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.overlayVisible else { return }

                // Double-check expanded notch isn't showing (could have changed during delay)
                // But only block if we're in command mode
                if NotchOverlayManager.shared.isCommandOutputExpanded && self.currentOverlayMode == .command {
                    self.pendingShowOperation = nil
                    return
                }

                // Show notch overlay
                NotchOverlayManager.shared.show(
                    audioLevelPublisher: asrService.audioLevelPublisher,
                    mode: self.currentOverlayMode
                )

                self.pendingShowOperation = nil
            }
            self.pendingShowOperation = showItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: showItem)
        } else {
            // Cancel any pending show operation
            self.pendingShowOperation?.cancel()
            self.pendingShowOperation = nil

            self.overlayVisible = false

            // If expanded command output is showing, don't hide it - let it stay visible
            if NotchOverlayManager.shared.isCommandOutputExpanded {
                // Stop recording visualization in expanded notch
                NotchContentState.shared.setRecordingInExpandedMode(false)
                self.expandedModeAudioSubscription?.cancel()
                self.expandedModeAudioSubscription = nil

                self.pendingHideOperation = nil
                return
            }

            let hideItem = DispatchWorkItem { [weak self] in
                guard let self = self, !self.overlayVisible else { return }

                // Don't hide if expanded command output is now showing
                if NotchOverlayManager.shared.isCommandOutputExpanded {
                    self.pendingHideOperation = nil
                    return
                }

                // Hide notch overlay
                NotchOverlayManager.shared.hide()

                self.pendingHideOperation = nil
            }
            self.pendingHideOperation = hideItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: hideItem)
        }
    }

    // MARK: - Public API for overlay management

    func updateOverlayTranscription(_ text: String) {
        NotchOverlayManager.shared.updateTranscriptionText(text)
    }

    func setOverlayMode(_ mode: OverlayMode) {
        self.currentOverlayMode = mode
        NotchOverlayManager.shared.setMode(mode)
    }

    func setProcessing(_ processing: Bool) {
        // Track processing state to prevent hide during AI refinement
        self.isProcessingActive = processing

        if processing {
            self.menuBarAnimator?.start(.processing)
            // Cancel any pending hide - we want to keep the overlay visible for AI processing
            self.pendingHideOperation?.cancel()
            self.pendingHideOperation = nil
            self.overlayVisible = true
        } else {
            if self.isRecording == false {
                self.menuBarAnimator?.stop()
            }

            // When processing ends, schedule the hide (unless expanded output is showing)
            self.overlayVisible = false

            // If expanded command output is showing, don't hide it
            if NotchOverlayManager.shared.isCommandOutputExpanded {
                self.pendingHideOperation = nil
                NotchOverlayManager.shared.setProcessing(processing)
                return
            }

            let hideItem = DispatchWorkItem { [weak self] in
                guard let self = self, !self.overlayVisible else { return }

                // Don't hide if expanded command output is now showing
                if NotchOverlayManager.shared.isCommandOutputExpanded {
                    self.pendingHideOperation = nil
                    return
                }

                NotchOverlayManager.shared.hide()
                self.pendingHideOperation = nil
            }
            self.pendingHideOperation = hideItem
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: hideItem)
        }
        NotchOverlayManager.shared.setProcessing(processing)
    }

    private func setupMenuBarSafely() {
        // Check if window server connection is available
        guard NSApp.isActive || NSApp.isRunning else {
            // Retry after a short delay if app isn't ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.setupMenuBarSafely()
            }
            return
        }

        do {
            try self.setupMenuBar()
            self.isSetup = true
        } catch {
            // If setup fails, retry after delay
            DebugLogger.shared.error("MenuBar setup failed, retrying: \(error)", source: "MenuBarManager")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.setupMenuBarSafely()
            }
        }
    }

    private func setupMenuBar() throws {
        // Ensure we're not already set up
        guard !self.isSetup else { return }

        // Create status item with error handling
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let statusItem = statusItem else {
            throw NSError(domain: "MenuBarManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create status item"])
        }

        self.menuBarAnimator = MenuBarAnimator(statusItem: statusItem)

        // Set initial icon
        self.updateMenuBarIcon()
        self.configureMenuBarButton()

        // Create menu
        self.menu = NSMenu()
        statusItem.menu = self.menu

        self.updateMenu()
    }

    private func updateMenuBarIcon() {
        guard self.statusItem != nil else { return }

        guard let image = MenuBarAnimator.loadImage(named: "MenuBarIcon")
            ?? MenuBarAnimator.loadImage(named: "menubar_icon_36")
            ?? MenuBarAnimator.loadImage(named: "menubar_icon_18")
            ?? MenuBarIconGenerator.createMenuBarIcon()
        else {
            return
        }

        self.applyMenuBarImage(image)
    }

    private func configureMenuBarButton() {
        guard let button = statusItem?.button else { return }

        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyUpOrDown
        button.title = ""
        button.isEnabled = true
        button.toolTip = "SayIt"
    }

    private func applyMenuBarImage(_ image: NSImage) {
        guard let button = statusItem?.button else { return }

        let preparedImage = NSImage(size: self.menuBarIconSize)
        preparedImage.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: self.menuBarIconSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1.0
        )
        preparedImage.unlockFocus()

        preparedImage.isTemplate = true
        button.imageScaling = .scaleProportionallyUpOrDown
        button.image = preparedImage
    }

    private func buildMenuStructure() {
        guard let menu = menu else { return }

        menu.removeAllItems()

        // Status indicator with hotkey info
        self.statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        self.statusMenuItem?.isEnabled = false
        if let statusItem = statusMenuItem {
            menu.addItem(statusItem)
        }

        menu.addItem(.separator())

        // AI Processing Toggle
        self.aiMenuItem = NSMenuItem(title: "", action: #selector(self.toggleAIProcessing), keyEquivalent: "")
        self.aiMenuItem?.target = self
        if let aiItem = aiMenuItem {
            menu.addItem(aiItem)
        }

        menu.addItem(.separator())

        // Open Main Window
        let openItem = NSMenuItem(title: AppIdentity.menuOpenItem, action: #selector(openMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        // Preferences
        let preferencesItem = NSMenuItem(title: "Preferences", action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        preferencesItem.keyEquivalentModifierMask = [.command]
        menu.addItem(preferencesItem)

        // Quit
        let quitItem = NSMenuItem(
            title: AppIdentity.menuQuitItem,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)

        // Now update the text content
        self.updateMenuItemsText()
    }

    private func updateMenu() {
        // If menu structure hasn't been built yet, build it
        if self.statusMenuItem == nil {
            self.buildMenuStructure()
        } else {
            // Just update the text of existing items
            self.updateMenuItemsText()
        }
    }

    private func updateMenuItemsText() {
        // Update status text with hotkey info
        let hotkeyShortcut = SettingsStore.shared.hotkeyShortcut
        let hotkeyInfo = hotkeyShortcut.displayString.isEmpty ? "" : " (\(hotkeyShortcut.displayString))"
        let statusTitle = self.isRecording
            ? "\(AppIdentity.menuStatusRecording)\(hotkeyInfo)"
            : "\(AppIdentity.menuStatusReady)\(hotkeyInfo)"
        self.statusMenuItem?.title = statusTitle

        // Update AI toggle text
        let aiTitle = self.aiProcessingEnabled ? "Disable AI Processing" : "Enable AI Processing"
        self.aiMenuItem?.title = aiTitle

    }

    /// Centralized entry point to update AI post-processing enablement.
    /// Use this instead of writing `aiProcessingEnabled` directly so all state stays in sync.
    func setAIProcessingEnabled(_ enabled: Bool) {
        guard self.aiProcessingEnabled != enabled else {
            // Ensure menu text stays correct even if caller repeats the same value.
            self.updateMenu()
            return
        }
        self.aiProcessingEnabled = enabled
        SettingsStore.shared.enableAIProcessing = enabled
        self.updateMenu()
    }

    /// Toggle AI post-processing and return the new value.
    @discardableResult
    func toggleAIProcessingEnabled() -> Bool {
        let next = !self.aiProcessingEnabled
        self.setAIProcessingEnabled(next)
        return next
    }

    @objc private func toggleAIProcessing() {
        _ = self.toggleAIProcessingEnabled()
    }

    @objc private func openMainWindow() {
        // First, unhide the app if it's hidden
        if NSApp.isHidden {
            NSApp.unhide(nil)
        }

        // Activate the app and bring it to the front
        NSApp.activate(ignoringOtherApps: true)

        // Find an existing *non-minimized* primary window.
        // Important: avoid programmatic deminiaturize() — it creates internal window transform animations
        // (NSWindowTransformAnimation) that have been unstable on macOS 26.x for this app.
        if let window = self.hostedWindow, window.isReleasedWhenClosed == false {
            AppWindowHelper.makeUsableMainWindow(window)
            window.animationBehavior = .none
            AppWindowHelper.bringToFront(window)
        } else if let window = AppWindowHelper.primaryWindow(in: NSApp),
                  self.isHostedWindowUsable(window) {
            AppWindowHelper.makeUsableMainWindow(window)
            window.animationBehavior = .none
            AppWindowHelper.bringToFront(window)
            self.hostedWindow = window
        } else {
            // If there is no suitable window (or it's minimized), create a fresh one.
            self.createAndShowMainWindow()
        }

        // Final attempt: ensure app is active and visible
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func openPreferences() {
        // Ensure a fresh one-shot request every time the menu item is clicked.
        self.requestedNavigationDestination = nil
        self.requestedNavigationDestination = .preferences

        self.openMainWindow()

        // Nudge again after the window is front-most, so an already-open ContentView
        // will still switch tabs even if it consumed a previous preference request.
        DispatchQueue.main.async { [weak self] in
            self?.requestedNavigationDestination = nil
            self?.requestedNavigationDestination = .preferences
        }
    }

    /// Public entry-point for non-menu UI surfaces (e.g. overlay controls) to open Preferences.
    func openPreferencesFromUI() {
        self.openPreferences()
    }

    /// Create and present a fresh main window hosting `ContentView`
    private func createAndShowMainWindow() {
        // Build the SwiftUI root view with required environment
        let rootView = ContentView()
            .environmentObject(self)
            .environmentObject(AppServices.shared)
            .appTheme(.dark)
            .preferredColorScheme(.dark)

        // Host inside an AppKit window
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: AppWindowHelper.defaultWindowSize.width, height: AppWindowHelper.defaultWindowSize.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppIdentity.displayName
        window.animationBehavior = .none
        AppWindowHelper.makeUsableMainWindow(window)
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.setFrame(AppWindowHelper.defaultWindowFrame(), display: false)
        AppWindowHelper.bringToFront(window)
        self.hostedWindow = window

        // Bring app to front in case we're running as an accessory app (no Dock)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func isHostedWindowUsable(_ window: NSWindow) -> Bool {
        window.isMiniaturized == false && AppWindowHelper.isPrimaryWindow(window)
    }
}
