//
//  OverlayMenus.swift
//  SayIt
//
//  Click-to-open pop-up menus for the recording overlays (mode, prompt, actions).
//  One controller serves both overlay styles. Menus open in their own child panel,
//  outside the overlay, so they never cover the transcript.
//

import AppKit
import SwiftUI

enum OverlayMenuKind: Equatable {
    case mode
    case prompt(SettingsStore.PromptMode)
    case actions
}

enum OverlayMenuDirection {
    /// Opens above the anchor (bottom overlay).
    case above
    /// Opens below the anchor (notch overlay).
    case below
}

// MARK: - Controller

@MainActor
final class OverlayMenuController {
    static let shared = OverlayMenuController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var anchorInScreen: CGRect = .zero
    private weak var parentWindow: NSWindow?
    private var direction: OverlayMenuDirection = .above
    private var maxWidth: CGFloat = 240
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    private(set) var openKind: OverlayMenuKind?

    var isOpen: Bool {
        self.openKind != nil && self.panel?.isVisible == true
    }

    private static let gap: CGFloat = Space.xs
    private static let screenInset: CGFloat = Space.sm

    private init() {}

    /// Opens `kind` anchored to `anchor` (screen coordinates), or closes it if it is
    /// already the open menu.
    func toggle(
        _ kind: OverlayMenuKind,
        anchor: CGRect,
        parent: NSWindow?,
        direction: OverlayMenuDirection,
        maxWidth: CGFloat = 240
    ) {
        if self.openKind == kind, self.isOpen {
            self.hide()
            return
        }
        guard anchor.width > 0, anchor.height > 0 else { return }
        self.anchorInScreen = anchor
        self.parentWindow = parent
        self.direction = direction
        self.maxWidth = max(maxWidth, 160)
        self.openKind = kind
        self.present()
    }

    func hide() {
        self.openKind = nil
        self.removeMouseMonitors()
        guard let panel = self.panel, panel.isVisible else { return }
        if let parent = panel.parent {
            parent.removeChildWindow(panel)
        }
        panel.orderOut(nil)
    }

    private func present() {
        guard let kind = self.openKind else { return }
        let panel = self.panel ?? self.makePanel()
        self.panel = panel

        let content = OverlayMenuView(kind: kind, maxWidth: self.maxWidth) { [weak self] in
            self?.hide()
        }
        .sayItOverlayTheme()

        if let hostingView = self.hostingView {
            hostingView.rootView = AnyView(content)
        } else {
            let hostingView = NSHostingView(rootView: AnyView(content))
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = .clear
            panel.contentView = hostingView
            self.hostingView = hostingView
        }

        if let parent = self.parentWindow {
            panel.level = NSWindow.Level(rawValue: max(parent.level.rawValue, NSWindow.Level.floating.rawValue))
            if panel.parent !== parent {
                panel.parent?.removeChildWindow(panel)
                parent.addChildWindow(panel, ordered: .above)
            }
        }

        self.layout(panel)

        let reduceMotion = Motion.prefersReducedMotion
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.quick
            context.timingFunction = reduceMotion ? OverlayWindowMotion.fade : OverlayWindowMotion.enter
            panel.animator().alphaValue = 1
        }
        self.installMouseMonitors()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        return panel
    }

    private func layout(_ panel: NSPanel) {
        guard let hostingView = self.hostingView else { return }
        let size = hostingView.fittingSize
        guard size.width > 0, size.height > 0 else { return }

        var origin = CGPoint(
            x: self.anchorInScreen.midX - size.width / 2,
            y: self.direction == .above
                ? self.anchorInScreen.maxY + Self.gap
                : self.anchorInScreen.minY - Self.gap - size.height
        )

        let screen = self.parentWindow?.screen
            ?? NSScreen.screens.first { $0.frame.contains(CGPoint(x: self.anchorInScreen.midX, y: self.anchorInScreen.midY)) }
            ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + Self.screenInset), visible.maxX - size.width - Self.screenInset)
            origin.y = min(max(origin.y, visible.minY + Self.screenInset), visible.maxY - size.height - Self.screenInset)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    private func installMouseMonitors() {
        if self.localMouseMonitor == nil {
            self.localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
                let point = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? NSEvent.mouseLocation
                MainActor.assumeIsolated {
                    OverlayMenuController.shared.dismissIfNeeded(for: point)
                }
                return event
            }
        }
        if self.globalMouseMonitor == nil {
            self.globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
                let point = NSEvent.mouseLocation
                MainActor.assumeIsolated {
                    OverlayMenuController.shared.dismissIfNeeded(for: point)
                }
            }
        }
    }

    private func removeMouseMonitors() {
        if let monitor = self.localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            self.localMouseMonitor = nil
        }
        if let monitor = self.globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            self.globalMouseMonitor = nil
        }
    }

    /// Clicking anywhere outside the menu and its anchor closes the menu.
    func dismissIfNeeded(for screenPoint: CGPoint) {
        guard self.isOpen else { return }
        let insideMenu = self.panel?.frame.contains(screenPoint) ?? false
        let insideAnchor = self.anchorInScreen.contains(screenPoint)
        if !insideMenu, !insideAnchor {
            self.hide()
        }
    }
}

// MARK: - Menu Content

struct OverlayMenuView: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var contentState = NotchContentState.shared
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var historyStore = TranscriptionHistoryStore.shared

    let kind: OverlayMenuKind
    let maxWidth: CGFloat
    let onDismiss: () -> Void

    private static let minWidth: CGFloat = 180

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            switch self.kind {
            case .mode:
                self.modeMenu
            case let .prompt(promptMode):
                self.promptMenu(promptMode)
            case .actions:
                self.actionsMenu
            }
        }
        .padding(Space.xs)
        .frame(minWidth: Self.minWidth, maxWidth: self.maxWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(self.theme.overlay.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(self.theme.overlay.hairline, lineWidth: 1)
        )
    }

    // MARK: - Mode

    @ViewBuilder
    private var modeMenu: some View {
        self.modeRow(.dictation)
        self.modeRow(.edit)
        OverlayMenuDivider()
        self.modeRow(.command)
    }

    private func modeRow(_ mode: OverlayMode) -> some View {
        let isSelected = self.contentState.mode.normalized == mode
        return OverlayMenuRow(
            title: mode.displayName,
            systemImage: mode.symbolName,
            shortcut: OverlayShortcutResolver.shortcutDisplay(for: mode, settings: self.settings),
            isSelected: isSelected
        ) {
            guard !self.contentState.isProcessing else { return }
            self.contentState.onOverlayModeSwitchRequested?(mode)
            self.onDismiss()
        }
    }

    // MARK: - Prompt

    @ViewBuilder
    private func promptMenu(_ promptMode: SettingsStore.PromptMode) -> some View {
        let selectedID = self.settings.selectedPromptID(for: promptMode)
        let profiles = self.settings.promptProfiles(for: promptMode)

        OverlayMenuRow(title: "Default", isSelected: selectedID == nil) {
            self.settings.setSelectedPromptID(nil, for: promptMode)
            self.restoreTypingTarget()
            self.onDismiss()
        }

        if !profiles.isEmpty {
            OverlayMenuDivider()
            ForEach(profiles) { profile in
                OverlayMenuRow(
                    title: profile.name.isEmpty ? "Untitled" : profile.name,
                    isSelected: selectedID == profile.id
                ) {
                    self.settings.setSelectedPromptID(profile.id, for: promptMode)
                    self.restoreTypingTarget()
                    self.onDismiss()
                }
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionsMenu: some View {
        let latest = self.historyStore.entries.first
        let idle = !self.contentState.isProcessing
        let hasText = latest.map {
            !($0.processedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } ?? false
        let canUndo = latest.map {
            $0.wasAIProcessed && !$0.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? false

        OverlayMenuRow(title: "Reprocess Last Dictation", systemImage: "arrow.clockwise") {
            self.contentState.onReprocessLastRequested?()
            self.onDismiss()
        }
        .disabled(!(idle && latest != nil))

        OverlayMenuRow(title: "Copy Last Dictation", systemImage: "doc.on.doc") {
            self.contentState.onCopyLastRequested?()
            self.onDismiss()
        }
        .disabled(!(idle && hasText))

        OverlayMenuDivider()

        OverlayMenuRow(title: "Undo AI Enhancement", systemImage: "arrow.uturn.backward") {
            self.contentState.onUndoLastAIRequested?()
            self.onDismiss()
        }
        .disabled(!(idle && canUndo))
    }

    private func restoreTypingTarget() {
        let pid = NotchContentState.shared.recordingTargetPID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let pid { _ = TypingService.activateApp(pid: pid) }
        }
    }
}

// MARK: - Rows

private struct OverlayMenuRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    let title: String
    var systemImage: String?
    var shortcut: String = ""
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: Space.sm) {
                Image(systemName: "checkmark")
                    .font(AppFont.Overlay.icon)
                    .foregroundStyle(self.theme.overlay.primaryText)
                    .opacity(self.isSelected ? 1 : 0)
                    .accessibilityHidden(true)
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(AppFont.Overlay.icon)
                        .foregroundStyle(self.theme.overlay.secondaryText)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                }
                Text(self.title)
                    .font(AppFont.Overlay.menuRow)
                    .foregroundStyle(self.theme.overlay.primaryText)
                    .lineLimit(1)
                Spacer(minLength: Space.md)
                if !self.shortcut.isEmpty {
                    OverlayKeyCap(text: self.shortcut)
                }
            }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs + Space.xxs)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(self.isHovered && self.isEnabled ? self.theme.overlay.surfaceHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(self.isEnabled ? 1 : 0.45)
        .onHover { self.isHovered = $0 }
        .motion(Motion.snappy, value: self.isHovered)
        .accessibilityAddTraits(self.isSelected ? .isSelected : [])
    }
}

private struct OverlayMenuDivider: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Rectangle()
            .fill(self.theme.overlay.hairline)
            .frame(height: 1)
            .padding(.vertical, Space.xxs)
            .padding(.horizontal, Space.sm)
    }
}

// MARK: - Shortcut Display

enum OverlayShortcutResolver {
    static func shortcutDisplay(for mode: OverlayMode, settings: SettingsStore = .shared) -> String {
        switch mode.normalized {
        case .dictation:
            return settings.hotkeyShortcut.displayString
        case .edit, .write, .rewrite:
            return settings.rewriteModeHotkeyShortcut.displayString
        case .command:
            return settings.commandModeHotkeyShortcut.displayString
        }
    }
}

// MARK: - Anchor Reader

/// Reports a view's frame in screen coordinates (and its window) so menus can be
/// anchored to overlay controls.
struct OverlayAnchorReader: NSViewRepresentable {
    let onChange: (CGRect, NSWindow?) -> Void

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.onChange = self.onChange
        return view
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        nsView.onChange = self.onChange
        nsView.report()
    }

    final class AnchorView: NSView {
        var onChange: ((CGRect, NSWindow?) -> Void)?
        private var lastFrame: CGRect = .null
        private weak var lastWindow: NSWindow?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            self.observeWindow()
            self.report(force: true)
        }

        override func layout() {
            super.layout()
            self.report()
        }

        deinit {
            self.observers.forEach { NotificationCenter.default.removeObserver($0) }
        }

        private func observeWindow() {
            self.observers.forEach { NotificationCenter.default.removeObserver($0) }
            self.observers.removeAll()
            guard let window = self.window else { return }
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
                self.observers.append(
                    NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.report() }
                    }
                )
            }
        }

        func report(force: Bool = false) {
            guard let window = self.window else {
                if force || !self.lastFrame.isNull {
                    self.lastFrame = .null
                    self.lastWindow = nil
                    self.onChange?(.zero, nil)
                }
                return
            }
            let frame = window.convertToScreen(self.convert(self.bounds, to: nil))
            let changed = self.lastFrame.isNull
                || abs(frame.minX - self.lastFrame.minX) > 0.5
                || abs(frame.minY - self.lastFrame.minY) > 0.5
                || abs(frame.width - self.lastFrame.width) > 0.5
                || abs(frame.height - self.lastFrame.height) > 0.5
            guard force || changed || self.lastWindow !== window else { return }
            self.lastFrame = frame
            self.lastWindow = window
            self.onChange?(frame, window)
        }
    }
}
