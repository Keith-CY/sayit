//
//  OverlayComponents.swift
//  SayIt
//
//  Building blocks shared by the notch and bottom recording overlays
//  (docs/design/DESIGN.md §7–§8).
//

import AppKit
import Combine
import SwiftUI

// MARK: - Overlay Mode Presentation

extension OverlayMode {
    /// Write/Rewrite are presented as Edit.
    var normalized: OverlayMode {
        switch self {
        case .write, .rewrite: return .edit
        case .dictation, .edit, .command: return self
        }
    }

    var displayName: String {
        switch self.normalized {
        case .dictation: return "Dictate"
        case .edit, .write, .rewrite: return "Edit"
        case .command: return "Command"
        }
    }

    var symbolName: String {
        switch self.normalized {
        case .dictation: return "mic"
        case .edit, .write, .rewrite: return "pencil.line"
        case .command: return "terminal"
        }
    }

    /// Prompt profiles apply to Dictate and Edit only.
    var promptMode: SettingsStore.PromptMode? {
        switch self.normalized {
        case .dictation: return .dictate
        case .edit, .write, .rewrite: return .edit
        case .command: return nil
        }
    }
}

// MARK: - Audio Level Source

/// Audio level for the overlay meter. Kept separate from `NotchContentState` so level
/// ticks (tens per second) only re-render the meter, not the whole overlay.
@MainActor
final class OverlayAudioMeter: ObservableObject {
    static let shared = OverlayAudioMeter()

    @Published private(set) var level: CGFloat = 0
    private var subscription: AnyCancellable?

    private init() {}

    func attach(_ publisher: AnyPublisher<CGFloat, Never>) {
        self.subscription = publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.level = value
            }
    }

    func detach() {
        self.subscription = nil
        self.level = 0
    }

    /// Direct update, used by the expanded command overlay and by tests.
    func set(_ value: CGFloat) {
        self.level = value
    }
}

// MARK: - Level Meter

struct LevelMeterStyle: Equatable {
    let barCount: Int
    let barWidth: CGFloat
    let barSpacing: CGFloat
    let height: CGFloat

    var width: CGFloat {
        CGFloat(self.barCount) * self.barWidth + CGFloat(max(self.barCount - 1, 0)) * self.barSpacing
    }

    static let notch = LevelMeterStyle(barCount: 7, barWidth: 3, barSpacing: 3, height: 18)
    static let commandHeader = LevelMeterStyle(barCount: 5, barWidth: 3, barSpacing: 3, height: 16)
    static let small = LevelMeterStyle(barCount: 7, barWidth: 3, barSpacing: 3.5, height: 18)
    static let medium = LevelMeterStyle(barCount: 9, barWidth: 3.5, barSpacing: 4.5, height: 26)
    static let large = LevelMeterStyle(barCount: 11, barWidth: 5, barSpacing: 6, height: 40)
}

/// The overlay's single moving protagonist while listening.
///
/// Bars are fixed-size capsules scaled vertically (no layout per frame). The level is
/// smoothed with an attack/release envelope instead of random jitter, and the bar
/// profile is a fixed center-weighted curve. With Reduce Motion the bars keep their
/// height and the level is shown as opacity.
struct LevelMeter: View {
    let color: Color
    let style: LevelMeterStyle
    /// When false the meter rests flat (working and finished phases).
    var isLive: Bool = true

    @ObservedObject private var meter = OverlayAudioMeter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var envelope: CGFloat = 0
    @State private var threshold = LevelMeter.currentThreshold()

    private static let restScale: CGFloat = 0.2
    private static let attack: CGFloat = 0.65
    private static let release: CGFloat = 0.2

    var body: some View {
        HStack(alignment: .center, spacing: self.style.barSpacing) {
            ForEach(0..<self.style.barCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(self.color)
                    .frame(width: self.style.barWidth, height: self.style.height)
                    .scaleEffect(x: 1, y: self.scale(for: index), anchor: .center)
                    .opacity(self.reduceMotion ? 0.35 + 0.65 * Double(self.envelope) : 1)
            }
        }
        .frame(width: self.style.width, height: self.style.height)
        .drawingGroup()
        .accessibilityHidden(true)
        .onAppear {
            if self.isLive { self.envelope = self.normalized(self.meter.level) }
        }
        .onChange(of: self.meter.level) { _, raw in
            guard self.isLive else { return }
            self.advance(towards: self.normalized(raw))
        }
        .onChange(of: self.isLive) { _, live in
            guard !live else { return }
            withMotion(Motion.exit) { self.envelope = 0 }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let latest = Self.currentThreshold()
            if latest != self.threshold { self.threshold = latest }
        }
    }

    private func scale(for index: Int) -> CGFloat {
        if self.reduceMotion { return 0.5 }
        let rest = Self.restScale
        return rest + (1 - rest) * self.envelope * Self.profile(index: index, count: self.style.barCount)
    }

    /// Center-weighted bar profile: 1.0 in the middle, ~0.55 at the edges.
    static func profile(index: Int, count: Int) -> CGFloat {
        guard count > 1 else { return 1 }
        let center = CGFloat(count - 1) / 2
        let distance = abs(CGFloat(index) - center) / max(center, 1)
        return 0.55 + 0.45 * cos(distance * .pi / 2)
    }

    private func normalized(_ raw: CGFloat) -> CGFloat {
        let level = min(max(raw, 0), 1)
        guard level > self.threshold else { return 0 }
        let span = max(1 - self.threshold, 0.05)
        return pow(min((level - self.threshold) / span, 1), 0.6)
    }

    private func advance(towards target: CGFloat) {
        let coefficient = target > self.envelope ? Self.attack : Self.release
        let next = self.envelope + (target - self.envelope) * coefficient
        withMotion(Motion.meter) { self.envelope = next }
    }

    private static func currentThreshold() -> CGFloat {
        min(max(CGFloat(SettingsStore.shared.visualizerNoiseThreshold), 0), 0.95)
    }
}

// MARK: - Outcome Mark

enum OverlayMark: Equatable {
    case success
    case notice
    case failure
    case cancelled

    init?(phase: OverlayPhase) {
        switch phase {
        case let .done(outcome): self = outcome.isSuccess ? .success : .notice
        case .failed: self = .failure
        case .cancelled: self = .cancelled
        default: return nil
        }
    }

    var symbolName: String {
        switch self {
        case .success: return "checkmark"
        case .notice, .failure: return "exclamationmark"
        case .cancelled: return "xmark"
        }
    }

    func color(_ overlay: OverlayPalette) -> Color {
        switch self {
        case .success: return overlay.success
        case .notice: return overlay.warning
        case .failure: return overlay.error
        case .cancelled: return overlay.secondaryText
        }
    }
}

struct OverlayMarkView: View {
    @Environment(\.theme) private var theme
    let mark: OverlayMark
    let diameter: CGFloat

    var body: some View {
        let color = self.mark.color(self.theme.overlay)
        Circle()
            .fill(color.opacity(0.18))
            .overlay(Circle().strokeBorder(color.opacity(0.55), lineWidth: 1))
            .overlay(
                Image(systemName: self.mark.symbolName)
                    .font(AppFont.Overlay.icon.weight(.bold))
                    .foregroundStyle(color)
            )
            .frame(width: self.diameter, height: self.diameter)
            .accessibilityHidden(true)
    }
}

// MARK: - Indicator (meter ⇄ outcome mark)

/// The overlay protagonist. While listening the level meter moves; when work finishes
/// the meter collapses to its center and resolves into the outcome mark.
struct OverlayIndicator: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let phase: OverlayPhase
    let mode: OverlayMode
    let meterStyle: LevelMeterStyle

    private var mark: OverlayMark? {
        OverlayMark(phase: self.phase)
    }

    private var isLive: Bool {
        switch self.phase {
        case .idle, .starting, .listening: return true
        default: return false
        }
    }

    var body: some View {
        ZStack {
            if let mark = self.mark {
                OverlayMarkView(mark: mark, diameter: min(self.meterStyle.height, 22) + 2)
                    .transition(self.markTransition)
            } else {
                LevelMeter(
                    color: self.theme.overlay.color(for: self.mode),
                    style: self.meterStyle,
                    isLive: self.isLive
                )
                .opacity(self.phase.isWorking ? 0.45 : 1)
                .transition(self.meterTransition)
            }
        }
        .frame(width: self.meterStyle.width, height: max(self.meterStyle.height, 24))
        .animation(Motion.resolved(Motion.emphasis, reduceMotion: self.reduceMotion), value: self.mark)
        .motion(Motion.state, value: self.phase.isWorking)
        .accessibilityHidden(true)
    }

    private var meterTransition: AnyTransition {
        guard !self.reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.animation(Motion.enter),
            removal: .scale(scale: 0.15, anchor: .center).combined(with: .opacity).animation(Motion.exit)
        )
    }

    private var markTransition: AnyTransition {
        guard !self.reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .scale(scale: 0.4, anchor: .center).combined(with: .opacity).animation(Motion.emphasis.delay(Motion.quick * 0.5)),
            removal: .opacity.animation(Motion.exit)
        )
    }
}

// MARK: - Status Label

/// Mode glyph + status text. Working states shimmer; finished states take the color
/// of their mark so state is carried by glyph, text and color together.
struct OverlayStatusLabel: View {
    @Environment(\.theme) private var theme

    let phase: OverlayPhase
    let mode: OverlayMode
    var font: Font = AppFont.Overlay.status
    var showsModeGlyph: Bool = true
    var maxLines: Int = 1

    var body: some View {
        HStack(spacing: Space.xs) {
            if self.showsModeGlyph {
                Image(systemName: self.mode.symbolName)
                    .font(AppFont.Overlay.icon)
                    .foregroundStyle(self.modeColor)
                    .accessibilityHidden(true)
            }

            if self.phase.isWorking || self.phase == .starting {
                OverlayShimmerText(text: self.text, color: self.modeColor, font: self.font)
            } else {
                Text(self.text)
                    .font(self.font)
                    .foregroundStyle(self.textColor)
                    .lineLimit(self.isFailure ? max(self.maxLines, 2) : self.maxLines)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(self.mode.displayName) Mode, \(self.phase.statusText.isEmpty ? self.text : self.phase.statusText)")
    }

    private var isFailure: Bool {
        if case .failed = self.phase { return true }
        return false
    }

    private var modeColor: Color {
        self.theme.overlay.color(for: self.mode)
    }

    private var text: String {
        switch self.phase {
        case .idle, .listening: return self.mode.displayName
        default: return self.phase.statusText
        }
    }

    private var textColor: Color {
        if let mark = OverlayMark(phase: self.phase) {
            return mark.color(self.theme.overlay)
        }
        return self.modeColor
    }
}

// MARK: - Shimmer Text

/// The one ambient loop: a soft highlight sweeping across status text while work is in
/// progress. Sine-eased (not linear), period `Motion.ambientPeriod`. Static with Reduce Motion.
struct OverlayShimmerText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let text: String
    let color: Color
    var font: Font = AppFont.Overlay.status

    private let bandHalfWidth: CGFloat = 0.3

    var body: some View {
        if self.reduceMotion {
            self.label(highlight: nil)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let cycle = (time / Motion.ambientPeriod).truncatingRemainder(dividingBy: 1)
                let eased = 0.5 - 0.5 * cos(cycle * .pi)
                self.label(highlight: CGFloat(-0.3 + eased * 1.6))
            }
        }
    }

    @ViewBuilder
    private func label(highlight center: CGFloat?) -> some View {
        let text = Text(self.text).font(self.font).lineLimit(1)
        if let center {
            text.foregroundStyle(
                LinearGradient(
                    colors: [
                        self.color.opacity(0.55),
                        self.color.opacity(0.55),
                        self.color,
                        self.color.opacity(0.55),
                        self.color.opacity(0.55),
                    ],
                    startPoint: UnitPoint(x: center - self.bandHalfWidth, y: 0.5),
                    endPoint: UnitPoint(x: center + self.bandHalfWidth, y: 0.5)
                )
            )
        } else {
            text.foregroundStyle(self.color.opacity(0.85))
        }
    }
}

// MARK: - Transcript Preview

/// Spoken words, set in the serif (DESIGN.md §2). The box reserves its lines so the
/// overlay never changes size while text streams in. The newest words sit on the last
/// line; earlier lines slide out of the top under a short fade (one line: the head is
/// truncated instead).
struct OverlayTranscriptText: View {
    @Environment(\.theme) private var theme

    let text: String
    let font: Font
    let lines: Int
    /// Reduced emphasis while the transcript is being processed.
    var isDimmed: Bool = false
    /// Shown while there are no words yet, so the area never reads as a blank, broken box
    /// (models that only transcribe after you stop leave it empty for the whole session).
    var placeholder: String?

    private var showsPlaceholder: Bool {
        self.text.isEmpty && !(self.placeholder ?? "").isEmpty
    }

    private var displayText: String {
        self.showsPlaceholder ? (self.placeholder ?? "") : self.text
    }

    /// Changes only when the placeholder changes or real words replace it — not on every
    /// streamed word — so only those swaps run the transition below.
    private var contentKey: String {
        self.showsPlaceholder ? "placeholder:\(self.placeholder ?? "")" : "transcript"
    }

    /// The outgoing text leaves before the incoming text arrives, so the two never
    /// overlap mid-fade (one protagonist at a time).
    private static let swapTransition = AnyTransition.asymmetric(
        insertion: .opacity.animation(Motion.enter.delay(Motion.quick)),
        removal: .opacity.animation(Motion.exit)
    )

    @State private var boxHeight: CGFloat = 0
    @State private var textHeight: CGFloat = 0

    private static let topFade: CGFloat = Space.lg

    /// Fade the top edge only when earlier lines are actually scrolled out.
    private var overflows: Bool {
        self.textHeight > self.boxHeight + Space.xxs
    }

    var body: some View {
        Group {
            if self.lines <= 1 {
                self.styled(Text(self.displayText))
                    .lineLimit(1, reservesSpace: true)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(self.contentKey)
                    .transition(Self.swapTransition)
            } else {
                // Placeholder sizes the box to exactly `lines` lines of this font, using
                // glyphs from both scripts so mixed Chinese/English lines fit.
                Text("Ag 中")
                    .font(self.font)
                    .lineLimit(self.lines, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hidden()
                    // Headroom: lines that mix scripts can be a few points taller.
                    .padding(.top, Space.xs)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { self.boxHeight = $0 }
                    .overlay(alignment: .bottomLeading) {
                        self.styled(Text(self.displayText))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onGeometryChange(for: CGFloat.self, of: \.size.height) { self.textHeight = $0 }
                            .id(self.contentKey)
                            .transition(Self.swapTransition)
                    }
                    .clipped()
                    .mask(
                        VStack(spacing: 0) {
                            LinearGradient(
                                colors: [self.overflows ? .clear : .black, .black],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: Self.topFade)
                            Color.black
                        }
                    )
            }
        }
        .motion(Motion.state, value: self.isDimmed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.text.isEmpty ? "" : "Transcript: \(self.text)")
        .accessibilityHidden(self.text.isEmpty)
    }

    private func styled(_ text: Text) -> some View {
        text
            .font(self.font)
            .foregroundStyle(
                self.isDimmed || self.showsPlaceholder ? self.theme.overlay.tertiaryText : self.theme.overlay.primaryText
            )
            .multilineTextAlignment(.leading)
    }
}

// MARK: - Cancel Affordances

/// "esc" key cap shown next to the close button.
struct OverlayKeyCap: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        Text(self.text)
            .font(AppFont.Overlay.keyCap)
            .foregroundStyle(self.theme.overlay.tertiaryText)
            .padding(.horizontal, Space.xs + Space.xxs)
            .padding(.vertical, Space.xxs)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .strokeBorder(self.theme.overlay.hairline, lineWidth: 1)
            )
            .fixedSize()
            .accessibilityHidden(true)
    }
}

/// Close button + esc hint. Both routes end in the same cancel path.
struct OverlayCancelControl: View {
    var showsKeyCap: Bool = true
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: Space.xs) {
            if self.showsKeyCap {
                OverlayKeyCap(text: "esc")
            }
            IconButton("Cancel (Esc)", systemName: "xmark", size: self.size) {
                NotchOverlayManager.shared.handleEscape()
            }
        }
        .fixedSize()
    }
}

// MARK: - Chip Button Style

/// Compact pill used for the bottom overlay's controls (mode, prompt, AI, actions).
struct OverlayChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OverlayChip(configuration: configuration)
    }

    private struct OverlayChip: View {
        @Environment(\.theme) private var theme
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false
        let configuration: ButtonStyle.Configuration

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            let active = self.isEnabled && (self.isHovered || self.configuration.isPressed)
            self.configuration.label
                .font(AppFont.Overlay.label)
                .foregroundStyle(self.theme.overlay.secondaryText)
                .lineLimit(1)
                .padding(.horizontal, Space.sm)
                .padding(.vertical, Space.xs)
                .background(shape.fill(active ? self.theme.overlay.surfaceHover : self.theme.overlay.surface))
                .overlay(shape.strokeBorder(self.theme.overlay.hairline, lineWidth: 1))
                .contentShape(shape)
                .opacity(self.isEnabled ? 1 : 0.55)
                .onHover { self.isHovered = $0 }
                .motion(Motion.snappy, value: active)
        }
    }
}

/// Chip label: optional dimmed title, value, and a disclosure chevron.
struct OverlayChipLabel: View {
    @Environment(\.theme) private var theme
    var title: String?
    let value: String
    var systemImage: String?
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: Space.xs) {
            if let title {
                Text(title)
                    .foregroundStyle(self.theme.overlay.tertiaryText)
            }
            Text(self.value)
                .foregroundStyle(self.theme.overlay.primaryText)
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(self.theme.overlay.secondaryText)
            }
            if self.showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(AppFont.micro)
                    .foregroundStyle(self.theme.overlay.tertiaryText)
            }
        }
        .fixedSize()
    }
}

// MARK: - Screen Resolution

/// Picks the display for an overlay: the screen holding the target app's focused
/// window, else the screen under the mouse, else the main screen.
enum OverlayScreenResolver {
    @MainActor
    static func targetScreen(pid: pid_t? = nil) -> NSScreen? {
        let resolvedPID = pid ?? Self.frontmostForeignPID()
        if let resolvedPID,
           let frame = Self.focusedWindowFrame(pid: resolvedPID),
           let screen = Self.screen(containing: CGPoint(x: frame.midX, y: frame.midY))
        {
            return screen
        }
        if let screen = Self.screen(containing: NSEvent.mouseLocation) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private static func frontmostForeignPID() -> pid_t? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier
        else { return nil }
        return app.processIdentifier
    }

    private static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    /// Focused window frame in Cocoa (bottom-left origin) coordinates.
    private static func focusedWindowFrame(pid: pid_t) -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        // Never let an unresponsive app stall the overlay.
        AXUIElementSetMessagingTimeout(app, 0.05)

        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let windowValue,
              CFGetTypeID(windowValue) == AXUIElementGetTypeID()
        else { return nil }
        // swiftlint:disable:next force_cast
        let window = windowValue as! AXUIElement

        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable force_cast
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        // swiftlint:enable force_cast

        guard let primary = NSScreen.screens.first else { return nil }
        let flippedY = primary.frame.maxY - origin.y - size.height
        return CGRect(x: origin.x, y: flippedY, width: size.width, height: size.height)
    }
}
