import AppKit
import SwiftUI

/// Shared building blocks for the Activity and Tools pages (Stats, History,
/// File Transcription, Command Mode, Edit Mode, Help & Feedback).
/// See docs/design/DESIGN.md §§ 4–6.
enum ActivityUI {
    /// Readable line length for page content.
    static let contentMaxWidth: CGFloat = 760
    /// Line length for short centered messages (empty states).
    static let messageMaxWidth: CGFloat = 320

    // MARK: - Page

    /// Scrolling page with the standard header, padding and content width.
    struct Page<Trailing: View, Content: View>: View {
        @Environment(\.theme) private var theme

        let title: String
        let subtitle: String?
        private let trailing: Trailing
        private let content: Content

        init(
            _ title: String,
            subtitle: String? = nil,
            @ViewBuilder trailing: () -> Trailing,
            @ViewBuilder content: () -> Content
        ) {
            self.title = title
            self.subtitle = subtitle
            self.trailing = trailing()
            self.content = content()
        }

        var body: some View {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Space.xl) {
                    Header(self.title, subtitle: self.subtitle) { self.trailing }
                    self.content
                }
                .frame(maxWidth: ActivityUI.contentMaxWidth, alignment: .leading)
                .padding(.horizontal, Space.xxl)
                .padding(.vertical, Space.xl)
                .frame(maxWidth: .infinity)
            }
            .background(self.theme.palette.contentBackground)
        }
    }

    // MARK: - Header

    struct Header<Trailing: View>: View {
        @Environment(\.theme) private var theme

        let title: String
        let subtitle: String?
        private let trailing: Trailing

        init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
            self.title = title
            self.subtitle = subtitle
            self.trailing = trailing()
        }

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(self.title)
                        .font(AppFont.pageTitle)
                        .foregroundStyle(self.theme.palette.primaryText)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle = self.subtitle {
                        Text(subtitle)
                            .font(AppFont.callout)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Space.md)
                self.trailing
            }
        }
    }

    // MARK: - Section Title

    /// Card title row: title, optional supporting text, optional trailing accessory.
    struct SectionTitle<Trailing: View>: View {
        @Environment(\.theme) private var theme

        let title: String
        let systemImage: String?
        private let trailing: Trailing

        init(_ title: String, systemImage: String? = nil, @ViewBuilder trailing: () -> Trailing) {
            self.title = title
            self.systemImage = systemImage
            self.trailing = trailing()
        }

        var body: some View {
            HStack(spacing: Space.sm) {
                if let systemImage = self.systemImage {
                    Image(systemName: systemImage)
                        .font(AppFont.iconSmall)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .accessibilityHidden(true)
                }
                Text(self.title)
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.sm)
                self.trailing
            }
        }
    }

    // MARK: - Empty State

    /// What this place will contain, why it is empty, and the one action that fills it.
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
            VStack(spacing: Space.md) {
                Image(systemName: self.systemImage)
                    .font(AppFont.iconLarge)
                    .foregroundStyle(self.theme.palette.tertiaryText)
                    .frame(width: Space.xxxl, height: Space.xxxl)
                    .background(Circle().fill(self.theme.palette.surfaceSunken))
                    .accessibilityHidden(true)
                VStack(spacing: Space.xs) {
                    Text(self.title)
                        .font(AppFont.bodyEmphasis)
                        .foregroundStyle(self.theme.palette.primaryText)
                    Text(self.message)
                        .font(AppFont.callout)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: ActivityUI.messageMaxWidth)
                self.action
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: - Banner

    enum BannerKind {
        case error
        case warning
        case info

        var systemImage: String {
            switch self {
            case .error: return "exclamationmark.octagon"
            case .warning: return "exclamationmark.triangle"
            case .info: return "info.circle"
            }
        }

        func color(_ palette: AppTheme.Palette) -> Color {
            switch self {
            case .error: return palette.error
            case .warning: return palette.warning
            case .info: return palette.info
            }
        }
    }

    /// Inline message with a glyph (never color alone) and optional actions.
    struct Banner<Actions: View>: View {
        @Environment(\.theme) private var theme

        let kind: BannerKind
        let title: String
        let message: String?
        private let actions: Actions

        init(_ kind: BannerKind, title: String, message: String? = nil, @ViewBuilder actions: () -> Actions) {
            self.kind = kind
            self.title = title
            self.message = message
            self.actions = actions()
        }

        var body: some View {
            let tint = self.kind.color(self.theme.palette)
            HStack(alignment: .top, spacing: Space.md) {
                Image(systemName: self.kind.systemImage)
                    .font(AppFont.icon)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xxs) {
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
                }
                Spacer(minLength: Space.sm)
                HStack(spacing: Space.sm) {
                    self.actions
                }
            }
            .padding(Space.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(self.theme.palette.subtle(tint))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            )
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: - Badge

    struct Badge: View {
        @Environment(\.theme) private var theme

        let text: String
        var systemImage: String?
        var tint: Color?

        var body: some View {
            let color = self.tint ?? self.theme.palette.accentForeground
            HStack(spacing: Space.xxs) {
                if let systemImage = self.systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(self.text)
            }
            .font(AppFont.micro)
            .foregroundStyle(color)
            .padding(.horizontal, Space.sm - Space.xxs)
            .padding(.vertical, Space.xxs)
            .background(Capsule().fill(self.theme.palette.subtle(color)))
        }
    }

    // MARK: - Key Cap

    struct KeyCap: View {
        @Environment(\.theme) private var theme
        let text: String

        init(_ text: String) {
            self.text = text
        }

        var body: some View {
            Text(self.text)
                .font(AppFont.mono)
                .foregroundStyle(self.theme.palette.primaryText)
                .padding(.horizontal, Space.sm - Space.xxs)
                .padding(.vertical, Space.xxs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(self.theme.palette.surfaceSunken)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .strokeBorder(self.theme.palette.hairline, lineWidth: 1)
                )
                .accessibilityLabel(Text("Shortcut \(self.text)"))
        }
    }

    // MARK: - Copy Button

    /// Copies text and confirms in place: the label turns into “Copied” for a moment.
    struct CopyButton: View {
        let text: String
        var title: String = "Copy"
        var size: SayItButtonSize = .small

        @State private var didCopy = false
        @State private var resetTask: Task<Void, Never>?

        var body: some View {
            Button {
                ActivityUI.copyToPasteboard(self.text)
                withMotion(Motion.snappy) { self.didCopy = true }
                NSAccessibility.post(
                    element: NSApp as Any,
                    notification: .announcementRequested,
                    userInfo: [.announcement: "Copied", .priority: NSAccessibilityPriorityLevel.medium.rawValue]
                )
                self.resetTask?.cancel()
                self.resetTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard !Task.isCancelled else { return }
                    withMotion(Motion.exit) { self.didCopy = false }
                }
            } label: {
                Label(self.didCopy ? "Copied" : self.title, systemImage: self.didCopy ? "checkmark" : "doc.on.doc")
                    .contentTransition(.opacity)
            }
            .buttonStyle(.sayIt(.secondary, size: self.size))
            .disabled(self.text.isEmpty)
        }
    }

    static func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Labeled Value

    /// Small label above a value, used in detail grids.
    struct LabeledValue: View {
        @Environment(\.theme) private var theme

        let label: String
        let value: String
        var systemImage: String?

        var body: some View {
            HStack(alignment: .top, spacing: Space.sm) {
                if let systemImage = self.systemImage {
                    Image(systemName: systemImage)
                        .font(AppFont.iconSmall)
                        .foregroundStyle(self.theme.palette.tertiaryText)
                        .frame(width: Space.lg)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(self.label)
                        .font(AppFont.caption)
                        .foregroundStyle(self.theme.palette.secondaryText)
                    Text(self.value)
                        .font(AppFont.rowTitle)
                        .foregroundStyle(self.theme.palette.primaryText)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Transcript Block

    /// Spoken words rendered as writing: New York serif on a recessed surface.
    struct TranscriptBlock: View {
        @Environment(\.theme) private var theme

        let text: String
        var emphasis: Bool = true
        var large: Bool = false

        var body: some View {
            Text(self.text)
                .font(self.large ? AppFont.transcriptLarge : AppFont.transcript)
                .lineSpacing(Space.xs)
                .foregroundStyle(self.emphasis ? self.theme.palette.primaryText : self.theme.palette.secondaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.lg)
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

    // MARK: - Toast

    /// Transient confirmation pinned to the bottom of a page (e.g. “Dictation deleted · Undo”).
    struct Toast<Action: View>: View {
        @Environment(\.theme) private var theme

        let message: String
        private let action: Action

        init(_ message: String, @ViewBuilder action: () -> Action) {
            self.message = message
            self.action = action()
        }

        var body: some View {
            HStack(spacing: Space.md) {
                Text(self.message)
                    .font(AppFont.callout)
                    .foregroundStyle(self.theme.palette.primaryText)
                self.action
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm)
            .background(
                Capsule().fill(self.theme.palette.surfaceRaised)
                    .shadow(
                        color: self.theme.metrics.elevatedCardShadow.color.opacity(self.theme.metrics.elevatedCardShadow.opacity),
                        radius: self.theme.metrics.elevatedCardShadow.radius,
                        y: self.theme.metrics.elevatedCardShadow.y
                    )
            )
            .overlay(Capsule().strokeBorder(self.theme.palette.hairline, lineWidth: 1))
            .accessibilityElement(children: .contain)
        }
    }
}

extension ActivityUI.Page where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

extension ActivityUI.Header where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

extension ActivityUI.SectionTitle where Trailing == EmptyView {
    init(_ title: String, systemImage: String? = nil) {
        self.init(title, systemImage: systemImage, trailing: { EmptyView() })
    }
}

extension ActivityUI.EmptyState where Action == EmptyView {
    init(systemImage: String, title: String, message: String) {
        self.init(systemImage: systemImage, title: title, message: message, action: { EmptyView() })
    }
}

extension ActivityUI.Banner where Actions == EmptyView {
    init(_ kind: ActivityUI.BannerKind, title: String, message: String? = nil) {
        self.init(kind, title: title, message: message, actions: { EmptyView() })
    }
}
