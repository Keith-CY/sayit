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
        LiveCaptionContent(
            state: self.service.viewState,
            onToggleMicrophone: { self.service.setMicrophoneEnabled(self.service.viewState.microphone == .off) },
            onClose: { self.service.stop() }
        )
        .sayItOverlayTheme()
    }
}

struct LiveCaptionContent: View {
    @Environment(\.theme) private var theme
    let state: LiveCaptionViewState
    var onToggleMicrophone: () -> Void = {}
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
            Label("Mac Audio", systemImage: Self.glyph(for: .macAudio))
                .labelStyle(.titleAndIcon)
            Spacer(minLength: Space.sm)
            if self.state.phase == .listening {
                MicrophoneToggle(state: self.state.microphone, action: self.onToggleMicrophone)
            }
            IconButton("Turn Off Live Captions", systemName: "xmark", size: 22, action: self.onClose)
        }
        .font(AppFont.Overlay.label)
        .foregroundStyle(self.theme.overlay.tertiaryText)
    }

    static func glyph(for source: LiveCaptionSource) -> String {
        switch source {
        case .macAudio: return "speaker.wave.2"
        case .microphone: return "mic"
        }
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
            if !self.state.rows.isEmpty {
                self.captions
            } else if self.state.showsSilenceHint {
                self.message(
                    "Nothing has played yet",
                    detail: "If something is playing, allow SayIt in Screen & System Audio Recording.",
                    settingsButton: true
                )
            } else if self.state.microphone == .on {
                self.message(
                    "Listening to your Mac and your microphone…",
                    detail: "Captions appear here when someone speaks.",
                    pulsing: true
                )
            } else {
                self.message(
                    "Listening to your Mac’s audio…",
                    detail: "Captions appear here when something with speech plays.",
                    pulsing: true
                )
            }
        }
    }

    private var captions: some View {
        let rows = Array(self.state.rows.suffix(LiveCaptionLayout.visibleLines))
        // Mark where each line came from once the microphone is in the mix.
        let showsSources = self.state.microphone == .on || rows.contains { $0.source == .microphone }

        return VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    if showsSources {
                        Image(systemName: Self.glyph(for: row.source))
                            .font(AppFont.LiveCaption.sourceIcon)
                            .foregroundStyle(self.theme.overlay.tertiaryText)
                            .frame(width: Space.lg)
                            .accessibilityLabel(row.source == .microphone ? "You" : "Mac Audio")
                    }
                    self.captionText(row)
                }
                .motionTransition()
            }
        }
        .font(AppFont.LiveCaption.text)
        .lineSpacing(Space.xxs)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .motion(Motion.state, value: rows.map(\.id))
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
    private func captionText(_ row: LiveCaptionViewState.Row) -> some View {
        let ink = row.isDraft ? self.theme.overlay.secondaryText : self.theme.overlay.primaryText
        return (Text(row.text).foregroundStyle(ink) + Text(row.formingTail).foregroundStyle(self.theme.overlay.tertiaryText))
            .contentTransition(.opacity)
            .motion(Motion.state, value: row.text)
            .motion(Motion.state, value: row.isDraft)
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

/// Turns the microphone source on and off. Off by default: an open microphone puts
/// AirPods in call mode, which lowers playback quality.
private struct MicrophoneToggle: View {
    let state: LiveCaptionViewState.Microphone
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Label("Microphone", systemImage: self.glyph)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(LiveCaptionChipStyle(isOn: self.state == .on, isWarning: self.state == .unavailable))
        .help(self.help)
        .accessibilityValue(self.state == .off ? "Off" : "On")
    }

    private var glyph: String {
        switch self.state {
        case .off: return "mic.slash"
        case .on: return "mic"
        case .unavailable: return "exclamationmark.triangle"
        }
    }

    private var help: String {
        switch self.state {
        case .off: return "Also caption what you say"
        case .on: return "Stop captioning your microphone"
        case .unavailable: return "SayIt can’t use the microphone. Allow it in Privacy & Security → Microphone, then turn it on again."
        }
    }
}

/// Overlay chip with an on state (raised fill, full ink) and a warning state.
private struct LiveCaptionChipStyle: ButtonStyle {
    let isOn: Bool
    let isWarning: Bool

    func makeBody(configuration: Configuration) -> some View {
        Chip(configuration: configuration, isOn: self.isOn, isWarning: self.isWarning)
    }

    private struct Chip: View {
        @Environment(\.theme) private var theme
        @State private var isHovered = false
        let configuration: ButtonStyle.Configuration
        let isOn: Bool
        let isWarning: Bool

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            let active = self.isHovered || self.configuration.isPressed
            self.configuration.label
                .font(AppFont.Overlay.label)
                .foregroundStyle(self.foreground)
                .lineLimit(1)
                .padding(.horizontal, Space.sm)
                .padding(.vertical, Space.xs)
                .background(shape.fill(active ? self.theme.overlay.surfaceHover : self.isOn ? self.theme.overlay.surfaceRaised : self.theme.overlay.surface))
                .overlay(shape.strokeBorder(self.theme.overlay.hairline, lineWidth: 1))
                .contentShape(shape)
                .onHover { self.isHovered = $0 }
                .motion(Motion.snappy, value: active)
                .motion(Motion.state, value: self.isOn)
        }

        private var foreground: Color {
            if self.isWarning { return self.theme.overlay.warning }
            return self.isOn ? self.theme.overlay.primaryText : self.theme.overlay.secondaryText
        }
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
