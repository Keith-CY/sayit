//
//  AISettingsComponents.swift
//  SayIt
//
//  Building blocks shared by the settings pages (General, Voice Engine, Dictionary).
//  See docs/design/DESIGN.md § Components.
//

import SwiftUI

/// Namespace for settings-page building blocks.
enum SettingsKit {
    /// Readable column width for settings content.
    static let contentMaxWidth: CGFloat = 760
    /// Width of trailing menu pickers so rows line up.
    static let pickerWidth: CGFloat = 220
    /// Width of the small value label next to sliders.
    static let valueLabelWidth: CGFloat = 92
    /// Width of a slider including its end labels, so slider rows line up.
    static let sliderWidth: CGFloat = 260
    static let emptyStateTextWidth: CGFloat = 420
    static let ratingLabelWidth: CGFloat = 62
}

// MARK: - Page

extension SettingsKit {
    /// Scrollable page with a title, a one-line purpose and a centered content column.
    struct Page<Content: View>: View {
        @Environment(\.theme) private var theme

        let title: String
        let subtitle: String
        private let content: Content

        init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
            self.title = title
            self.subtitle = subtitle
            self.content = content()
        }

        var body: some View {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(self.title)
                            .font(AppFont.pageTitle)
                            .foregroundStyle(self.theme.palette.primaryText)
                            .accessibilityAddTraits(.isHeader)
                        Text(self.subtitle)
                            .font(AppFont.callout)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    self.content
                }
                .frame(maxWidth: SettingsKit.contentMaxWidth, alignment: .leading)
                .padding(Space.xxl)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.automatic)
            .background(self.theme.palette.contentBackground)
        }
    }
}

// MARK: - Section

extension SettingsKit {
    /// A titled group of rows. The title sits above the card, help text below it.
    struct Section<Content: View, Accessory: View>: View {
        @Environment(\.theme) private var theme

        let title: String
        let footer: String?
        private let accessory: Accessory
        private let content: Content

        init(
            _ title: String,
            footer: String? = nil,
            @ViewBuilder accessory: () -> Accessory,
            @ViewBuilder content: () -> Content
        ) {
            self.title = title
            self.footer = footer
            self.accessory = accessory()
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Text(self.title)
                        .font(AppFont.sectionTitle)
                        .foregroundStyle(self.theme.palette.primaryText)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Space.sm)
                    self.accessory
                }
                .padding(.horizontal, Space.xs)

                ThemedCard(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        self.content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let footer = self.footer {
                    Text(footer)
                        .font(AppFont.caption)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Space.xs)
                }
            }
        }
    }
}

extension SettingsKit.Section where Accessory == EmptyView {
    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, footer: footer, accessory: { EmptyView() }, content: content)
    }
}

// MARK: - Rows

extension SettingsKit {
    /// Title + one line of supporting text, with a trailing control.
    struct Row<Trailing: View>: View {
        @Environment(\.theme) private var theme

        let title: String
        let description: String?
        let systemImage: String?
        private let trailing: Trailing

        init(
            _ title: String,
            description: String? = nil,
            systemImage: String? = nil,
            @ViewBuilder trailing: () -> Trailing
        ) {
            self.title = title
            self.description = description
            self.systemImage = systemImage
            self.trailing = trailing()
        }

        var body: some View {
            HStack(alignment: .center, spacing: Space.md) {
                if let systemImage = self.systemImage {
                    Image(systemName: systemImage)
                        .font(AppFont.icon)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .frame(width: Space.xl)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(self.title)
                        .font(AppFont.rowTitle)
                        .foregroundStyle(self.theme.palette.primaryText)
                    if let description = self.description {
                        Text(description)
                            .font(AppFont.callout)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                self.trailing
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)
        }
    }

    /// A row whose trailing control is a switch. The title is the switch's
    /// accessibility label; the description is its hint.
    struct ToggleRow: View {
        let title: String
        let description: String?
        var systemImage: String?
        @Binding var isOn: Bool

        init(_ title: String, description: String? = nil, systemImage: String? = nil, isOn: Binding<Bool>) {
            self.title = title
            self.description = description
            self.systemImage = systemImage
            self._isOn = isOn
        }

        var body: some View {
            SettingsKit.Row(self.title, description: self.description, systemImage: self.systemImage) {
                Toggle(self.title, isOn: self.$isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityHint(self.description ?? "")
            }
        }
    }

    /// Hairline between rows, inset to the text column.
    struct RowDivider: View {
        @Environment(\.theme) private var theme
        var inset: CGFloat = Space.lg

        var body: some View {
            Rectangle()
                .fill(self.theme.palette.separator)
                .frame(height: 1)
                .padding(.leading, self.inset)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Status

extension SettingsKit {
    enum Tone {
        case neutral
        case accent
        case success
        case warning
        case error
        case info

        func color(_ palette: AppTheme.Palette) -> Color {
            switch self {
            case .neutral: return palette.secondaryText
            case .accent: return palette.accentForeground
            case .success: return palette.success
            case .warning: return palette.warning
            case .error: return palette.error
            case .info: return palette.info
            }
        }
    }

    /// Glyph + text status. Never relies on color alone.
    struct StatusBadge: View {
        @Environment(\.theme) private var theme

        let text: String
        let systemImage: String
        var tone: Tone = .neutral

        var body: some View {
            HStack(spacing: Space.xs) {
                Image(systemName: self.systemImage)
                    .font(AppFont.iconSmall)
                    .foregroundStyle(self.tone.color(self.theme.palette))
                    .accessibilityHidden(true)
                Text(self.text)
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(self.theme.palette.primaryText)
            }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xxs)
            .background(
                Capsule().fill(self.tone == .neutral
                    ? self.theme.palette.surfaceSunken
                    : self.theme.palette.subtle(self.tone.color(self.theme.palette)))
            )
            .accessibilityElement(children: .combine)
        }
    }

    /// Small informational chip (size, languages, requirements).
    struct Chip: View {
        @Environment(\.theme) private var theme

        let text: String
        var systemImage: String?

        var body: some View {
            HStack(spacing: Space.xs) {
                if let systemImage = self.systemImage {
                    Image(systemName: systemImage)
                        .font(AppFont.iconSmall)
                        .accessibilityHidden(true)
                }
                Text(self.text)
                    .font(AppFont.caption)
            }
            .foregroundStyle(self.theme.palette.secondaryText)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xxs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(self.theme.palette.surfaceSunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(self.theme.palette.hairline, lineWidth: 1)
            )
        }
    }

    /// Keyboard shortcut rendered as a key cap.
    struct KeyCap: View {
        @Environment(\.theme) private var theme

        let text: String

        var body: some View {
            Text(self.text)
                .font(AppFont.mono.weight(.medium))
                .foregroundStyle(self.theme.palette.primaryText)
                .padding(.horizontal, Space.sm)
                .padding(.vertical, Space.xs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(self.theme.palette.surfaceSunken)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(self.theme.palette.hairline, lineWidth: 1)
                )
                .accessibilityLabel("Shortcut \(self.text)")
        }
    }

    /// Inline message with an icon, used for errors, warnings and guidance.
    struct Notice<Actions: View>: View {
        @Environment(\.theme) private var theme

        let tone: Tone
        let title: String
        let message: String?
        private let actions: Actions

        init(_ tone: Tone, title: String, message: String? = nil, @ViewBuilder actions: () -> Actions) {
            self.tone = tone
            self.title = title
            self.message = message
            self.actions = actions()
        }

        private var systemImage: String {
            switch self.tone {
            case .error: return "xmark.octagon"
            case .warning: return "exclamationmark.triangle"
            case .success: return "checkmark.circle"
            default: return "info.circle"
            }
        }

        var body: some View {
            HStack(alignment: .top, spacing: Space.md) {
                Image(systemName: self.systemImage)
                    .font(AppFont.icon)
                    .foregroundStyle(self.tone.color(self.theme.palette))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(self.title)
                        .font(AppFont.rowTitle)
                        .foregroundStyle(self.theme.palette.primaryText)
                    if let message = self.message {
                        Text(message)
                            .font(AppFont.callout)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    HStack(spacing: Space.sm) {
                        self.actions
                    }
                    .padding(.top, Space.xxs)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Space.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(self.theme.palette.subtle(self.tone.color(self.theme.palette)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(self.tone.color(self.theme.palette).opacity(0.3), lineWidth: 1)
            )
            .accessibilityElement(children: .contain)
        }
    }

    /// What a list will hold, why it is empty, and the one action that fills it.
    struct EmptyState<Action: View>: View {
        @Environment(\.theme) private var theme

        let systemImage: String
        let title: String
        let message: String
        private let action: Action

        init(systemImage: String, title: String, message: String, @ViewBuilder action: () -> Action) {
            self.systemImage = systemImage
            self.title = title
            self.message = message
            self.action = action()
        }

        var body: some View {
            VStack(spacing: Space.sm) {
                Image(systemName: self.systemImage)
                    .font(AppFont.iconLarge)
                    .foregroundStyle(self.theme.palette.tertiaryText)
                    .accessibilityHidden(true)
                Text(self.title)
                    .font(AppFont.rowTitle)
                    .foregroundStyle(self.theme.palette.primaryText)
                Text(self.message)
                    .font(AppFont.callout)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: SettingsKit.emptyStateTextWidth)
                self.action
                    .padding(.top, Space.xs)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.xl)
            .padding(.horizontal, Space.lg)
        }
    }
}

extension SettingsKit.Notice where Actions == EmptyView {
    init(_ tone: SettingsKit.Tone, title: String, message: String? = nil) {
        self.init(tone, title: title, message: message, actions: { EmptyView() })
    }
}

// MARK: - Rating

extension SettingsKit {
    /// Five-segment rating (speed, accuracy). Fills once when the value changes; no
    /// idle motion. With Reduce Motion the change is a short cross-fade.
    struct Rating: View {
        @Environment(\.theme) private var theme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        let label: String
        let value: Int
        var maximum: Int = 5
        var compact: Bool = false

        private var segmentSize: CGSize {
            self.compact ? CGSize(width: 10, height: 4) : CGSize(width: 18, height: 6)
        }

        var body: some View {
            HStack(spacing: self.compact ? Space.xs : Space.sm) {
                Text(self.label)
                    .font(self.compact ? AppFont.caption : AppFont.captionEmphasis)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .frame(minWidth: self.compact ? nil : SettingsKit.ratingLabelWidth, alignment: .leading)

                HStack(spacing: Space.xxs) {
                    ForEach(0..<self.maximum, id: \.self) { index in
                        Capsule()
                            .fill(index < self.value ? self.theme.palette.accent : self.theme.palette.separator)
                            .frame(width: self.segmentSize.width, height: self.segmentSize.height)
                    }
                }
                .motion(Motion.state, value: self.value)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(self.label)
            .accessibilityValue("\(self.value) out of \(self.maximum)")
        }
    }
}
