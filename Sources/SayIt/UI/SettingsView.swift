//
//  SettingsView.swift
//  SayIt
//
//  The General settings page: permissions, shortcuts, recording, output, overlay,
//  app behavior and updates.
//

import AVFoundation
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appServices: AppServices
    private var asr: ASRService { self.appServices.asr }
    @Environment(\.theme) private var theme
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var updateController = UpdateController.shared
    @Binding var appear: Bool
    @Binding var visualizerNoiseThreshold: Double
    @Binding var selectedInputUID: String
    @Binding var selectedOutputUID: String
    @Binding var inputDevices: [AudioDevice.Device]
    @Binding var outputDevices: [AudioDevice.Device]
    @Binding var accessibilityEnabled: Bool
    @Binding var hotkeyShortcut: HotkeyShortcut
    @Binding var isRecordingShortcut: Bool
    @Binding var commandModeShortcut: HotkeyShortcut
    @Binding var isRecordingCommandModeShortcut: Bool
    @Binding var rewriteShortcut: HotkeyShortcut
    @Binding var isRecordingRewriteShortcut: Bool
    @Binding var commandModeShortcutEnabled: Bool
    @Binding var rewriteShortcutEnabled: Bool
    @Binding var hotkeyManagerInitialized: Bool
    @Binding var pressAndHoldModeEnabled: Bool
    @Binding var enableStreamingPreview: Bool
    @Binding var copyToClipboard: Bool

    // CRITICAL FIX: Cache default device names to avoid CoreAudio calls during view body evaluation.
    // Querying AudioDevice.getDefaultInputDevice() in the view body triggers HALSystem::InitializeShell()
    // which races with SwiftUI's AttributeGraph metadata processing and causes EXC_BAD_ACCESS crashes.
    @State private var cachedDefaultInputName: String = ""
    @State private var cachedDefaultOutputName: String = ""
    @State private var showAccessibilitySteps = false

    let hotkeyManager: GlobalHotkeyManager?
    let menuBarManager: MenuBarManager
    let startRecording: () -> Void
    let refreshDevices: () -> Void
    let openAccessibilitySettings: () -> Void
    let restartApp: () -> Void
    let revealAppInFinder: () -> Void
    let openApplicationsFolder: () -> Void

    private static let defaultNoiseThreshold = 0.4

    var body: some View {
        SettingsKit.Page(
            title: "General",
            subtitle: "How SayIt listens, where it writes, and how it starts."
        ) {
            self.permissionsSection
            self.shortcutsSection
            self.recordingSection
            self.outputSection
            self.overlaySection
            self.appSection
            self.updatesSection
        }
        .onAppear {
            self.updateController.refreshStatus()

            Task { @MainActor in
                // Ensure the shared audio startup gate is scheduled. Safe to call repeatedly.
                await AudioStartupGate.shared.scheduleOpenAfterInitialUISettled()
                await AudioStartupGate.shared.waitUntilOpen()

                self.refreshDevices()
                self.syncInputSelection(with: self.inputDevices)
                self.syncOutputSelection(with: self.outputDevices)

                // CRITICAL FIX: Populate cached default device names after onAppear, not during view body evaluation.
                // This avoids the CoreAudio/SwiftUI AttributeGraph race condition that causes EXC_BAD_ACCESS.
                self.cachedDefaultInputName = AudioDevice.getDefaultInputDevice()?.name ?? ""
                self.cachedDefaultOutputName = AudioDevice.getDefaultOutputDevice()?.name ?? ""
            }
        }
        .onChange(of: self.visualizerNoiseThreshold) { _, newValue in
            SettingsStore.shared.visualizerNoiseThreshold = newValue
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        SettingsKit.Section(
            "Permissions",
            footer: "SayIt only listens after you start dictating. Audio never leaves this Mac."
        ) {
            self.microphoneRow
            SettingsKit.RowDivider()
            self.accessibilityRow

            if !self.accessibilityEnabled {
                self.accessibilityHelp
            }
        }
    }

    private var microphoneRow: some View {
        let status = self.asr.micStatus
        return SettingsKit.Row(
            "Microphone",
            description: self.microphoneDescription(for: status),
            systemImage: "mic"
        ) {
            switch status {
            case .authorized:
                SettingsKit.StatusBadge(text: "Allowed", systemImage: "checkmark.circle.fill", tone: .success)
            case .notDetermined:
                Button("Allow Access") {
                    self.asr.requestMicAccess()
                }
                .buttonStyle(.sayItPrimary)
            case .denied:
                Button("Open System Settings") {
                    self.asr.openSystemSettingsForMic()
                }
                .buttonStyle(.sayItSecondary)
            default:
                SettingsKit.StatusBadge(text: "Restricted", systemImage: "lock", tone: .warning)
            }
        }
    }

    private func microphoneDescription(for status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "SayIt can hear you when you start dictating."
        case .notDetermined:
            return "Needed to hear your voice. Choose Allow when macOS asks."
        case .denied:
            return "Access is off. Turn on SayIt in System Settings › Privacy & Security › Microphone."
        default:
            return "This Mac restricts microphone access, for example through a management profile."
        }
    }

    private var accessibilityRow: some View {
        SettingsKit.Row(
            "Accessibility",
            description: self.accessibilityEnabled
                ? "Lets SayIt respond to shortcuts and type into other apps."
                : "Needed for keyboard shortcuts and for typing into other apps.",
            systemImage: "accessibility"
        ) {
            if self.accessibilityEnabled {
                SettingsKit.StatusBadge(text: "Allowed", systemImage: "checkmark.circle.fill", tone: .success)
            } else {
                // One primary action per page: the microphone comes first when both are missing.
                Button("Open System Settings") {
                    self.openAccessibilitySettings()
                }
                .buttonStyle(SayItButtonStyle(role: self.asr.micStatus == .notDetermined ? .secondary : .primary))
            }
        }
    }

    private var accessibilityHelp: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            DisclosureGroup(isExpanded: self.$showAccessibilitySteps) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    self.numberedStep(1, "Click **Open System Settings**.")
                    self.numberedStep(2, "If SayIt isn’t listed, click **+** and choose SayIt from Applications.")
                    self.numberedStep(3, "Turn on **SayIt**.")

                    HStack(spacing: Space.sm) {
                        Button("Show SayIt in Finder") { self.revealAppInFinder() }
                            .buttonStyle(.sayIt(.quiet, size: .small))
                        Button("Open Applications Folder") { self.openApplicationsFolder() }
                            .buttonStyle(.sayIt(.quiet, size: .small))
                    }
                }
                .padding(.top, Space.sm)
            } label: {
                Text("How to allow Accessibility")
                    .font(AppFont.callout)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.bottom, Space.md)
        .padding(.leading, Space.xl + Space.md)
    }

    private func numberedStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Text("\(number).")
                .font(AppFont.captionEmphasis)
                .foregroundStyle(self.theme.palette.accentForeground)
                .monospacedDigit()
            Text(.init(text))
                .font(AppFont.callout)
                .foregroundStyle(self.theme.palette.primaryText)
        }
    }

    // MARK: - Shortcuts

    private var isCapturingShortcut: Bool {
        self.isRecordingShortcut || self.isRecordingCommandModeShortcut || self.isRecordingRewriteShortcut
    }

    private var shortcutsSection: some View {
        SettingsKit.Section(
            "Keyboard Shortcuts",
            footer: self.accessibilityEnabled
                ? "Shortcuts work in every app. Press Esc while recording to cancel."
                : "Shortcuts start working once Accessibility is allowed above.",
            accessory: { self.shortcutStatusBadge }
        ) {
            self.shortcutRow(
                systemImage: "mic",
                title: "Dictate Mode",
                description: "Speak and SayIt types what you said.",
                shortcut: self.hotkeyShortcut,
                isCapturing: self.isRecordingShortcut,
                onChange: {
                    DebugLogger.shared.debug("Starting to record new dictate shortcut", source: "SettingsView")
                    self.isRecordingShortcut = true
                }
            )
            SettingsKit.RowDivider()
            self.shortcutRow(
                systemImage: "pencil.and.outline",
                title: "Edit Mode",
                description: "Select text, then say how to change it — or ask for new text.",
                shortcut: self.rewriteShortcut,
                isCapturing: self.isRecordingRewriteShortcut,
                isEnabled: self.$rewriteShortcutEnabled,
                onChange: {
                    DebugLogger.shared.debug("Starting to record new edit shortcut", source: "SettingsView")
                    self.isRecordingRewriteShortcut = true
                }
            )
            SettingsKit.RowDivider()
            self.shortcutRow(
                systemImage: "terminal",
                title: "Command Mode",
                description: "Ask SayIt to do something on your Mac.",
                shortcut: self.commandModeShortcut,
                isCapturing: self.isRecordingCommandModeShortcut,
                isEnabled: self.$commandModeShortcutEnabled,
                onChange: {
                    DebugLogger.shared.debug("Starting to record new command mode shortcut", source: "SettingsView")
                    self.isRecordingCommandModeShortcut = true
                }
            )
            SettingsKit.RowDivider()
            SettingsKit.ToggleRow(
                "Hold shortcut to record",
                description: "Records only while you hold the shortcut. Release it to finish.",
                systemImage: "hand.tap",
                isOn: self.$pressAndHoldModeEnabled
            )
            .onChange(of: self.pressAndHoldModeEnabled) { _, newValue in
                SettingsStore.shared.pressAndHoldMode = newValue
                self.hotkeyManager?.enablePressAndHoldMode(newValue)
            }
        }
    }

    @ViewBuilder
    private var shortcutStatusBadge: some View {
        if !self.accessibilityEnabled {
            SettingsKit.StatusBadge(text: "Needs Accessibility", systemImage: "exclamationmark.triangle.fill", tone: .warning)
        } else if self.isCapturingShortcut {
            SettingsKit.StatusBadge(text: "Press new shortcut…", systemImage: "keyboard", tone: .info)
        } else if self.hotkeyManagerInitialized {
            SettingsKit.StatusBadge(text: "Active", systemImage: "checkmark.circle.fill", tone: .success)
        } else {
            SettingsKit.StatusBadge(text: "Starting…", systemImage: "hourglass", tone: .neutral)
        }
    }

    private func shortcutRow(
        systemImage: String,
        title: String,
        description: String,
        shortcut: HotkeyShortcut,
        isCapturing: Bool,
        isEnabled: Binding<Bool>? = nil,
        onChange: @escaping () -> Void
    ) -> some View {
        let enabled = isEnabled?.wrappedValue ?? true
        let canEdit = self.accessibilityEnabled && enabled

        return SettingsKit.Row(title, description: description, systemImage: systemImage) {
            HStack(spacing: Space.sm) {
                if isCapturing && enabled {
                    Text("Press keys…")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(self.theme.palette.info)
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, Space.xs)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(self.theme.palette.subtle(self.theme.palette.info))
                        )
                        .accessibilityLabel("Waiting for the new \(title) shortcut")
                } else {
                    SettingsKit.KeyCap(text: shortcut.displayString)
                        .opacity(enabled ? 1 : 0.5)
                }

                Button("Change…") {
                    onChange()
                }
                .buttonStyle(.sayIt(.secondary, size: .small))
                .disabled(isCapturing || !canEdit)
                .accessibilityLabel("Change \(title) shortcut")

                if let isEnabled {
                    Toggle("Enable \(title)", isOn: isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!self.accessibilityEnabled)
                }
            }
        }
    }

    // MARK: - Recording

    private var recordingSection: some View {
        SettingsKit.Section(
            "Recording",
            footer: self.asr.isRunning
                ? "Devices can’t be changed while you’re recording."
                : "Changing a device here also changes it in macOS Sound settings.",
            accessory: {
                IconButton("Refresh Devices", systemName: "arrow.clockwise") {
                    self.refreshDevices()
                    // Update cached default device names on refresh
                    self.cachedDefaultInputName = AudioDevice.getDefaultInputDevice()?.name ?? ""
                    self.cachedDefaultOutputName = AudioDevice.getDefaultOutputDevice()?.name ?? ""
                }
            }
        ) {
            SettingsKit.Row("Microphone", description: "The input SayIt records from.", systemImage: "mic") {
                self.devicePicker(
                    title: "Microphone",
                    selection: self.$selectedInputUID,
                    devices: self.inputDevices,
                    defaultName: self.cachedDefaultInputName
                )
                .onChange(of: self.selectedInputUID) { oldUID, newUID in
                    guard !newUID.isEmpty else { return }

                    // Prevent device changes during active recording
                    if self.asr.isRunning {
                        DebugLogger.shared.warning("Cannot change input device during recording", source: "SettingsView")
                        self.selectedInputUID = oldUID
                        return
                    }

                    SettingsStore.shared.preferredInputDeviceUID = newUID
                    if SettingsStore.shared.syncAudioDevicesWithSystem {
                        _ = AudioDevice.setDefaultInputDevice(uid: newUID)
                    }
                }
                .onChange(of: self.inputDevices) { _, newDevices in
                    self.cachedDefaultInputName = AudioDevice.getDefaultInputDevice()?.name ?? ""
                    self.syncInputSelection(with: newDevices)
                }
            }
            SettingsKit.RowDivider()
            SettingsKit.Row("Sound output", description: "Where SayIt plays its sounds.", systemImage: "speaker.wave.2") {
                self.devicePicker(
                    title: "Sound output",
                    selection: self.$selectedOutputUID,
                    devices: self.outputDevices,
                    defaultName: self.cachedDefaultOutputName
                )
                .onChange(of: self.selectedOutputUID) { oldUID, newUID in
                    guard !newUID.isEmpty else { return }

                    if self.asr.isRunning {
                        DebugLogger.shared.warning("Cannot change output device during recording", source: "SettingsView")
                        self.selectedOutputUID = oldUID
                        return
                    }

                    SettingsStore.shared.preferredOutputDeviceUID = newUID
                    if SettingsStore.shared.syncAudioDevicesWithSystem {
                        _ = AudioDevice.setDefaultOutputDevice(uid: newUID)
                    }
                }
                .onChange(of: self.outputDevices) { _, newDevices in
                    self.cachedDefaultOutputName = AudioDevice.getDefaultOutputDevice()?.name ?? ""
                    self.syncOutputSelection(with: newDevices)
                }
            }
            SettingsKit.RowDivider()
            SettingsKit.Row("Start sound", description: "Plays when recording begins.", systemImage: "bell") {
                Picker("Start sound", selection: Binding(
                    get: { SettingsStore.shared.transcriptionStartSound },
                    set: { SettingsStore.shared.transcriptionStartSound = $0 }
                )) {
                    ForEach(SettingsStore.TranscriptionStartSound.allCases) { option in
                        Text(option.uiName).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: SettingsKit.pickerWidth)
            }
            SettingsKit.RowDivider()
            SettingsKit.ToggleRow(
                "Pause media while recording",
                description: "Pauses music or video when you start and resumes it afterwards, if SayIt paused it.",
                systemImage: "pause.circle",
                isOn: Binding(
                    get: { SettingsStore.shared.pauseMediaDuringTranscription },
                    set: { SettingsStore.shared.pauseMediaDuringTranscription = $0 }
                )
            )
        }
    }

    private func devicePicker(
        title: String,
        selection: Binding<String>,
        devices: [AudioDevice.Device],
        defaultName: String
    ) -> some View {
        Picker(title, selection: selection) {
            if devices.isEmpty {
                Text("Looking for devices…").tag("")
            } else {
                ForEach(devices, id: \.uid) { device in
                    // Use the cached default name to avoid CoreAudio calls during layout
                    let isSystemDefault = !defaultName.isEmpty && device.name == defaultName
                    Text(isSystemDefault ? "\(device.name) (System Default)" : device.name).tag(device.uid)
                }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: SettingsKit.pickerWidth)
        .disabled(self.asr.isRunning)
    }

    private func syncInputSelection(with devices: [AudioDevice.Device]) {
        guard !devices.isEmpty else { return }
        guard self.selectedInputUID.isEmpty || !devices.contains(where: { $0.uid == self.selectedInputUID }) else { return }

        if let preferredUID = SettingsStore.shared.preferredInputDeviceUID,
           devices.contains(where: { $0.uid == preferredUID })
        {
            self.selectedInputUID = preferredUID
        } else if let defaultUID = AudioDevice.getDefaultInputDevice()?.uid,
                  devices.contains(where: { $0.uid == defaultUID })
        {
            self.selectedInputUID = defaultUID
        } else {
            self.selectedInputUID = devices.first?.uid ?? ""
        }
    }

    private func syncOutputSelection(with devices: [AudioDevice.Device]) {
        guard !devices.isEmpty else { return }
        guard self.selectedOutputUID.isEmpty || !devices.contains(where: { $0.uid == self.selectedOutputUID }) else { return }

        if let preferredUID = SettingsStore.shared.preferredOutputDeviceUID,
           devices.contains(where: { $0.uid == preferredUID })
        {
            self.selectedOutputUID = preferredUID
        } else if let defaultUID = AudioDevice.getDefaultOutputDevice()?.uid,
                  devices.contains(where: { $0.uid == defaultUID })
        {
            self.selectedOutputUID = defaultUID
        } else {
            self.selectedOutputUID = devices.first?.uid ?? ""
        }
    }

    // MARK: - Output

    private var outputSection: some View {
        SettingsKit.Section("Output") {
            SettingsKit.ToggleRow(
                "Also copy to the clipboard",
                description: "Keeps each dictation on the clipboard in case typing into an app fails.",
                systemImage: "doc.on.clipboard",
                isOn: self.$copyToClipboard
            )
            .onChange(of: self.copyToClipboard) { _, newValue in
                SettingsStore.shared.copyTranscriptionToClipboard = newValue
            }
            SettingsKit.RowDivider()
            SettingsKit.ToggleRow(
                "Skip capitalization and final period",
                description: "Writes short entries like search queries and form fields as spoken: no capital first letter, no trailing period.",
                systemImage: "textformat",
                isOn: Binding(
                    get: { SettingsStore.shared.gaavModeEnabled },
                    set: { SettingsStore.shared.gaavModeEnabled = $0 }
                )
            )
            SettingsKit.RowDivider()
            SettingsKit.ToggleRow(
                "Save transcription history",
                description: "Keeps your dictations on this Mac so you can find them in History.",
                systemImage: "clock.arrow.circlepath",
                isOn: Binding(
                    get: { SettingsStore.shared.saveTranscriptionHistory },
                    set: { SettingsStore.shared.saveTranscriptionHistory = $0 }
                )
            )
        }
    }

    // MARK: - Overlay

    private var overlaySection: some View {
        SettingsKit.Section(
            "Recording Overlay",
            footer: "The overlay shows that SayIt is listening and what it heard."
        ) {
            SettingsKit.Row("Position", description: "Where the overlay appears while you dictate.", systemImage: "rectangle.topthird.inset.filled") {
                Picker("Position", selection: self.$settings.overlayPosition) {
                    ForEach(SettingsStore.OverlayPosition.allCases, id: \.self) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: SettingsKit.pickerWidth)
            }

            if self.settings.overlayPosition == .bottom {
                SettingsKit.RowDivider()
                SettingsKit.Row("Size", description: "How large the overlay appears.", systemImage: "arrow.up.left.and.arrow.down.right") {
                    Picker("Size", selection: self.$settings.overlaySize) {
                        ForEach(SettingsStore.OverlaySize.allCases, id: \.self) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: SettingsKit.pickerWidth)
                }
                SettingsKit.RowDivider()
                self.sliderRow(
                    SliderSpec(
                        title: "Distance from bottom",
                        description: "Space between the overlay and the bottom of the screen.",
                        systemImage: "arrow.up.to.line",
                        range: 20...500,
                        step: 1,
                        valueLabel: "\(Int(self.settings.overlayBottomOffset)) pt"
                    ),
                    value: self.$settings.overlayBottomOffset
                )
            }

            SettingsKit.RowDivider()
            SettingsKit.ToggleRow(
                "Show live transcript",
                description: "Shows words in the overlay as you speak.",
                systemImage: "text.bubble",
                isOn: self.$enableStreamingPreview
            )
            .onChange(of: self.enableStreamingPreview) { _, newValue in
                SettingsStore.shared.enableStreamingPreview = newValue
            }
            SettingsKit.RowDivider()
            self.sliderRow(
                SliderSpec(
                    title: "Preview length",
                    description: "How much of the latest transcript the overlay shows.",
                    systemImage: "text.alignleft",
                    range: Double(SettingsStore.transcriptionPreviewCharLimitRange.lowerBound)...Double(SettingsStore.transcriptionPreviewCharLimitRange.upperBound),
                    step: Double(SettingsStore.transcriptionPreviewCharLimitStep),
                    valueLabel: CopyFormat.count(self.settings.transcriptionPreviewCharLimit, "character"),
                    minimumLabel: "Less",
                    maximumLabel: "More"
                ),
                value: Binding(
                    get: { Double(self.settings.transcriptionPreviewCharLimit) },
                    set: { self.settings.transcriptionPreviewCharLimit = Int($0.rounded()) }
                )
            )
            SettingsKit.RowDivider()
            self.sliderRow(
                SliderSpec(
                    title: "Meter sensitivity",
                    description: "How much sound it takes to move the level meter.",
                    systemImage: "waveform",
                    range: 0.01...0.8,
                    step: 0.01,
                    minimumLabel: "More",
                    maximumLabel: "Less"
                ),
                value: self.$visualizerNoiseThreshold
            ) {
                Button("Reset") {
                    self.visualizerNoiseThreshold = Self.defaultNoiseThreshold
                    SettingsStore.shared.visualizerNoiseThreshold = self.visualizerNoiseThreshold
                }
                .buttonStyle(.sayIt(.quiet, size: .small))
                .disabled(abs(self.visualizerNoiseThreshold - Self.defaultNoiseThreshold) < 0.001)
                .accessibilityLabel("Reset meter sensitivity")
            }
        }
    }

    private struct SliderSpec {
        let title: String
        let description: String
        let systemImage: String
        let range: ClosedRange<Double>
        let step: Double
        var valueLabel: String?
        var minimumLabel: String?
        var maximumLabel: String?
    }

    private func sliderRow(_ spec: SliderSpec, value: Binding<Double>) -> some View {
        self.sliderRow(spec, value: value) { EmptyView() }
    }

    private func sliderRow<Trailing: View>(
        _ spec: SliderSpec,
        value: Binding<Double>,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        SettingsKit.Row(spec.title, description: spec.description, systemImage: spec.systemImage) {
            HStack(spacing: Space.sm) {
                Slider(value: value, in: spec.range, step: spec.step) {
                    Text(spec.title)
                } minimumValueLabel: {
                    Text(spec.minimumLabel ?? "")
                        .font(AppFont.caption)
                        .foregroundStyle(self.theme.palette.secondaryText)
                } maximumValueLabel: {
                    Text(spec.maximumLabel ?? "")
                        .font(AppFont.caption)
                        .foregroundStyle(self.theme.palette.secondaryText)
                }
                .labelsHidden()
                .frame(width: SettingsKit.sliderWidth)
                .accessibilityValue(spec.valueLabel ?? value.wrappedValue.formatted(.number.precision(.fractionLength(2))))

                // One fixed-width column for the value or an action, so slider rows align.
                HStack(spacing: 0) {
                    if let valueLabel = spec.valueLabel {
                        Text(valueLabel)
                            .font(AppFont.caption)
                            .monospacedDigit()
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .accessibilityHidden(true)
                    }
                    trailing()
                }
                .frame(width: SettingsKit.valueLabelWidth, alignment: .leading)
            }
        }
    }

    // MARK: - App

    private var appSection: some View {
        SettingsKit.Section("App") {
            SettingsKit.ToggleRow(
                "Open at login",
                description: "Starts SayIt in the menu bar when you log in.",
                systemImage: "power",
                isOn: Binding(
                    get: { SettingsStore.shared.launchAtStartup },
                    set: { SettingsStore.shared.launchAtStartup = $0 }
                )
            )
            SettingsKit.RowDivider()
            SettingsKit.ToggleRow(
                "Hide from Dock and ⌘-Tab",
                description: "Keeps SayIt in the menu bar only. May take effect after SayIt restarts.",
                systemImage: "dock.rectangle",
                isOn: Binding(
                    get: { SettingsStore.shared.hideFromDockAndAppSwitcher },
                    set: { SettingsStore.shared.hideFromDockAndAppSwitcher = $0 }
                )
            )
            SettingsKit.RowDivider()
            SettingsKit.Row("Accent color", description: "Colors buttons, switches and selections.", systemImage: "paintpalette") {
                self.accentSwatches
            }
            SettingsKit.RowDivider()
            SettingsKit.ToggleRow(
                "Don’t count weekends against streaks",
                description: "Streaks in Stats skip Saturdays and Sundays.",
                systemImage: "calendar",
                isOn: Binding(
                    get: { SettingsStore.shared.weekendsDontBreakStreak },
                    set: { SettingsStore.shared.weekendsDontBreakStreak = $0 }
                )
            )
        }
    }

    private var accentSwatches: some View {
        HStack(spacing: Space.xs) {
            ForEach(SettingsStore.AccentColorOption.allCases) { option in
                let isSelected = self.settings.accentColorOption == option
                Button {
                    withMotion(Motion.snappy) {
                        self.settings.accentColorOption = option
                    }
                } label: {
                    Circle()
                        .fill(Color(hex: option.hex) ?? self.theme.palette.secondaryText)
                        .frame(width: AccentSwatch.diameter, height: AccentSwatch.diameter)
                        .padding(AccentSwatch.ringGap)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    isSelected ? self.theme.palette.primaryText : .clear,
                                    lineWidth: AccentSwatch.ringWidth
                                )
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(option.rawValue)
                .accessibilityLabel(option.rawValue)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private enum AccentSwatch {
        static let diameter: CGFloat = 16
        static let ringGap: CGFloat = 3
        static let ringWidth: CGFloat = 1.5
    }

    // MARK: - Updates

    private var updatesSection: some View {
        SettingsKit.Section(
            "Software Updates",
            footer: "Updates are checked against SayIt’s signing key before they install.",
            accessory: {
                Text("Version \(self.updateController.currentVersion.displayName)")
                    .font(AppFont.caption)
                    .monospacedDigit()
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .textSelection(.enabled)
            }
        ) {
            SettingsKit.ToggleRow(
                "Check for updates automatically",
                description: "Checks GitHub Releases once a day. SayIt always asks before installing.",
                systemImage: "arrow.triangle.2.circlepath",
                isOn: Binding(
                    get: { self.updateController.automaticChecksEnabled },
                    set: { self.updateController.setAutomaticChecksEnabled($0) }
                )
            )
            SettingsKit.RowDivider()
            SettingsKit.Row(
                "Check now",
                description: self.updateController.lastCheckDate.map {
                    "Last checked \($0.formatted(date: .abbreviated, time: .shortened))."
                } ?? "Not checked yet.",
                systemImage: "arrow.clockwise"
            ) {
                HStack(spacing: Space.sm) {
                    Button("Release Notes") {
                        self.updateController.openReleasesPage()
                    }
                    .buttonStyle(.sayItQuiet)

                    Button("Check for Updates") {
                        self.updateController.checkForUpdates()
                    }
                    .buttonStyle(.sayItSecondary)
                }
            }

            if let lastErrorMessage = self.updateController.lastErrorMessage {
                SettingsKit.Notice(.warning, title: "The last update check didn’t finish", message: lastErrorMessage)
                    .padding([.horizontal, .bottom], Space.lg)
            }
        }
    }
}

// MARK: - Filler Words Editor

struct FillerWordsEditor: View {
    @State private var fillerWords: [String] = SettingsStore.shared.fillerWords
    @State private var newWord: String = ""
    @Environment(\.theme) private var theme

    private var trimmedNewWord: String {
        self.newWord.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private var isDuplicate: Bool {
        self.fillerWords.contains(self.trimmedNewWord)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Words to remove")
                .font(AppFont.captionEmphasis)
                .foregroundStyle(self.theme.palette.secondaryText)

            if self.fillerWords.isEmpty {
                Text("No words yet. Add one below or restore the defaults.")
                    .font(AppFont.callout)
                    .foregroundStyle(self.theme.palette.secondaryText)
            } else {
                FlowLayout(spacing: Space.sm) {
                    ForEach(self.fillerWords, id: \.self) { word in
                        HStack(spacing: Space.xs) {
                            Text(word)
                                .font(AppFont.transcript)
                                .foregroundStyle(self.theme.palette.primaryText)
                            Button {
                                withMotion(Motion.state) { self.removeWord(word) }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(AppFont.iconSmall)
                                    .foregroundStyle(self.theme.palette.secondaryText)
                                    .frame(width: Space.lg, height: Space.lg)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Remove “\(word)”")
                            .accessibilityLabel("Remove \(word)")
                        }
                        .padding(.leading, Space.sm)
                        .padding(.trailing, Space.xs)
                        .padding(.vertical, Space.xxs)
                        .background(
                            Capsule().fill(self.theme.palette.surfaceSunken)
                        )
                        .overlay(Capsule().strokeBorder(self.theme.palette.hairline, lineWidth: 1))
                        .motionTransition()
                    }
                }
            }

            HStack(spacing: Space.sm) {
                TextField("Add a word", text: self.$newWord)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: SettingsKit.pickerWidth)
                    .onSubmit { self.addWord() }

                Button("Add") { self.addWord() }
                    .buttonStyle(.sayIt(.secondary, size: .small))
                    .disabled(self.trimmedNewWord.isEmpty || self.isDuplicate)

                Spacer()

                Button("Restore Defaults") {
                    withMotion(Motion.state) {
                        self.fillerWords = SettingsStore.defaultFillerWords
                    }
                    SettingsStore.shared.fillerWords = self.fillerWords
                }
                .buttonStyle(.sayIt(.quiet, size: .small))
                .disabled(self.fillerWords == SettingsStore.defaultFillerWords)
            }

            if self.isDuplicate && !self.trimmedNewWord.isEmpty {
                Text("“\(self.trimmedNewWord)” is already on the list.")
                    .font(AppFont.caption)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }
        }
    }

    private func addWord() {
        let word = self.trimmedNewWord
        guard !word.isEmpty, !self.fillerWords.contains(word) else { return }
        withMotion(Motion.state) {
            self.fillerWords.append(word)
        }
        SettingsStore.shared.fillerWords = self.fillerWords
        self.newWord = ""
    }

    private func removeWord(_ word: String) {
        self.fillerWords.removeAll { $0 == word }
        SettingsStore.shared.fillerWords = self.fillerWords
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    struct Cache {
        var sizes: [CGSize] = []
        var positions: [CGPoint] = []
        var containerSize: CGSize = .zero
        var lastWidth: CGFloat = 0
    }

    var spacing: CGFloat = Space.sm

    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: Array(repeating: .zero, count: subviews.count))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        self.arrangeSubviews(proposal: proposal, subviews: subviews, cache: &cache)
        return cache.containerSize
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        self.arrangeSubviews(proposal: proposal, subviews: subviews, cache: &cache)
        for (index, position) in cache.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        let proposedWidth = proposal.width ?? 0
        let maxWidth = proposedWidth > 0 ? proposedWidth : 260
        let needsLayout = cache.positions.count != subviews.count || cache.lastWidth != maxWidth

        if needsLayout {
            cache.positions = []
            cache.positions.reserveCapacity(subviews.count)
            cache.sizes = Array(repeating: .zero, count: subviews.count)
        }

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for index in subviews.indices {
            let size: CGSize
            if needsLayout {
                size = subviews[index].sizeThatFits(.unspecified)
                cache.sizes[index] = size
            } else {
                size = cache.sizes[index]
            }

            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + self.spacing
                rowHeight = 0
            }
            if needsLayout {
                cache.positions.append(CGPoint(x: x, y: y))
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + self.spacing
        }

        cache.containerSize = CGSize(width: maxWidth, height: y + rowHeight)
        cache.lastWidth = maxWidth
    }
}
