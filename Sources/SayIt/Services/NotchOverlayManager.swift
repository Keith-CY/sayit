//
//  NotchOverlayManager.swift
//  SayIt
//
//  Created by Assistant
//

import AppKit
import Combine
import DynamicNotchKit
import SwiftUI

// MARK: - Overlay Mode

enum OverlayMode: String {
    case dictation = "Dictation"
    case edit = "Edit"
    case rewrite = "Rewrite"
    case write = "Write"
    case command = "Command"
}

/// Owns the recording overlay (notch or bottom style) and its lifecycle.
///
/// Phase contract (see `OverlayPhase`, DESIGN.md §8):
/// - `present(_:)` sets what the overlay communicates and announces it to VoiceOver.
/// - `show(...)` starts a session; unless work is already in progress it presents `.listening`.
/// - `setProcessing(true)` without a working phase presents `.refining`.
/// - A terminal phase (`.done`, `.failed`, `.cancelled`) stays on screen for
///   `Motion.outcomeDwell`: `hide()` waits out the remainder, and the overlay leaves on
///   its own when the dwell ends even if nobody calls `hide()`. A terminal phase presented
///   while the overlay is already gone re-shows it briefly for non-success outcomes.
/// - Starting a new session (`show`) cancels any pending deferred hide.
/// - After the overlay has left, the phase returns to `.idle`.
@MainActor
final class NotchOverlayManager {
    static let shared = NotchOverlayManager()

    private var notch: DynamicNotch<NotchExpandedView, EmptyView, EmptyView>?
    private var commandOutputNotch: DynamicNotch<NotchCommandOutputExpandedView, EmptyView, EmptyView>?
    private var currentMode: OverlayMode = .dictation

    // Store last audio publisher for re-showing during processing
    private var lastAudioPublisher: AnyPublisher<CGFloat, Never>?

    // Current audio publisher (can be updated for expanded notch recording)
    @Published private(set) var currentAudioPublisher: AnyPublisher<CGFloat, Never>?

    // State machine to prevent race conditions
    private enum State {
        case idle
        case showing
        case visible
        case hiding
    }

    private var state: State = .idle
    private var commandOutputState: State = .idle

    // Track if expanded command output is showing
    private(set) var isCommandOutputExpanded: Bool = false

    // Track if bottom overlay is visible
    private(set) var isBottomOverlayVisible: Bool = false

    // Callbacks for command output interaction
    var onCommandOutputDismiss: (() -> Void)?
    var onCommandFollowUp: ((String) async -> Void)?
    var onNotchClicked: (() -> Void)? // Called when regular notch is clicked in command mode

    // Callbacks for chat management
    var onNewChat: (() -> Void)?
    var onSwitchChat: ((String) -> Void)?
    var onClearChat: (() -> Void)?

    /// Stops the active recording session without transcribing and resets mode state.
    /// Set by `GlobalHotkeyManager`; invoked by Esc and the overlay's close button.
    var onCancelRequested: (() -> Void)?

    // Generation counter to track show/hide cycles and prevent race conditions
    // Uses UInt64 to avoid overflow concerns in long-running sessions
    private var generation: UInt64 = 0
    private var commandOutputGeneration: UInt64 = 0
    /// Incremented on every `show`; deferred hides only run within their own session.
    private var sessionGeneration: UInt64 = 0

    // Track pending retry task for cancellation
    private var pendingRetryTask: Task<Void, Never>?
    private var deferredHideTask: Task<Void, Never>?
    private var settleHideTask: Task<Void, Never>?

    // Escape key monitors for dismissing notch
    private var globalEscapeMonitor: Any?
    private var localEscapeMonitor: Any?

    /// Notch hide animation length in DynamicNotchKit.
    private static let notchHideDuration: Double = 0.4

    private init() {
        self.setupEscapeKeyMonitors()
    }

    /// True while a recording overlay (not the expanded command output) is on screen.
    var isOverlayVisible: Bool {
        self.isBottomOverlayVisible || self.state == .visible || self.state == .showing
    }

    // MARK: - Escape / Cancel

    /// Monitors Esc for the cases the global event tap does not cover (tap not yet
    /// installed, or SayIt itself focused). The event is consumed only when an overlay
    /// actually handled it; otherwise it continues to its normal destination.
    private func setupEscapeKeyMonitors() {
        func isPlainEscape(_ event: NSEvent) -> Bool {
            event.keyCode == 53 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.function).isEmpty
        }

        self.globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard isPlainEscape(event) else { return }
            MainActor.assumeIsolated {
                _ = NotchOverlayManager.shared.handleEscape()
            }
        }

        self.localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isPlainEscape(event) else { return event }
            let handled = MainActor.assumeIsolated {
                NotchOverlayManager.shared.handleEscape()
            }
            return handled ? nil : event
        }
    }

    /// Esc / close button. Closes an open overlay menu, then the expanded command output,
    /// then cancels the visible session (or dismisses a finished one). Returns true only
    /// when the key was meant for SayIt; otherwise it should reach the focused app.
    @discardableResult
    func handleEscape() -> Bool {
        if OverlayMenuController.shared.isOpen {
            OverlayMenuController.shared.hide()
            return true
        }

        if self.isCommandOutputExpanded {
            self.hideExpandedCommandOutput()
            self.onCommandOutputDismiss?()
            return true
        }

        guard self.isOverlayVisible else { return false }

        // Already showing an outcome: leave now, and let the key reach the user's app
        // (they are back to typing, not talking to SayIt).
        if NotchContentState.shared.phase.isTerminal {
            self.hideNow()
            return false
        }

        self.cancel()
        return true
    }

    /// Cancels the session: stops recording without transcribing, shows "Cancelled",
    /// then leaves after the dwell.
    func cancel() {
        self.onCancelRequested?()
        self.present(.cancelled)
        self.hide()
    }

    // MARK: - Show

    func show(audioLevelPublisher: AnyPublisher<CGFloat, Never>, mode: OverlayMode) {
        self.showSession(audioLevelPublisher: audioLevelPublisher, mode: mode, startsListening: true)
    }

    private func showSession(audioLevelPublisher: AnyPublisher<CGFloat, Never>, mode: OverlayMode, startsListening: Bool) {
        self.cancelPendingHides()
        self.sessionGeneration &+= 1

        // A new session starts listening, unless this show is re-surfacing work in progress.
        if startsListening, !NotchContentState.shared.phase.isWorking {
            self.present(.listening)
        }

        // Don't show regular notch if expanded command output is visible
        if self.isCommandOutputExpanded {
            // Just store the publisher for later use
            self.lastAudioPublisher = audioLevelPublisher
            return
        }

        // Cancel any pending retry operations
        self.pendingRetryTask?.cancel()
        self.pendingRetryTask = nil

        // If already visible or in transition, wait for cleanup to complete
        if self.notch != nil || self.state != .idle {
            // Increment generation to invalidate stale operations
            self.generation &+= 1
            let targetGeneration = self.generation

            // Start async cleanup and retry
            self.pendingRetryTask = Task { [weak self] in
                guard let self = self else { return }

                // Perform cleanup synchronously first
                await self.performCleanup()

                // Small delay to ensure cleanup completes
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

                // Check if we're still the active operation
                guard !Task.isCancelled, self.generation == targetGeneration else { return }

                // Retry show
                self.showInternal(audioLevelPublisher: audioLevelPublisher, mode: mode)
            }
            return
        }

        self.showInternal(audioLevelPublisher: audioLevelPublisher, mode: mode)
    }

    private func showInternal(audioLevelPublisher: AnyPublisher<CGFloat, Never>, mode: OverlayMode) {
        guard self.state == .idle else { return }

        // Store for potential re-show during processing
        self.lastAudioPublisher = audioLevelPublisher
        OverlayAudioMeter.shared.attach(audioLevelPublisher)

        // Start monitoring active app changes (updates icon in real-time)
        ActiveAppMonitor.shared.startMonitoring()

        let screen = OverlayScreenResolver.targetScreen(pid: NotchContentState.shared.recordingTargetPID)

        // Route to bottom overlay if user preference is set
        if SettingsStore.shared.overlayPosition == .bottom {
            self.showBottomOverlay(audioLevelPublisher: audioLevelPublisher, mode: mode, screen: screen)
            return
        }

        // Otherwise show notch overlay (original behavior)
        self.showNotchOverlay(mode: mode, screen: screen)
    }

    /// Show bottom overlay (alternative to notch)
    private func showBottomOverlay(audioLevelPublisher: AnyPublisher<CGFloat, Never>, mode: OverlayMode, screen: NSScreen?) {
        // Hide any existing notch first
        if self.notch != nil {
            Task { await self.performCleanup() }
        }

        self.lastAudioPublisher = audioLevelPublisher
        self.currentMode = mode.normalized

        BottomOverlayWindowController.shared.show(mode: self.currentMode, on: screen)
        self.isBottomOverlayVisible = true
    }

    /// Show notch overlay (original behavior)
    private func showNotchOverlay(mode: OverlayMode, screen: NSScreen?) {
        // Hide bottom overlay if it was visible
        if self.isBottomOverlayVisible {
            BottomOverlayWindowController.shared.hide()
            self.isBottomOverlayVisible = false
        }

        // Increment generation for this operation
        self.generation &+= 1
        let currentGeneration = self.generation

        self.state = .showing
        self.currentMode = mode.normalized

        // Update shared content state immediately
        NotchContentState.shared.mode = self.currentMode
        self.syncPromptPickerMode(for: self.currentMode)
        NotchContentState.shared.updateTranscription("")

        // Clicking the notch opens menus explicitly; no hover-to-open behaviour.
        let newNotch = DynamicNotch(hoverBehavior: [.keepVisible], style: .auto) {
            NotchExpandedView()
        }

        self.notch = newNotch

        // Show in expanded state
        Task { [weak self] in
            if let screen {
                await newNotch.expand(on: screen)
            } else {
                await newNotch.expand()
            }
            // Only update state if we're still the active generation
            guard let self = self, self.generation == currentGeneration else { return }
            self.state = .visible
        }
    }

    // MARK: - Hide

    /// Hides the overlay. If an outcome is on screen, waits until it has been visible for
    /// `Motion.outcomeDwell` first.
    func hide() {
        let content = NotchContentState.shared
        if content.phase.isTerminal, self.isOverlayVisible {
            let remaining = Motion.outcomeDwell - Date().timeIntervalSince(content.phaseChangedAt)
            if remaining > 0.02 {
                self.scheduleDeferredHide(after: remaining)
                return
            }
        }
        self.hideNow()
    }

    /// Hides after work ends, giving the pipeline `Motion.outcomeGrace` to report an
    /// outcome first. Used when processing finishes without an explicit outcome.
    func hideWhenSettled() {
        if NotchContentState.shared.phase.isTerminal {
            self.hide()
            return
        }
        self.settleHideTask?.cancel()
        let session = self.sessionGeneration
        self.settleHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Motion.outcomeGrace * 1_000_000_000))
            guard let self, !Task.isCancelled, self.sessionGeneration == session else { return }
            self.settleHideTask = nil
            self.hide()
        }
    }

    private func scheduleDeferredHide(after delay: TimeInterval) {
        self.deferredHideTask?.cancel()
        let session = self.sessionGeneration
        self.deferredHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(delay, 0) * 1_000_000_000))
            guard let self, !Task.isCancelled, self.sessionGeneration == session else { return }
            self.deferredHideTask = nil
            self.hideNow()
        }
    }

    private func cancelPendingHides() {
        self.deferredHideTask?.cancel()
        self.deferredHideTask = nil
        self.settleHideTask?.cancel()
        self.settleHideTask = nil
    }

    private func hideNow() {
        self.cancelPendingHides()
        OverlayMenuController.shared.hide()

        // Stop monitoring active app changes
        ActiveAppMonitor.shared.stopMonitoring()
        OverlayAudioMeter.shared.detach()

        // Hide bottom overlay if visible
        if self.isBottomOverlayVisible {
            BottomOverlayWindowController.shared.hide()
            self.isBottomOverlayVisible = false
        }

        // Cancel any pending retry operations
        self.pendingRetryTask?.cancel()
        self.pendingRetryTask = nil

        // Safety: reset processing state when hiding
        NotchContentState.shared.setProcessing(false)
        self.scheduleIdleReset()

        // Increment generation to invalidate any pending show tasks
        self.generation &+= 1
        let currentGeneration = self.generation

        // Handle visible or showing states (can hide while still expanding)
        guard self.state == .visible || self.state == .showing, let currentNotch = notch else {
            // Force cleanup if stuck or in inconsistent state
            Task { [weak self] in await self?.performCleanup() }
            return
        }

        self.state = .hiding

        Task { [weak self] in
            await currentNotch.hide()
            // Only clear if we're still the active operation
            guard let self = self, self.generation == currentGeneration else { return }
            self.notch = nil
            self.state = .idle
        }
    }

    /// Returns the phase to `.idle` once the exit animation has finished, so the
    /// leaving overlay keeps showing its last state.
    private func scheduleIdleReset() {
        let session = self.sessionGeneration
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((Self.notchHideDuration + 0.05) * 1_000_000_000))
            guard let self, self.sessionGeneration == session, !self.isOverlayVisible else { return }
            NotchContentState.shared.setPhase(.idle)
        }
    }

    /// Async cleanup that properly waits for hide to complete
    private func performCleanup() async {
        // Cancel any pending retry operations
        self.pendingRetryTask?.cancel()
        self.pendingRetryTask = nil

        if let existingNotch = notch {
            await existingNotch.hide()
        }
        self.notch = nil
        self.state = .idle
    }

    // MARK: - Content

    func setMode(_ mode: OverlayMode) {
        // Always update NotchContentState to ensure UI stays in sync
        // (can get out of sync during show/hide transitions)
        let normalized = mode.normalized
        self.currentMode = normalized
        NotchContentState.shared.mode = normalized
        self.syncPromptPickerMode(for: normalized)
    }

    func switchLiveOverlayMode(to promptMode: SettingsStore.PromptMode) {
        guard !NotchContentState.shared.isProcessing else { return }
        switch promptMode.normalized {
        case .dictate:
            self.setMode(.dictation)
        case .edit:
            self.setMode(.edit)
        case .write, .rewrite:
            self.setMode(.edit)
        }
    }

    func updateTranscriptionText(_ text: String) {
        // Older pipeline code posts status words as transcript text. Treat them as phases
        // so they render as status (and the transcript itself stays intact).
        if let phase = Self.legacyStatusPhase(for: text) {
            self.present(phase)
            return
        }
        NotchContentState.shared.updateTranscription(text)
    }

    private static func legacyStatusPhase(for text: String) -> OverlayPhase? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "…", with: "...")
        switch normalized {
        case "Transcribing...": return .transcribing
        case "Refining...", "Reprocessing...", "Thinking...", "Thinking…", "Working...": return .refining
        default: return nil
        }
    }

    /// Updates what the overlay communicates and announces it to VoiceOver.
    /// Pipeline code reports phases here; the overlay views decide how to render them.
    func present(_ phase: OverlayPhase) {
        guard NotchContentState.shared.phase != phase else { return }
        NotchContentState.shared.setPhase(phase)
        if phase != .idle {
            phase.announce()
        }

        guard phase.isTerminal, !self.isCommandOutputExpanded else { return }
        self.settleHideTask?.cancel()
        self.settleHideTask = nil

        if self.isOverlayVisible {
            // Leave on our own once the outcome has been readable for the dwell.
            self.scheduleDeferredHide(after: Motion.outcomeDwell)
        } else if Self.shouldResurface(phase) {
            self.resurface(for: phase)
        }
    }

    /// Problems must be seen even if the overlay already left; plain success need not.
    private static func shouldResurface(_ phase: OverlayPhase) -> Bool {
        switch phase {
        case .failed: return true
        case let .done(outcome): return !outcome.isSuccess || outcome == .copied
        default: return false
        }
    }

    private func resurface(for phase: OverlayPhase) {
        let publisher = Empty<CGFloat, Never>().eraseToAnyPublisher()
        self.showSession(audioLevelPublisher: publisher, mode: self.currentMode, startsListening: false)
        self.scheduleDeferredHide(after: Motion.outcomeDwell)
    }

    func setProcessing(_ processing: Bool) {
        NotchContentState.shared.setProcessing(processing)
        if processing, !NotchContentState.shared.phase.isWorking {
            // Legacy callers signal work without a phase. Callers that also post a
            // status string ("Transcribing...") do so right after this call, so derive
            // the phase on the next turn of the run loop to avoid announcing it twice.
            DispatchQueue.main.async { [weak self] in
                guard NotchContentState.shared.isProcessing, !NotchContentState.shared.phase.isWorking else { return }
                self?.present(.refining)
            }
        }

        // If expanded command output is showing, don't mess with regular notch
        if self.isCommandOutputExpanded {
            return
        }

        if processing {
            self.cancelPendingHides()
        }

        // The bottom overlay renders from NotchContentState; nothing else to do.
        if self.isBottomOverlayVisible {
            return
        }

        if processing {
            // If notch isn't visible, re-show it for processing state
            if self.state == .idle || self.state == .hiding {
                // Use stored publisher or create empty one
                let publisher = self.lastAudioPublisher ?? Empty<CGFloat, Never>().eraseToAnyPublisher()
                self.show(audioLevelPublisher: publisher, mode: self.currentMode)
            }
        }
    }

    // MARK: - Expanded Command Output

    /// Show expanded command output notch
    func showExpandedCommandOutput() {
        // Hide regular notch first if visible
        if self.notch != nil {
            self.hideNow()
        }

        // Wait a bit for cleanup
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            await self?.showExpandedCommandOutputInternal()
        }
    }

    private func showExpandedCommandOutputInternal() async {
        guard self.commandOutputState == .idle else { return }

        self.commandOutputGeneration &+= 1
        let currentGeneration = self.commandOutputGeneration

        self.commandOutputState = .showing
        self.isCommandOutputExpanded = true

        // Update content state
        NotchContentState.shared.mode = .command
        NotchContentState.shared.isExpandedForCommandOutput = true

        let screen = OverlayScreenResolver.targetScreen(pid: NotchContentState.shared.recordingTargetPID)
        let maxHeight = (screen?.visibleFrame.height ?? 800) * 0.45

        let newNotch = DynamicNotch(hoverBehavior: [], style: .auto) {
            NotchCommandOutputExpandedView(
                maxHeight: maxHeight,
                onDismiss: { [weak self] in
                    Task { @MainActor in
                        self?.hideExpandedCommandOutput()
                        self?.onCommandOutputDismiss?()
                    }
                },
                onSubmit: { [weak self] text in
                    await self?.onCommandFollowUp?(text)
                },
                onNewChat: { [weak self] in
                    Task { @MainActor in
                        self?.onNewChat?()
                        // Refresh recent chats in notch state
                        NotchContentState.shared.refreshRecentChats()
                    }
                },
                onSwitchChat: { [weak self] chatID in
                    Task { @MainActor in
                        self?.onSwitchChat?(chatID)
                        // Refresh recent chats in notch state
                        NotchContentState.shared.refreshRecentChats()
                    }
                },
                onClearChat: { [weak self] in
                    Task { @MainActor in
                        self?.onClearChat?()
                    }
                }
            )
        }

        self.commandOutputNotch = newNotch

        if let screen {
            await newNotch.expand(on: screen)
        } else {
            await newNotch.expand()
        }

        guard self.commandOutputGeneration == currentGeneration else { return }
        self.commandOutputState = .visible
    }

    private func syncPromptPickerMode(for mode: OverlayMode) {
        switch mode {
        case .dictation:
            NotchContentState.shared.promptPickerMode = .dictate
        case .edit, .write, .rewrite:
            NotchContentState.shared.promptPickerMode = .edit
        case .command:
            break
        }
    }

    /// Hide expanded command output notch - force close regardless of hover state
    func hideExpandedCommandOutput() {
        self.commandOutputGeneration &+= 1
        let currentGeneration = self.commandOutputGeneration

        // Force cleanup state immediately
        self.isCommandOutputExpanded = false
        NotchContentState.shared.collapseCommandOutput()

        guard self.commandOutputState == .visible || self.commandOutputState == .showing,
              let currentNotch = commandOutputNotch
        else {
            self.commandOutputState = .idle
            return
        }

        self.commandOutputState = .hiding

        // Store reference and nil out immediately to prevent hover from keeping it alive
        let notchToHide = currentNotch
        self.commandOutputNotch = nil

        Task { [weak self] in
            // Try to hide gracefully, but we've already removed our reference
            await notchToHide.hide()
            guard let self = self, self.commandOutputGeneration == currentGeneration else { return }
            self.commandOutputState = .idle
        }
    }

    /// Toggle expanded command output (for hotkey handling)
    func toggleExpandedCommandOutput() {
        if self.isCommandOutputExpanded {
            self.hideExpandedCommandOutput()
        } else if NotchContentState.shared.commandConversationHistory.isEmpty == false {
            // Only show if there's history to show
            self.showExpandedCommandOutput()
        }
    }

    /// Check if any notch (regular or expanded) is visible
    var isAnyNotchVisible: Bool {
        return self.state == .visible || self.state == .showing || self.isCommandOutputExpanded
    }

    /// Update audio publisher for expanded notch (when recording starts within it)
    func updateAudioPublisher(_ publisher: AnyPublisher<CGFloat, Never>) {
        self.lastAudioPublisher = publisher
        self.currentAudioPublisher = publisher
        OverlayAudioMeter.shared.attach(publisher)
    }
}
