//
//  FeedbackView.swift
//  SayIt
//
//  Help & Feedback: status, shortcuts, troubleshooting and problem reports.
//

import ApplicationServices
import AVFoundation
import SwiftUI

struct FeedbackView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.theme) private var theme

    @State private var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var accessibilityTrusted = AXIsProcessTrusted()

    static let issuesURL = URL(string: "https://github.com/Keith-CY/sayit/issues/new")
    static let microphoneSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")

    var body: some View {
        ActivityUI.Page(
            "Help & Feedback",
            subtitle: "Check that SayIt is set up, look up a shortcut, or report a problem."
        ) {
            self.statusCard
            self.shortcutsCard
            self.troubleshootingCard
            self.reportCard
        }
        .onAppear(perform: self.refreshPermissions)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            self.refreshPermissions()
        }
    }

    // MARK: - Status

    private var statusCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: Space.lg) {
                ActivityUI.SectionTitle("Status")
                VStack(spacing: Space.md) {
                    StatusRow(
                        title: "Microphone",
                        detail: self.microphoneDetail,
                        isOK: self.microphoneStatus == .notDetermined ? nil : self.microphoneStatus == .authorized
                    ) {
                        if self.microphoneStatus == .denied || self.microphoneStatus == .restricted {
                            Button("Open Settings") { self.open(Self.microphoneSettingsURL) }
                                .buttonStyle(.sayIt(.secondary, size: .small))
                        }
                    }
                    Divider()
                    StatusRow(
                        title: "Accessibility",
                        detail: self.accessibilityTrusted
                            ? "Allowed. SayIt can type into other apps."
                            : "Not allowed. Shortcuts and typing into other apps won’t work.",
                        isOK: self.accessibilityTrusted
                    ) {
                        if !self.accessibilityTrusted {
                            Button("Open Settings") { self.open(Self.accessibilitySettingsURL) }
                                .buttonStyle(.sayIt(.secondary, size: .small))
                        }
                    }
                    Divider()
                    StatusRow(
                        title: "Speech Model",
                        detail: self.settings.selectedSpeechModel.displayName,
                        isOK: nil
                    ) { EmptyView() }
                    Divider()
                    StatusRow(
                        title: "Version",
                        detail: "SayIt \(AppVersion.current().displayName) on macOS \(Self.macOSVersion)",
                        isOK: nil
                    ) { EmptyView() }
                }
            }
        }
    }

    private var microphoneDetail: String {
        switch self.microphoneStatus {
        case .authorized: return "Allowed."
        case .denied: return "Not allowed. SayIt can’t hear you until you allow it."
        case .restricted: return "Restricted by your administrator or a device profile."
        case .notDetermined: return "Not requested yet. SayIt asks the first time you dictate."
        @unknown default: return "Unknown."
        }
    }

    // MARK: - Shortcuts

    private var shortcutsCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: Space.lg) {
                ActivityUI.SectionTitle("Keyboard Shortcuts")
                VStack(alignment: .leading, spacing: Space.md) {
                    ShortcutRow(action: "Dictate", keys: self.settings.hotkeyShortcut.displayString)
                    ShortcutRow(
                        action: "Edit Mode",
                        keys: self.settings.rewriteModeShortcutEnabled ? self.settings.rewriteModeHotkeyShortcut.displayString : nil
                    )
                    ShortcutRow(
                        action: "Command Mode",
                        keys: self.settings.commandModeShortcutEnabled ? self.settings.commandModeHotkeyShortcut.displayString : nil
                    )
                    ShortcutRow(action: "Cancel a dictation", keys: "Esc")
                }
                Text("Change shortcuts in Settings › General.")
                    .font(AppFont.caption)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }
        }
    }

    // MARK: - Troubleshooting

    private var troubleshootingCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: Space.lg) {
                ActivityUI.SectionTitle("Troubleshooting")
                VStack(alignment: .leading, spacing: Space.lg) {
                    TroubleshootingItem(
                        problem: "Nothing happens when I press the shortcut",
                        fix: "SayIt needs Accessibility access to listen for shortcuts. Allow it in System Settings. If shortcuts still don’t respond, quit and reopen SayIt."
                    )
                    TroubleshootingItem(
                        problem: "Recording starts, but no text appears",
                        fix: "Check that the microphone is allowed and that the right input device is selected in Settings › General. Text is typed into the app that was focused when you started."
                    )
                    TroubleshootingItem(
                        problem: "The speech model won’t download",
                        fix: "Open Settings › Voice Engine and download the model again. SayIt only offers a model for activation once its download is complete."
                    )
                    TroubleshootingItem(
                        problem: "Text comes out changed or translated",
                        fix: "Turn off AI Enhancement in Settings › AI Enhancement for a literal transcript."
                    )
                }
            }
        }
    }

    // MARK: - Report

    private var reportCard: some View {
        ThemedCard(style: .prominent) {
            VStack(alignment: .leading, spacing: Space.md) {
                ActivityUI.SectionTitle("Report a Problem")
                Text("Copy the diagnostics, then open an issue on GitHub and paste them in. Diagnostics list versions, settings and permissions — never your dictations.")
                    .font(AppFont.callout)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.sm) {
                    ActivityUI.CopyButton(text: self.diagnostics, title: "Copy Diagnostics", size: .regular)
                    Button("Open Logs Folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([FileLogger.shared.currentLogFileURL()])
                    }
                    .buttonStyle(.sayItSecondary)
                    Spacer()
                    Button("Report an Issue…") { self.open(Self.issuesURL) }
                        .buttonStyle(.sayItPrimary)
                }
            }
        }
    }

    /// Plain-text diagnostics. Contains no transcript text.
    var diagnostics: String {
        let microphone: String = {
            switch self.microphoneStatus {
            case .authorized: return "allowed"
            case .denied: return "denied"
            case .restricted: return "restricted"
            case .notDetermined: return "not requested"
            @unknown default: return "unknown"
            }
        }()
        return [
            "SayIt \(AppVersion.current().displayName)",
            "macOS \(Self.macOSVersion)",
            "Mac: \(Self.hardwareModel)",
            "Speech model: \(self.settings.selectedSpeechModel.displayName)",
            "AI Enhancement: \(self.settings.enableAIProcessing ? "on" : "off")",
            "History: \(self.settings.saveTranscriptionHistory ? "on" : "off")",
            "Microphone: \(microphone)",
            "Accessibility: \(self.accessibilityTrusted ? "allowed" : "not allowed")",
        ].joined(separator: "\n")
    }

    // MARK: - Helpers

    private func refreshPermissions() {
        self.microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        self.accessibilityTrusted = AXIsProcessTrusted()
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    private static var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static var hardwareModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Unknown" }
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}

// MARK: - Rows

private struct StatusRow<Accessory: View>: View {
    @Environment(\.theme) private var theme

    let title: String
    let detail: String
    /// `nil` for informational rows without a pass/fail state.
    let isOK: Bool?
    @ViewBuilder let accessory: Accessory

    private static var titleWidth: CGFloat { 120 }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.md) {
            Group {
                if let isOK {
                    Image(systemName: isOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(isOK ? self.theme.palette.success : self.theme.palette.warning)
                        .accessibilityLabel(isOK ? "OK" : "Needs attention")
                } else {
                    Image(systemName: "info.circle")
                        .foregroundStyle(self.theme.palette.tertiaryText)
                        .accessibilityHidden(true)
                }
            }
            .font(AppFont.icon)
            .frame(width: Space.xl)

            Text(self.title)
                .font(AppFont.rowTitle)
                .foregroundStyle(self.theme.palette.primaryText)
                .frame(width: Self.titleWidth, alignment: .leading)

            Text(self.detail)
                .font(AppFont.callout)
                .foregroundStyle(self.theme.palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Spacer(minLength: Space.sm)
            self.accessory
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ShortcutRow: View {
    @Environment(\.theme) private var theme

    let action: String
    let keys: String?

    private static let actionWidth: CGFloat = 180

    var body: some View {
        HStack(spacing: Space.xl) {
            Text(self.action)
                .font(AppFont.body)
                .foregroundStyle(self.theme.palette.primaryText)
                .frame(width: Self.actionWidth, alignment: .leading)
            if let keys = self.keys {
                ActivityUI.KeyCap(keys)
            } else {
                Text("Off")
                    .font(AppFont.callout)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TroubleshootingItem: View {
    @Environment(\.theme) private var theme

    let problem: String
    let fix: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(self.problem)
                .font(AppFont.rowTitle)
                .foregroundStyle(self.theme.palette.primaryText)
            Text(self.fix)
                .font(AppFont.callout)
                .foregroundStyle(self.theme.palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    FeedbackView()
        .frame(width: 720, height: 900)
        .sayItTheme()
}
