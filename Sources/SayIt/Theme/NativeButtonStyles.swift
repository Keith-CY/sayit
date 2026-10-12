import SwiftUI

// MARK: - Button System
//
// Four roles, three sizes. See docs/design/DESIGN.md § Components.
//   .sayItPrimary      one per view: the action that moves the task forward
//   .sayItSecondary    supporting actions
//   .sayItQuiet        low-emphasis inline actions (text-only, accent colored)
//   .sayItDestructive  removes data; always paired with a confirmation
// Icon-only buttons use `IconButton`, which requires an accessibility label.

enum SayItButtonSize {
    case small
    case regular
    case large

    var height: CGFloat {
        switch self {
        case .small: return 24
        case .regular: return 30
        case .large: return 40
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .small: return Space.sm
        case .regular: return Space.md
        case .large: return Space.xl
        }
    }

    var font: Font {
        switch self {
        case .small: return AppFont.captionEmphasis
        case .regular: return AppFont.bodyEmphasis
        case .large: return AppFont.bodyEmphasis
        }
    }

    var radius: CGFloat {
        switch self {
        case .small: return Radius.sm
        case .regular: return Radius.md
        case .large: return Radius.lg
        }
    }
}

enum SayItButtonRole {
    case primary
    case secondary
    case quiet
    case destructive
}

struct SayItButtonStyle: ButtonStyle {
    var role: SayItButtonRole = .primary
    var size: SayItButtonSize = .regular
    var fullWidth: Bool = false
    /// Primary only: paints the button in the recording color (e.g. "Stop Recording").
    var isRecording: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        SayItButton(
            configuration: configuration,
            role: self.role,
            size: self.size,
            fullWidth: self.fullWidth,
            isRecording: self.isRecording
        )
    }

    private struct SayItButton: View {
        @Environment(\.theme) private var theme
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovered = false

        let configuration: ButtonStyle.Configuration
        let role: SayItButtonRole
        let size: SayItButtonSize
        let fullWidth: Bool
        let isRecording: Bool

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: self.size.radius, style: .continuous)
        }

        private var isInteractive: Bool {
            self.isEnabled
        }

        var body: some View {
            let palette = self.theme.palette
            let pressed = self.configuration.isPressed && self.isInteractive
            let hovered = self.isHovered && self.isInteractive

            self.configuration.label
                .font(self.size.font)
                .lineLimit(1)
                .padding(.horizontal, self.role == .quiet ? Space.xs : self.size.horizontalPadding)
                .frame(maxWidth: self.fullWidth ? .infinity : nil)
                .frame(minHeight: self.size.height)
                .foregroundStyle(self.foreground(palette))
                .background(self.background(palette, hovered: hovered, pressed: pressed), in: self.shape)
                .overlay(self.outline(palette, hovered: hovered))
                .contentShape(self.shape)
                .opacity(self.isInteractive ? 1 : 0.45)
                .scaleEffect(pressed && !self.reduceMotion ? 0.98 : 1)
                .animation(Motion.resolved(Motion.snappy, reduceMotion: self.reduceMotion), value: hovered)
                .animation(Motion.resolved(Motion.snappy, reduceMotion: self.reduceMotion), value: pressed)
                .onHover { self.isHovered = $0 }
        }

        private func foreground(_ palette: AppTheme.Palette) -> Color {
            switch self.role {
            case .primary:
                return self.isRecording ? .white : palette.onAccent
            case .secondary:
                return palette.primaryText
            case .quiet:
                return palette.accentForeground
            case .destructive:
                return palette.error
            }
        }

        private func background(_ palette: AppTheme.Palette, hovered: Bool, pressed: Bool) -> Color {
            switch self.role {
            case .primary:
                let base = self.isRecording ? palette.recording : palette.accent
                return pressed ? base.opacity(0.82) : (hovered ? base.opacity(0.92) : base)
            case .secondary:
                return pressed ? palette.surfaceHover.opacity(1.6) : (hovered ? palette.surfaceHover : palette.surfaceRaised)
            case .quiet:
                return hovered || pressed ? palette.accentSubtle : .clear
            case .destructive:
                return hovered || pressed ? palette.subtle(palette.error) : palette.surfaceRaised
            }
        }

        @ViewBuilder
        private func outline(_ palette: AppTheme.Palette, hovered: Bool) -> some View {
            switch self.role {
            case .primary, .quiet:
                EmptyView()
            case .secondary, .destructive:
                self.shape.strokeBorder(palette.hairline, lineWidth: 1)
            }
        }
    }
}

extension ButtonStyle where Self == SayItButtonStyle {
    static var sayItPrimary: SayItButtonStyle { SayItButtonStyle(role: .primary) }
    static var sayItSecondary: SayItButtonStyle { SayItButtonStyle(role: .secondary) }
    static var sayItQuiet: SayItButtonStyle { SayItButtonStyle(role: .quiet) }
    static var sayItDestructive: SayItButtonStyle { SayItButtonStyle(role: .destructive) }

    static func sayIt(
        _ role: SayItButtonRole,
        size: SayItButtonSize = .regular,
        fullWidth: Bool = false,
        isRecording: Bool = false
    ) -> SayItButtonStyle {
        SayItButtonStyle(role: role, size: size, fullWidth: fullWidth, isRecording: isRecording)
    }
}

// MARK: - Icon Button

/// Icon-only button. The label is spoken by VoiceOver and shown as the tooltip.
struct IconButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    let systemName: String
    let label: String
    var role: SayItButtonRole = .secondary
    var size: CGFloat = 26
    let action: () -> Void

    init(
        _ label: String,
        systemName: String,
        role: SayItButtonRole = .secondary,
        size: CGFloat = 26,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.systemName = systemName
        self.role = role
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.systemName)
                .font(AppFont.icon)
                .frame(width: self.size, height: self.size)
                .foregroundStyle(self.foreground)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(self.isHovered && self.isEnabled ? self.theme.palette.surfaceHover : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(self.isEnabled ? 1 : 0.45)
        .onHover { self.isHovered = $0 }
        .motion(Motion.snappy, value: self.isHovered)
        .help(self.label)
        .accessibilityLabel(self.label)
    }

    private var foreground: Color {
        switch self.role {
        case .destructive:
            return self.isHovered ? self.theme.palette.error : self.theme.palette.secondaryText
        case .quiet, .primary:
            return self.theme.palette.accentForeground
        case .secondary:
            return self.isHovered ? self.theme.palette.primaryText : self.theme.palette.secondaryText
        }
    }
}

// MARK: - Legacy Styles
//
// Thin wrappers so existing call sites render with the new system while they are
// migrated. New code must use `.sayIt…` styles directly.

struct GlassButtonStyle: ButtonStyle {
    var height: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        SayItButtonStyle(role: .secondary, size: .regular).makeBody(configuration: configuration)
    }
}

struct PremiumButtonStyle: ButtonStyle {
    var isRecording: Bool = false
    var height: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        SayItButtonStyle(role: .primary, size: .large, fullWidth: true, isRecording: self.isRecording)
            .makeBody(configuration: configuration)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SayItButtonStyle(role: .secondary, size: .large, fullWidth: true).makeBody(configuration: configuration)
    }
}

struct CompactButtonStyle: ButtonStyle {
    var isReady: Bool = false
    var foreground: Color?
    var borderColor: Color?

    func makeBody(configuration: Configuration) -> some View {
        SayItButtonStyle(role: self.isReady ? .primary : .secondary, size: .regular).makeBody(configuration: configuration)
    }
}

struct AccentButtonStyle: ButtonStyle {
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        SayItButtonStyle(role: .primary, size: .regular).makeBody(configuration: configuration)
    }
}

// MARK: - Form Row

struct FormRowStyle: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm + Space.xxs)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(self.theme.palette.surfaceSunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(self.theme.palette.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func formRowStyle() -> some View {
        modifier(FormRowStyle())
    }
}
