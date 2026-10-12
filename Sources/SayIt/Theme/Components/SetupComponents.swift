//
//  SetupComponents.swift
//  SayIt
//
//  Building blocks for Home: setup steps, status rows and key caps.
//

import SwiftUI

// MARK: - Setup Step Row

enum SetupStepStatus: Equatable {
    /// Not started and not the next step.
    case pending
    /// The next thing the user should do.
    case current
    /// Work in progress (downloading, loading).
    case working
    /// Cannot be completed from SayIt (e.g. microphone restricted by device management).
    case blocked
    case completed

    var accessibilityValue: String {
        switch self {
        case .pending, .current: return "Not done"
        case .working: return "In progress"
        case .blocked: return "Blocked"
        case .completed: return "Done"
        }
    }
}

/// One step of the setup checklist. Completion is conveyed by the indicator, the
/// trailing “Done” label and the accessibility value — never by disabling the row.
struct SetupStepRow<Detail: View, Action: View>: View {
    @Environment(\.theme) private var theme

    let number: Int
    let title: String
    let description: String
    let status: SetupStepStatus
    private let detail: Detail
    private let action: Action

    init(
        number: Int,
        title: String,
        description: String,
        status: SetupStepStatus,
        @ViewBuilder detail: () -> Detail,
        @ViewBuilder action: () -> Action
    ) {
        self.number = number
        self.title = title
        self.description = description
        self.status = status
        self.detail = detail()
        self.action = action()
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            SetupStepIndicator(number: self.number, status: self.status)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Space.xs) {
                Text(self.title)
                    .font(AppFont.rowTitle)
                    .foregroundStyle(self.titleColor)
                Text(self.description)
                    .font(AppFont.callout)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                self.detail
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityValue(self.status.accessibilityValue)

            if self.status == .completed {
                Text("Done")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .accessibilityHidden(true)
                    .motionTransition()
            } else {
                self.action
            }
        }
        .padding(.vertical, Space.sm)
        .motion(Motion.emphasis, value: self.status)
    }

    private var titleColor: Color {
        self.status == .completed ? self.theme.palette.secondaryText : self.theme.palette.primaryText
    }
}

struct SetupStepIndicator: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let number: Int
    let status: SetupStepStatus

    private let size: CGFloat = 24

    var body: some View {
        ZStack {
            Circle()
                .fill(self.fill)
            Circle()
                .strokeBorder(self.stroke, lineWidth: 1.5)

            switch self.status {
            case .completed:
                Image(systemName: "checkmark")
                    .font(AppFont.micro)
                    .foregroundStyle(self.theme.palette.success)
                    .transition(self.reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
            case .working:
                ProgressView()
                    .controlSize(.mini)
            case .blocked:
                Image(systemName: "minus")
                    .font(AppFont.micro)
                    .foregroundStyle(self.theme.palette.warning)
            case .pending, .current:
                Text("\(self.number)")
                    .font(AppFont.micro)
                    .monospacedDigit()
                    .foregroundStyle(
                        self.status == .current ? self.theme.palette.accentForeground : self.theme.palette.tertiaryText
                    )
            }
        }
        .frame(width: self.size, height: self.size)
    }

    private var fill: Color {
        switch self.status {
        case .completed: return self.theme.palette.subtle(self.theme.palette.success)
        case .current: return self.theme.palette.accentSubtle
        case .blocked: return self.theme.palette.subtle(self.theme.palette.warning)
        case .pending, .working: return .clear
        }
    }

    private var stroke: Color {
        switch self.status {
        case .completed: return self.theme.palette.success.opacity(0.5)
        case .current: return self.theme.palette.accentForeground
        case .blocked: return self.theme.palette.warning.opacity(0.5)
        case .pending, .working: return self.theme.palette.hairline
        }
    }
}

// MARK: - Status Row

/// Label + state + optional action, used by the Home status card once setup is done.
struct StatusRow<Trailing: View>: View {
    @Environment(\.theme) private var theme

    let systemImage: String
    let title: String
    let value: String
    var tone: Tone = .neutral
    private let trailing: Trailing

    enum Tone {
        case neutral
        case good
        case attention
    }

    init(
        systemImage: String,
        title: String,
        value: String,
        tone: Tone = .neutral,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.systemImage = systemImage
        self.title = title
        self.value = value
        self.tone = tone
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: self.systemImage)
                .font(AppFont.icon)
                .foregroundStyle(self.theme.palette.secondaryText)
                .frame(width: Space.xl)
                .accessibilityHidden(true)

            Text(self.title)
                .font(AppFont.rowTitle)
                .foregroundStyle(self.theme.palette.primaryText)

            Spacer(minLength: Space.md)

            HStack(spacing: Space.xs) {
                if self.tone != .neutral {
                    Image(systemName: self.tone == .good ? "checkmark.circle" : "exclamationmark.circle")
                        .font(AppFont.iconSmall)
                        .foregroundStyle(self.tone == .good ? self.theme.palette.success : self.theme.palette.warning)
                        .accessibilityHidden(true)
                }
                Text(self.value)
                    .font(AppFont.callout)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .lineLimit(1)
            }

            self.trailing
        }
        .padding(.vertical, Space.sm)
        .accessibilityElement(children: .combine)
    }
}

extension StatusRow where Trailing == EmptyView {
    init(systemImage: String, title: String, value: String, tone: Tone = .neutral) {
        self.init(systemImage: systemImage, title: title, value: value, tone: tone) { EmptyView() }
    }
}

// MARK: - Key Cap

/// Renders a keyboard shortcut as a key cap (“⌥ Right”, “⌘ + K”).
struct KeyCap: View {
    @Environment(\.theme) private var theme
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(self.text)
            .font(AppFont.Overlay.keyCap)
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
            .accessibilityLabel("Shortcut \(self.text)")
    }
}

// MARK: - Inline Progress

/// Determinate (or indeterminate when `fraction` is nil) progress with a caption.
struct InlineProgress: View {
    @Environment(\.theme) private var theme
    let fraction: Double?
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let fraction {
                ProgressView(value: min(max(fraction, 0), 1))
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            Text(self.caption)
                .font(AppFont.caption)
                .foregroundStyle(self.theme.palette.secondaryText)
                .monospacedDigit()
        }
        .tint(self.theme.palette.accent)
        .padding(.top, Space.xs)
        .accessibilityElement(children: .combine)
    }
}
