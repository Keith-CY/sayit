//
//  BottomOverlayView.swift
//  SayIt
//
//  Bottom overlay for transcription (alternative to notch overlay)
//

import AppKit
import Combine
import SwiftUI

// MARK: - Bottom Overlay Window Controller

@MainActor
final class BottomOverlayWindowController {
    static let shared = BottomOverlayWindowController()

    private var window: NSPanel?
    private var targetScreen: NSScreen?
    /// Guards fade-out completions against a show that started in the meantime.
    private var visibilityGeneration: UInt64 = 0

    private init() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name("OverlayOffsetChanged"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.positionWindow()
            }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("OverlaySizeChanged"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshSizeForContent()
            }
        }
    }

    /// Shows the overlay on `screen` (the target app's display), rising into place.
    func show(mode: OverlayMode, on screen: NSScreen?) {
        self.visibilityGeneration &+= 1
        OverlayMenuController.shared.hide()

        // Update mode in content state
        NotchContentState.shared.mode = mode
        switch mode {
        case .dictation: NotchContentState.shared.promptPickerMode = .dictate
        case .edit, .write, .rewrite: NotchContentState.shared.promptPickerMode = .edit
        case .command: break
        }
        NotchContentState.shared.updateTranscription("")

        if self.window == nil {
            self.createWindow()
        }
        guard let window = self.window else { return }

        self.targetScreen = screen
        self.updateSize()
        let finalOrigin = self.targetOrigin() ?? window.frame.origin
        let reduceMotion = Motion.prefersReducedMotion

        // Back-to-back sessions: already on screen, so just settle into place.
        if window.isVisible, window.alphaValue > 0.99 {
            window.setFrameOrigin(finalOrigin)
            return
        }

        window.alphaValue = 0
        window.setFrameOrigin(
            reduceMotion ? finalOrigin : NSPoint(x: finalOrigin.x, y: finalOrigin.y - OverlayWindowMotion.enterOffset)
        )
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? Motion.quick : Motion.standard
            context.timingFunction = reduceMotion ? OverlayWindowMotion.fade : OverlayWindowMotion.enter
            window.animator().alphaValue = 1
            if !reduceMotion {
                window.animator().setFrame(NSRect(origin: finalOrigin, size: window.frame.size), display: true)
            }
        }
    }

    func hide() {
        self.visibilityGeneration &+= 1
        let generation = self.visibilityGeneration
        OverlayMenuController.shared.hide()
        NotchContentState.shared.setProcessing(false)

        guard let window = self.window, window.isVisible else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.quick
            context.timingFunction = Motion.prefersReducedMotion ? OverlayWindowMotion.fade : OverlayWindowMotion.exit
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.visibilityGeneration == generation else { return }
                window.orderOut(nil)
                NotchContentState.shared.targetAppIcon = nil
            }
        }
    }

    func setProcessing(_ processing: Bool) {
        NotchContentState.shared.setProcessing(processing)
    }

    /// Re-measures the overlay (its size only changes with the overlay size setting).
    func refreshSizeForContent() {
        self.updateSize()
        self.positionWindow()
    }

    private func updateSize() {
        guard let window = self.window, let hostingView = window.contentView else { return }
        let newSize = hostingView.fittingSize
        let current = window.frame.size
        guard abs(current.width - newSize.width) > 0.5 || abs(current.height - newSize.height) > 0.5 else { return }
        // Resize from the current origin; `positionWindow` re-centres afterwards.
        window.setFrame(NSRect(origin: window.frame.origin, size: newSize), display: false)
    }

    private func createWindow() {
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
        panel.hasShadow = false // SwiftUI handles shadow
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        let hostingView = NSHostingView(rootView: BottomOverlayView())
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: fittingSize)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        panel.setContentSize(fittingSize)
        panel.contentView = hostingView

        self.window = panel
    }

    private func targetOrigin() -> NSPoint? {
        guard let window = self.window,
              let screen = self.targetScreen ?? window.screen ?? NSScreen.main
        else { return nil }

        let visibleFrame = screen.visibleFrame
        let windowSize = window.frame.size
        let x = screen.frame.midX - windowSize.width / 2

        // Keep the overlay inside the visible area (above the Dock, below the menu bar).
        let rawY = visibleFrame.minY + CGFloat(SettingsStore.shared.overlayBottomOffset)
        let minY = visibleFrame.minY + Space.sm
        let maxY = visibleFrame.maxY - windowSize.height - Space.xxxl
        return NSPoint(x: x, y: max(min(rawY, maxY), minY))
    }

    private func positionWindow() {
        guard let window = self.window, let origin = self.targetOrigin() else { return }
        // Apply directly to avoid implicit frame animations.
        window.setFrameOrigin(origin)
    }
}

// MARK: - Bottom Overlay SwiftUI View

/// Root of the bottom overlay. Applies the always-dark overlay theme.
struct BottomOverlayView: View {
    var body: some View {
        BottomOverlayContent()
            .sayItOverlayTheme()
    }
}

struct BottomOverlayContent: View {
    @ObservedObject private var contentState = NotchContentState.shared
    @ObservedObject private var appServices = AppServices.shared
    @ObservedObject private var activeAppMonitor = ActiveAppMonitor.shared
    @ObservedObject private var historyStore = TranscriptionHistoryStore.shared
    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.theme) private var theme

    @State private var modeChipAnchor = OverlayAnchor()
    @State private var promptChipAnchor = OverlayAnchor()
    @State private var actionsChipAnchor = OverlayAnchor()

    /// Renders a specific size regardless of the setting (snapshot tests).
    let sizeOverride: SettingsStore.OverlaySize?

    init(sizeOverride: SettingsStore.OverlaySize? = nil) {
        self.sizeOverride = sizeOverride
    }

    private var overlaySize: SettingsStore.OverlaySize {
        self.sizeOverride ?? self.settings.overlaySize
    }

    /// Overlay geometry per size setting. Heights are fixed (the transcript reserves its
    /// lines), so the window never resizes while text streams in.
    struct LayoutConstants {
        let width: CGFloat
        let hPadding: CGFloat
        let vPadding: CGFloat
        let iconSize: CGFloat
        let meter: LevelMeterStyle
        let transcriptFont: Font
        let transcriptLines: Int
        let statusFont: Font
        let showsTopControls: Bool
        let showsKeyCap: Bool
        let showsChipTitles: Bool

        static func get(for size: SettingsStore.OverlaySize) -> LayoutConstants {
            switch size {
            case .small:
                return LayoutConstants(
                    width: 300,
                    hPadding: Space.md,
                    vPadding: Space.sm,
                    iconSize: 16,
                    meter: .small,
                    transcriptFont: AppFont.Overlay.transcriptCompact,
                    transcriptLines: 1,
                    statusFont: AppFont.Overlay.status,
                    showsTopControls: false,
                    showsKeyCap: false,
                    showsChipTitles: false
                )
            case .medium:
                return LayoutConstants(
                    width: 380,
                    hPadding: Space.lg,
                    vPadding: Space.md,
                    iconSize: 20,
                    meter: .medium,
                    transcriptFont: AppFont.Overlay.transcript,
                    transcriptLines: 2,
                    statusFont: AppFont.Overlay.status,
                    showsTopControls: true,
                    showsKeyCap: true,
                    showsChipTitles: false
                )
            case .large:
                return LayoutConstants(
                    width: 600,
                    hPadding: Space.xl,
                    vPadding: Space.lg,
                    iconSize: 24,
                    meter: .large,
                    transcriptFont: AppFont.Overlay.transcriptLarge,
                    transcriptLines: 4,
                    statusFont: AppFont.callout.weight(.semibold),
                    showsTopControls: true,
                    showsKeyCap: true,
                    showsChipTitles: true
                )
            }
        }
    }

    private var layout: LayoutConstants {
        LayoutConstants.get(for: self.overlaySize)
    }

    private var mode: OverlayMode {
        self.contentState.mode.normalized
    }

    private var phase: OverlayPhase {
        self.contentState.phase
    }

    /// Controls are locked while work is running or an outcome is showing.
    private var controlsLocked: Bool {
        self.phase.isWorking || self.phase.isTerminal || self.contentState.isProcessing
    }

    private var isModelLoading: Bool {
        let asr = self.appServices.asr
        return !asr.isAsrReady && (asr.isLoadingModel || asr.isDownloadingModel)
    }

    private var selectedPromptLabel: String {
        guard let promptMode = self.mode.promptMode else { return "" }
        if let profile = self.settings.selectedPromptProfile(for: promptMode) {
            let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Untitled" : name
        }
        return "Default"
    }

    var body: some View {
        VStack(spacing: Space.sm) {
            if self.layout.showsTopControls {
                self.controlsRow
            }
            self.panel
        }
        .frame(width: self.layout.width)
        .onChange(of: self.settings.overlaySize) { _, _ in
            BottomOverlayWindowController.shared.refreshSizeForContent()
        }
        .onChange(of: self.contentState.mode) { _, newMode in
            OverlayMenuController.shared.hide()
            switch newMode {
            case .dictation: self.contentState.promptPickerMode = .dictate
            case .edit, .write, .rewrite: self.contentState.promptPickerMode = .edit
            case .command: break
            }
        }
        .onChange(of: self.controlsLocked) { _, locked in
            if locked { OverlayMenuController.shared.hide() }
        }
        .onDisappear {
            OverlayMenuController.shared.hide()
        }
        .motion(Motion.state, value: self.contentState.mode)
    }

    // MARK: - Panel

    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
        return VStack(alignment: .leading, spacing: Space.sm) {
            OverlayTranscriptText(
                text: self.contentState.cachedPreviewText,
                font: self.layout.transcriptFont,
                lines: self.layout.transcriptLines,
                isDimmed: self.phase.isWorking
            )

            HStack(spacing: Space.md) {
                self.targetAppIcon

                OverlayIndicator(phase: self.phase, mode: self.mode, meterStyle: self.layout.meter)

                VStack(alignment: .leading, spacing: Space.xxs) {
                    OverlayStatusLabel(
                        phase: self.phase,
                        mode: self.mode,
                        font: self.layout.statusFont,
                        maxLines: self.overlaySize == .large ? 2 : 1
                    )

                    if self.isModelLoading, self.overlaySize != .small {
                        Label("Loading speech model…", systemImage: "hourglass")
                            .font(AppFont.Overlay.label)
                            .foregroundStyle(self.theme.overlay.warning)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: Space.sm)

                OverlayCancelControl(showsKeyCap: self.layout.showsKeyCap)
            }
        }
        .padding(.horizontal, self.layout.hPadding)
        .padding(.vertical, self.layout.vPadding)
        .background(shape.fill(self.theme.overlay.surface))
        .overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: [self.theme.overlay.hairline, self.theme.overlay.hairline.opacity(0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
        )
    }

    @ViewBuilder
    private var targetAppIcon: some View {
        let icon = self.contentState.targetAppIcon ?? self.activeAppMonitor.activeAppIcon
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: self.layout.iconSize, height: self.layout.iconSize)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
                .accessibilityHidden(true)
        } else if self.isModelLoading {
            ProgressView()
                .controlSize(.small)
                .frame(width: self.layout.iconSize, height: self.layout.iconSize)
                .accessibilityLabel("Loading speech model")
        }
    }

    // MARK: - Controls

    private var controlsRow: some View {
        HStack(spacing: Space.sm) {
            self.modeChip
            if self.mode.promptMode != nil {
                self.promptChip
            }
            Spacer(minLength: Space.xs)
            self.aiChip
            self.actionsChip
            if self.layout.showsChipTitles {
                IconButton("Open Settings", systemName: "gearshape", size: 24) {
                    OverlayMenuController.shared.hide()
                    self.contentState.onOpenPreferencesRequested?()
                }
            }
        }
        .padding(.horizontal, Space.xs)
    }

    private var modeChip: some View {
        Button {
            OverlayMenuController.shared.toggle(
                .mode,
                anchor: self.modeChipAnchor.frame,
                parent: self.modeChipAnchor.window,
                direction: .above
            )
        } label: {
            OverlayChipLabel(
                title: self.layout.showsChipTitles ? "Mode" : nil,
                value: self.mode.displayName,
                systemImage: nil
            )
        }
        .buttonStyle(OverlayChipButtonStyle())
        .background(self.anchorReader { self.modeChipAnchor = $0 })
        .disabled(self.controlsLocked)
        .accessibilityLabel("Mode: \(self.mode.displayName)")
        .accessibilityHint("Switch between Dictate, Edit and Command")
    }

    private var promptChip: some View {
        Button {
            guard let promptMode = self.mode.promptMode else { return }
            OverlayMenuController.shared.toggle(
                .prompt(promptMode),
                anchor: self.promptChipAnchor.frame,
                parent: self.promptChipAnchor.window,
                direction: .above
            )
        } label: {
            OverlayChipLabel(
                title: self.layout.showsChipTitles ? "Prompt" : nil,
                value: self.selectedPromptLabel
            )
        }
        .buttonStyle(OverlayChipButtonStyle())
        .background(self.anchorReader { self.promptChipAnchor = $0 })
        .disabled(self.controlsLocked)
        .accessibilityLabel("Prompt: \(self.selectedPromptLabel)")
        .accessibilityHint("Choose the prompt used for this dictation")
    }

    private var aiChip: some View {
        let isOn = self.settings.enableAIProcessing
        return Button {
            OverlayMenuController.shared.hide()
            self.contentState.onToggleAIProcessingRequested?()
        } label: {
            OverlayChipLabel(
                title: self.layout.showsChipTitles ? "AI Enhancement" : nil,
                value: self.layout.showsChipTitles ? (isOn ? "On" : "Off") : (isOn ? "AI On" : "AI Off"),
                systemImage: isOn ? "sparkles" : nil,
                showsChevron: false
            )
        }
        .buttonStyle(OverlayChipButtonStyle())
        .disabled(self.controlsLocked)
        .help("Turn AI Enhancement on or off for dictation")
        .accessibilityLabel("AI Enhancement")
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private var actionsChip: some View {
        let unavailable = self.historyStore.entries.isEmpty
        return Button {
            OverlayMenuController.shared.toggle(
                .actions,
                anchor: self.actionsChipAnchor.frame,
                parent: self.actionsChipAnchor.window,
                direction: .above
            )
        } label: {
            OverlayChipLabel(value: "Actions")
        }
        .buttonStyle(OverlayChipButtonStyle())
        .background(self.anchorReader { self.actionsChipAnchor = $0 })
        .disabled(unavailable || self.controlsLocked)
        .help(unavailable ? "No saved dictations yet" : "Reprocess, copy or restore your last dictation")
        .accessibilityLabel("Actions for Last Dictation")
    }

    private func anchorReader(_ update: @escaping (OverlayAnchor) -> Void) -> some View {
        OverlayAnchorReader { frame, window in
            update(OverlayAnchor(frame: frame, window: window))
        }
        .allowsHitTesting(false)
    }
}

/// Screen frame and window of an overlay control, for anchoring its menu.
struct OverlayAnchor: Equatable {
    var frame: CGRect = .zero
    weak var window: NSWindow?

    // Equatable so re-reporting the same frame does not trigger another view update.
    static func == (lhs: OverlayAnchor, rhs: OverlayAnchor) -> Bool {
        lhs.frame == rhs.frame && lhs.window === rhs.window
    }
}
