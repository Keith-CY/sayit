import SwiftUI

// Presentational building blocks for the AI Enhancement page. They take plain values
// and closures (no view model), so the page and its snapshot specimen share them.

enum AIEnhancementLayout {
    static let logoTile: CGFloat = 32
    static let logoGlyph: CGFloat = 22
    static let featureGlyph: CGFloat = 36
    static let modelPickerWidth: CGFloat = 200
    static let providerPickerWidth: CGFloat = 170
    static let fieldMaxWidth: CGFloat = 360
    static let apiKeyFieldWidth: CGFloat = 240
    static let reasoningLabelWidth: CGFloat = 72
    static let reasoningControlWidth: CGFloat = 160
    static let promptEditorMinHeight: CGFloat = 180
    static let promptTestOutputMinHeight: CGFloat = 72
    static let sheetMinWidth: CGFloat = 560
    static let sheetMinHeight: CGFloat = 460
    static let dashPattern: [CGFloat] = [3, 3]
}

// MARK: - Page Header

struct AIEnhancementPageHeader: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("AI Enhancement")
                .font(AppFont.pageTitle)
                .foregroundStyle(self.theme.palette.primaryText)
                .accessibilityAddTraits(.isHeader)
            Text("Optionally rewrite what you say before it's inserted — fix punctuation, drop filler words, or follow your own instructions.")
                .font(AppFont.callout)
                .foregroundStyle(self.theme.palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Section Heading

struct AISectionHeading<Trailing: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(self.title)
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
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

/// Small uppercase-free group label inside a card ("Ready to Use", "Add a Provider").
struct AIGroupLabel: View {
    @Environment(\.theme) private var theme
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: Space.xs) {
            Text(self.title)
                .font(AppFont.captionEmphasis)
                .foregroundStyle(self.theme.palette.secondaryText)
            if let count {
                Text(count.formatted())
                    .font(AppFont.caption)
                    .foregroundStyle(self.theme.palette.tertiaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Status Badge

enum AIStatusKind: Equatable {
    case verified
    case failed
    case verifying
    case active
    case local
    case onDevice
    case unavailable
    case usesSelection

    var title: String {
        switch self {
        case .verified: return "Verified"
        case .failed: return "Connection Failed"
        case .verifying: return "Verifying…"
        case .active: return "In Use"
        case .local: return "Local"
        case .onDevice: return "On This Mac"
        case .unavailable: return "Unavailable"
        case .usesSelection: return "Uses Selection"
        }
    }

    var symbol: String {
        switch self {
        case .verified: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .verifying: return "arrow.triangle.2.circlepath"
        case .active: return "dot.radiowaves.left.and.right"
        case .local: return "desktopcomputer"
        case .onDevice: return "lock.shield"
        case .unavailable: return "slash.circle"
        case .usesSelection: return "text.cursor"
        }
    }
}

struct AIStatusBadge: View {
    @Environment(\.theme) private var theme
    let kind: AIStatusKind

    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: self.kind.symbol)
                .imageScale(.small)
                .foregroundStyle(self.glyphColor)
            Text(self.kind.title)
                .foregroundStyle(self.textColor)
        }
        .font(AppFont.micro)
        .padding(.horizontal, Space.sm - Space.xxs)
        .padding(.vertical, Space.xxs)
        .background(Capsule().fill(self.fill))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.kind.title)
    }

    private var glyphColor: Color {
        let palette = self.theme.palette
        switch self.kind {
        case .verified: return palette.success
        case .failed: return palette.error
        case .verifying, .active, .usesSelection: return palette.accentForeground
        case .local, .onDevice, .unavailable: return palette.secondaryText
        }
    }

    private var textColor: Color {
        switch self.kind {
        case .active, .usesSelection: return self.theme.palette.accentForeground
        default: return self.theme.palette.secondaryText
        }
    }

    private var fill: Color {
        let palette = self.theme.palette
        switch self.kind {
        case .verified: return palette.subtle(palette.success)
        case .failed: return palette.subtle(palette.error)
        case .active, .verifying, .usesSelection: return palette.accentSubtle
        case .local, .onDevice, .unavailable: return palette.surfaceHover
        }
    }
}

// MARK: - Inline Notice

enum AINoticeKind {
    case info
    case success
    case warning
    case error

    var symbol: String {
        switch self {
        case .info: return "info.circle"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "exclamationmark.octagon.fill"
        }
    }
}

struct AIInlineNotice: View {
    @Environment(\.theme) private var theme
    let kind: AINoticeKind
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Image(systemName: self.kind.symbol)
                .foregroundStyle(self.tint)
                .accessibilityHidden(true)
            Text(self.text)
                .font(AppFont.callout)
                .foregroundStyle(self.theme.palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(self.kind == .info ? self.theme.palette.surfaceSunken : self.theme.palette.subtle(self.tint))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(self.theme.palette.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        let palette = self.theme.palette
        switch self.kind {
        case .info: return palette.secondaryText
        case .success: return palette.success
        case .warning: return palette.warning
        case .error: return palette.error
        }
    }
}

/// One-line hint with a glyph, for "what's missing" guidance under a form.
struct AIHint: View {
    @Environment(\.theme) private var theme
    let text: String
    var symbol: String = "info.circle"

    var body: some View {
        Label {
            Text(self.text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: self.symbol)
        }
        .font(AppFont.caption)
        .foregroundStyle(self.theme.palette.secondaryText)
    }
}

// MARK: - Provider Logo

struct AIProviderLogo: View {
    @Environment(\.theme) private var theme
    let providerID: String
    let name: String
    var size: CGFloat = AIEnhancementLayout.logoTile

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
        ZStack {
            if let asset = Self.assetName(id: self.providerID, name: self.name) {
                // Brand marks are drawn for light backgrounds, so every logo sits on the
                // same white tile in both appearances.
                shape.fill(Color.white)
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: self.size * 0.7, height: self.size * 0.7)
            } else {
                shape.fill(self.theme.palette.surfaceRaised)
                Text(Self.initials(for: self.name))
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }
        }
        .frame(width: self.size, height: self.size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(self.theme.palette.hairline, lineWidth: 1))
        .accessibilityHidden(true)
    }

    static func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        return String(parts.prefix(2).compactMap(\.first)).uppercased()
    }

    static func assetName(id: String, name: String) -> String? {
        let id = id.lowercased()
        let name = name.lowercased()
        func matches(_ keys: String...) -> Bool {
            keys.contains { id.contains($0) || name.contains($0) }
        }
        if matches("openai-compatible") || id == "compatible" { return "Provider_Compatible" }
        if matches("openai") { return "Provider_OpenAI" }
        if matches("anthropic") { return "Provider_Anthropic" }
        if matches("openrouter") { return "Provider_OpenRouter" }
        if id.contains("xai") || name.contains("xai") || name.contains("x.ai") { return "Provider_xAI" }
        if matches("google", "gemini") { return "Provider_Gemini" }
        if matches("groq") { return "Provider_Groq" }
        if matches("cerebras") { return "Provider_Cerebras" }
        if matches("ollama") { return "Provider_Ollama" }
        if matches("llamacpp", "llama.cpp") { return "Provider_Compatible" }
        if matches("lmstudio", "lm studio") { return "Provider_LMStudio" }
        if matches("apple") { return "Provider_AppleIntelligence" }
        if matches("compatible") { return "Provider_Compatible" }
        return nil
    }
}

// MARK: - Selectable Row Surface

/// Shared surface for rows that can be selected or expanded inside a card.
struct AIRowSurface: ViewModifier {
    @Environment(\.theme) private var theme
    var isSelected: Bool = false
    var isExpanded: Bool = false
    var isHovered: Bool = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        content
            .background(shape.fill(self.fill))
            .overlay(shape.strokeBorder(self.stroke, lineWidth: 1))
    }

    private var fill: Color {
        let palette = self.theme.palette
        if self.isSelected { return palette.accentSubtle }
        if self.isExpanded { return palette.surfaceRaised }
        if self.isHovered { return palette.surfaceHover }
        return palette.surfaceSunken
    }

    private var stroke: Color {
        if self.isSelected || self.isExpanded { return self.theme.palette.accent.opacity(0.55) }
        return self.theme.palette.hairline
    }
}

extension View {
    func aiRowSurface(isSelected: Bool = false, isExpanded: Bool = false, isHovered: Bool = false) -> some View {
        modifier(AIRowSurface(isSelected: isSelected, isExpanded: isExpanded, isHovered: isHovered))
    }
}

/// Radio indicator used by rows that pick one option from a set.
struct AIRadioMark: View {
    @Environment(\.theme) private var theme
    let isOn: Bool

    var body: some View {
        Image(systemName: self.isOn ? "checkmark.circle.fill" : "circle")
            .font(AppFont.icon)
            .foregroundStyle(self.isOn ? self.theme.palette.accentForeground : self.theme.palette.tertiaryText)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }
}

// MARK: - Field

/// Label above a form control, with optional trailing helper text.
struct AIField<Content: View>: View {
    @Environment(\.theme) private var theme
    let label: String
    var helper: String?
    @ViewBuilder var content: Content

    init(_ label: String, helper: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.helper = helper
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs + Space.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(self.label)
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(self.theme.palette.secondaryText)
                if let helper {
                    Text(helper)
                        .font(AppFont.caption)
                        .foregroundStyle(self.theme.palette.tertiaryText)
                }
            }
            self.content
        }
    }
}

// MARK: - Overview Card

/// Summary of what AI Enhancement is doing right now.
enum AIEnhancementSummary: Hashable {
    case off
    /// Configured and verified.
    case ready(provider: String, model: String)
    /// Configured (it will run) but the connection was never verified.
    case unverified(provider: String, model: String)
    /// Missing a base URL, key or model, so dictation falls back to the raw transcript.
    case incomplete(provider: String)
}

struct AIEnhancementOverviewCard: View {
    @Environment(\.theme) private var theme
    @Binding var isEnabled: Bool
    let summary: AIEnhancementSummary

    var body: some View {
        ThemedCard(style: .prominent) {
            VStack(alignment: .leading, spacing: Space.lg) {
                HStack(alignment: .top, spacing: Space.md) {
                    Image(systemName: "sparkles")
                        .font(AppFont.iconLarge)
                        .foregroundStyle(self.theme.palette.accentForeground)
                        .frame(width: AIEnhancementLayout.featureGlyph, height: AIEnhancementLayout.featureGlyph)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(self.theme.palette.accentSubtle)
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text("Enhance Dictation with AI")
                            .font(AppFont.bodyEmphasis)
                            .foregroundStyle(self.theme.palette.primaryText)
                        Text("Your transcript is sent to the provider you choose. Local providers keep it on this Mac.")
                            .font(AppFont.callout)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: Space.md)

                    Toggle("AI Enhancement", isOn: self.$isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityLabel("AI Enhancement")
                }

                self.statusLine
                    .motionTransition()
                    .id(self.summary)
            }
        }
    }

    private var statusLine: some View {
        let palette = self.theme.palette
        let (symbol, tint, text): (String, Color, String) = {
            switch self.summary {
            case .off:
                return ("text.cursor", palette.secondaryText, "Off — text is inserted exactly as transcribed.")
            case let .ready(provider, model):
                return ("checkmark.circle.fill", palette.success, "On — enhancing with \(Self.detail(provider, model)).")
            case let .unverified(provider, model):
                return (
                    "info.circle.fill",
                    palette.info,
                    "On — enhancing with \(Self.detail(provider, model)). Verify the connection below to catch setup problems early."
                )
            case let .incomplete(provider):
                return (
                    "exclamationmark.triangle.fill",
                    palette.warning,
                    "On, but \(provider) isn't set up yet, so text is inserted exactly as transcribed."
                )
            }
        }()

        return HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(AppFont.callout)
                .foregroundStyle(palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm + Space.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.surfaceSunken)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(text)")
    }

    private static func detail(_ provider: String, _ model: String) -> String {
        model.isEmpty ? provider : "\(provider) · \(model)"
    }
}

// MARK: - Setup Guide

struct AISetupGuide: View {
    @Environment(\.theme) private var theme

    private let steps: [(String, String)] = [
        ("square.grid.2x2", "Choose a provider below."),
        ("key", "Add its API key. Local providers like Ollama don't need one."),
        ("arrow.clockwise", "Refresh the model list and pick a model."),
        ("checkmark.shield", "Verify the connection."),
        ("text.bubble", "Optionally, choose or write a prompt for each mode."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("How to Set Up AI Enhancement")
                .font(AppFont.captionEmphasis)
                .foregroundStyle(self.theme.palette.primaryText)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(self.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Text("\(index + 1)")
                        .font(AppFont.micro)
                        .monospacedDigit()
                        .foregroundStyle(self.theme.palette.accentForeground)
                        .frame(width: Space.lg + Space.xxs, height: Space.lg + Space.xxs)
                        .background(Circle().fill(self.theme.palette.accentSubtle))
                        .accessibilityHidden(true)
                    Text(step.1)
                        .font(AppFont.callout)
                        .foregroundStyle(self.theme.palette.secondaryText)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(index + 1): \(step.1)")
            }
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - Provider Row Header

/// Logo, name and status badges for a provider row.
struct AIProviderRowLabel: View {
    @Environment(\.theme) private var theme
    let providerID: String
    let name: String
    var badges: [AIStatusKind] = []
    var detail: String?

    var body: some View {
        HStack(spacing: Space.md) {
            AIProviderLogo(providerID: self.providerID, name: self.name)
            VStack(alignment: .leading, spacing: Space.xxs) {
                HStack(spacing: Space.sm) {
                    Text(self.name)
                        .font(AppFont.rowTitle)
                        .foregroundStyle(self.theme.palette.primaryText)
                        .lineLimit(1)
                    ForEach(self.badges, id: \.title) { badge in
                        AIStatusBadge(kind: badge)
                    }
                }
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(AppFont.caption)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }
}

/// Collapsible row for a provider that is not verified yet.
struct AIProviderDisclosureRow<Details: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    let providerID: String
    let name: String
    let badges: [AIStatusKind]
    let isExpanded: Bool
    let onToggle: () -> Void
    @ViewBuilder var details: Details

    init(
        providerID: String,
        name: String,
        badges: [AIStatusKind],
        isExpanded: Bool,
        onToggle: @escaping () -> Void,
        @ViewBuilder details: () -> Details
    ) {
        self.providerID = providerID
        self.name = name
        self.badges = badges
        self.isExpanded = isExpanded
        self.onToggle = onToggle
        self.details = details()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: self.onToggle) {
                HStack(spacing: Space.md) {
                    AIProviderRowLabel(providerID: self.providerID, name: self.name, badges: self.badges)
                    Spacer(minLength: Space.sm)
                    Image(systemName: "chevron.right")
                        .font(AppFont.iconSmall)
                        .foregroundStyle(self.theme.palette.tertiaryText)
                        .rotationEffect(.degrees(self.isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.sm + Space.xxs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { self.isHovered = $0 }
            .accessibilityLabel(self.name)
            .accessibilityValue(self.badges.map(\.title).joined(separator: ", "))
            .accessibilityHint(self.isExpanded ? "Hides this provider's settings" : "Shows this provider's settings")

            if self.isExpanded {
                Rectangle()
                    .fill(self.theme.palette.separator)
                    .frame(height: 1)
                    .padding(.horizontal, Space.md)
                self.details
                    .padding(Space.lg)
                    .motionTransition(edge: .top)
            }
        }
        .aiRowSurface(isExpanded: self.isExpanded, isHovered: self.isHovered)
        .motion(Motion.state, value: self.isExpanded)
        .motion(Motion.snappy, value: self.isHovered)
    }
}

// MARK: - Prompt Row

struct AIPromptRow<MenuItems: View>: View {
    @Environment(\.theme) private var theme
    @State private var isHovered = false

    let title: String
    let preview: String
    let isSelected: Bool
    var badge: AIStatusKind?
    let onSelect: () -> Void
    @ViewBuilder var menuItems: MenuItems

    init(
        title: String,
        preview: String,
        isSelected: Bool,
        badge: AIStatusKind? = nil,
        onSelect: @escaping () -> Void,
        @ViewBuilder menuItems: () -> MenuItems
    ) {
        self.title = title
        self.preview = preview
        self.isSelected = isSelected
        self.badge = badge
        self.onSelect = onSelect
        self.menuItems = menuItems()
    }

    var body: some View {
        HStack(spacing: Space.sm) {
            Button(action: self.onSelect) {
                HStack(alignment: .center, spacing: Space.md) {
                    AIRadioMark(isOn: self.isSelected)
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        HStack(spacing: Space.sm) {
                            Text(self.title)
                                .font(AppFont.rowTitle)
                                .foregroundStyle(self.theme.palette.primaryText)
                                .lineLimit(1)
                            if let badge {
                                AIStatusBadge(kind: badge)
                            }
                        }
                        Text(self.preview)
                            .font(AppFont.caption)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(self.title)
            .accessibilityValue(self.preview)
            .accessibilityAddTraits(self.isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint("Uses this prompt")

            Menu {
                self.menuItems
            } label: {
                Image(systemName: "ellipsis")
                    .font(AppFont.icon)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .frame(width: Space.xxl - Space.xxs, height: Space.xxl - Space.xxs)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Prompt Options")
            .accessibilityLabel("Options for \(self.title)")
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm + Space.xxs)
        .aiRowSurface(isSelected: self.isSelected, isHovered: self.isHovered)
        .onHover { self.isHovered = $0 }
        .motion(Motion.snappy, value: self.isHovered)
        .motion(Motion.state, value: self.isSelected)
    }
}

// MARK: - Mode Group Header

struct AIPromptModeHeader: View {
    @Environment(\.theme) private var theme
    let mode: SettingsStore.PromptMode

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Image(systemName: Self.symbol(for: self.mode))
                .font(AppFont.icon)
                .foregroundStyle(self.theme.palette.accentForeground)
                .frame(width: Space.xl)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(Self.title(for: self.mode))
                    .font(AppFont.bodyEmphasis)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text(Self.description(for: self.mode))
                    .font(AppFont.caption)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    static func title(for mode: SettingsStore.PromptMode) -> String {
        switch mode.normalized {
        case .dictate: return "Dictate Mode"
        case .edit, .write, .rewrite: return "Edit Mode"
        }
    }

    static func shortName(for mode: SettingsStore.PromptMode) -> String {
        switch mode.normalized {
        case .dictate: return "Dictate"
        case .edit, .write, .rewrite: return "Edit"
        }
    }

    static func symbol(for mode: SettingsStore.PromptMode) -> String {
        switch mode.normalized {
        case .dictate: return "mic"
        case .edit, .write, .rewrite: return "square.and.pencil"
        }
    }

    static func description(for mode: SettingsStore.PromptMode) -> String {
        switch mode.normalized {
        case .dictate:
            return "Cleans up what you say before it's inserted — tidy prose, emails, terminal commands, translations."
        case .edit, .write, .rewrite:
            return "Works on the text you've selected — rewrite it, summarize it, answer a question about it, or turn it into a list."
        }
    }
}
