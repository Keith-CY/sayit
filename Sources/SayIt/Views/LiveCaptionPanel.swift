//
//  LiveCaptionPanel.swift
//  SayIt
//
//  Floating panel that shows Live Captions for the audio the Mac is playing.
//

import AppKit
import SwiftUI

// MARK: - Window controller

@MainActor
final class LiveCaptionPanelController {
    static let shared = LiveCaptionPanelController()

    private static let frameAutosaveName = "LiveCaptionsPanel"
    private var panel: NSPanel?
    /// Guards fade-out completions against a show that started in the meantime.
    private var visibilityGeneration: UInt64 = 0

    private init() {}

    func show() {
        self.visibilityGeneration &+= 1
        let panel = self.panel ?? self.makePanel()
        self.panel = panel

        let size = panel.contentView?.fittingSize ?? panel.frame.size
        var frame = NSRect(origin: panel.frame.origin, size: size)
        if !panel.setFrameUsingName(Self.frameAutosaveName) {
            frame.origin = self.defaultOrigin(for: size)
        } else {
            frame.origin = panel.frame.origin
        }
        let reduceMotion = Motion.prefersReducedMotion

        panel.alphaValue = 0
        panel.setFrame(
            reduceMotion ? frame : frame.offsetBy(dx: 0, dy: -OverlayWindowMotion.enterOffset),
            display: false
        )
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? Motion.quick : Motion.standard
            context.timingFunction = reduceMotion ? OverlayWindowMotion.fade : OverlayWindowMotion.enter
            panel.animator().alphaValue = 1
            if !reduceMotion {
                panel.animator().setFrame(frame, display: true)
            }
        }
    }

    func hide() {
        self.visibilityGeneration &+= 1
        let generation = self.visibilityGeneration
        guard let panel = self.panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.quick
            context.timingFunction = Motion.prefersReducedMotion ? OverlayWindowMotion.fade : OverlayWindowMotion.exit
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.visibilityGeneration == generation else { return }
                panel.orderOut(nil)
            }
        }
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
        panel.hasShadow = false // SwiftUI draws the shadow
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.setFrameAutosaveName(Self.frameAutosaveName)

        let hostingView = NSHostingView(rootView: LiveCaptionPanelView())
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        let size = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)
        panel.contentView = hostingView
        return panel
    }

    /// Centered, above where the bottom recording overlay appears.
    private func defaultOrigin(for size: CGSize) -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        let visible = screen.visibleFrame
        let y = visible.minY + CGFloat(SettingsStore.shared.overlayBottomOffset) + LiveCaptionLayout.clearanceAboveOverlay
        return NSPoint(x: visible.midX - size.width / 2, y: min(y, visible.maxY - size.height))
    }
}

// MARK: - Layout

enum LiveCaptionLayout {
    static let width: CGFloat = 620
    /// Three caption lines at `AppFont.LiveCaption.text`; the line above them shows only
    /// inside the top fade as it scrolls off.
    static let textAreaHeight: CGFloat = 88
    /// Lines rendered (more than fit, so the top one fades out instead of popping).
    static let visibleLines = 4
    /// Keeps the panel clear of the bottom recording overlay at its largest size.
    static let clearanceAboveOverlay: CGFloat = 200
    /// Height of the fade at the top edge of the text area.
    static let topFade: CGFloat = Space.xl
}

// MARK: - Views

/// Root of the panel. Always dark, like the recording overlay: it sits over video and
/// arbitrary content.
struct LiveCaptionPanelView: View {
    @ObservedObject private var service = LiveCaptionService.shared

    var body: some View {
        LiveCaptionContent(state: self.service.viewState) {
            self.service.stop()
        }
        .sayItOverlayTheme()
    }
}

struct LiveCaptionContent: View {
    @Environment(\.theme) private var theme
    let state: LiveCaptionViewState
    var onClose: () -> Void = {}

    private static let privacySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
        VStack(alignment: .leading, spacing: Space.md) {
            self.header
            self.content
                .frame(
                    maxWidth: .infinity,
                    minHeight: LiveCaptionLayout.textAreaHeight,
                    maxHeight: LiveCaptionLayout.textAreaHeight,
                    alignment: .bottomLeading
                )
        }
        .padding(.horizontal, Space.lg)
        .padding(.top, Space.md)
        .padding(.bottom, Space.lg)
        .frame(width: LiveCaptionLayout.width)
        .background(shape.fill(self.theme.overlay.surface))
        .overlay(shape.strokeBorder(self.theme.overlay.hairline, lineWidth: 1))
        .clipShape(shape)
        .shadow(color: self.theme.palette.shadow, radius: Space.lg, y: Space.xs)
        .padding(Space.xl) // room for the shadow inside the borderless window
        .modifier(WindowDragModifier())
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Space.sm) {
            Label("Live Captions", systemImage: "captions.bubble")
                .labelStyle(.titleAndIcon)
            Text("·")
                .accessibilityHidden(true)
            Label("Mac Audio", systemImage: "speaker.wave.2")
                .labelStyle(.titleAndIcon)
            Spacer(minLength: Space.sm)
            IconButton("Turn Off Live Captions", systemName: "xmark", size: 22, action: self.onClose)
        }
        .font(AppFont.Overlay.label)
        .foregroundStyle(self.theme.overlay.tertiaryText)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch self.state.phase {
        case .preparing:
            self.message("Getting Live Captions ready…", detail: nil, pulsing: true)
        case let .failed(failure):
            self.failure(failure)
        case .listening:
            if self.state.lines.isEmpty, self.state.volatileText.isEmpty {
                if self.state.showsSilenceHint {
                    self.message(
                        "Nothing has played yet",
                        detail: "If something is playing, allow SayIt in Screen & System Audio Recording.",
                        settingsButton: true
                    )
                } else {
                    self.message(
                        "Listening to your Mac’s audio…",
                        detail: "Captions appear here when something with speech plays.",
                        pulsing: true
                    )
                }
            } else {
                self.captions
            }
        }
    }

    private var captions: some View {
        let lines = Array(self.state.lines.suffix(LiveCaptionLayout.visibleLines))
        let lastID = lines.last?.id
        // Forming words continue the open line, or start their own after a closed one.
        let volatileOnOwnLine = lines.last.map { $0.state != .open } ?? true

        return VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(lines) { line in
                self.captionText(line, volatile: line.id == lastID && !volatileOnOwnLine ? self.state.volatileText : "")
                    .motionTransition()
            }
            if volatileOnOwnLine, !self.state.volatileText.isEmpty {
                Text(self.state.volatileText)
                    .foregroundStyle(self.theme.overlay.tertiaryText)
                    .motionTransition()
            }
        }
        .font(AppFont.LiveCaption.text)
        .lineSpacing(Space.xxs)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .motion(Motion.state, value: lines.map(\.id))
        // minHeight 0 lets the area be shorter than its lines, so older ones scroll off.
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .bottomLeading)
        .clipped()
        .mask(alignment: .top) {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: LiveCaptionLayout.topFade)
                Rectangle()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live Captions")
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// Settled words in full ink; words that may still change (Apple's draft, awaiting
    /// Qwen) one step quieter; the forming tail quieter still.
    private func captionText(_ line: LiveCaptionTranscript.Line, volatile: String) -> some View {
        let ink = line.isDraft ? self.theme.overlay.secondaryText : self.theme.overlay.primaryText
        let tail = volatile.isEmpty
            ? ""
            : String(LiveCaptionTranscript.join(line.text, volatile).dropFirst(line.text.count))
        return (Text(line.text).foregroundStyle(ink) + Text(tail).foregroundStyle(self.theme.overlay.tertiaryText))
            .contentTransition(.opacity)
            .motion(Motion.state, value: line.text)
            .motion(Motion.state, value: line.state)
    }

    // MARK: - Messages

    @ViewBuilder
    private func failure(_ failure: LiveCaptionFailure) -> some View {
        switch failure {
        case .cantHearMac:
            self.message(
                "SayIt can’t hear your Mac’s audio",
                detail: "Allow SayIt in Privacy & Security → Screen & System Audio Recording, then turn Live Captions on again.",
                settingsButton: true,
                isError: true
            )
        case .speechUnavailable:
            self.message(
                "Live Captions can’t start",
                detail: "The speech model for your language isn’t available. Check your internet connection, then turn Live Captions on again.",
                isError: true
            )
        }
    }

    private func message(
        _ title: String,
        detail: String?,
        pulsing: Bool = false,
        settingsButton: Bool = false,
        isError: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: isError ? "exclamationmark.triangle" : "waveform")
                .font(AppFont.Overlay.icon)
                .foregroundStyle(isError ? self.theme.overlay.warning : self.theme.overlay.secondaryText)
                .ambientPulse(isActive: pulsing)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title)
                    .font(AppFont.LiveCaption.message)
                    .foregroundStyle(self.theme.overlay.primaryText)
                if let detail {
                    Text(detail)
                        .font(AppFont.LiveCaption.detail)
                        .foregroundStyle(self.theme.overlay.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if settingsButton, let url = Self.privacySettingsURL {
                    Button("Open Privacy Settings") { NSWorkspace.shared.open(url) }
                        .buttonStyle(SayItButtonStyle(role: .secondary, size: .small))
                        .padding(.top, Space.xxs)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .contain)
    }
}

/// Lets the panel be dragged anywhere outside its controls.
private struct WindowDragModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.gesture(WindowDragGesture())
        } else {
            content
        }
    }
}
