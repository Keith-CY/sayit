import AVFoundation
import SwiftUI

/// Home: setup checklist until SayIt works end to end, then status, test area and
/// recent dictations. Pure view — all data comes in through `HomeState`.
struct HomeView: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let state: HomeState
    let testArea: HomeTestAreaState
    @Binding var transcript: String
    var isTranscriptFocused: FocusState<Bool>.Binding
    let actions: HomeActions

    private enum Anchor: Hashable {
        case testArea
    }

    private let contentMaxWidth: CGFloat = 720
    private let transcriptHeight: CGFloat = 120
    private let optionalIconSize: CGFloat = 24
    private let eyebrowTracking: CGFloat = 1.2
    private let featureCardMinWidth: CGFloat = 300

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    self.hero

                    Group {
                        if self.state.setupComplete {
                            self.statusCard
                                .motionTransition()
                        } else {
                            self.checklistCard(proxy: proxy)
                                .motionTransition()
                        }
                    }

                    self.testAreaCard
                        .id(Anchor.testArea)

                    if self.state.setupComplete {
                        self.recentCard
                            .motionTransition()
                    }

                    self.moreWaysSection
                }
                .frame(maxWidth: self.contentMaxWidth, alignment: .leading)
                .padding(Space.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
                .motion(Motion.state, value: self.state.setupComplete)
            }
        }
        .background(self.theme.palette.contentBackground)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(self.state.setupComplete ? "Home" : "Welcome to SayIt")
                .font(AppFont.captionEmphasis)
                .tracking(self.eyebrowTracking)
                .textCase(.uppercase)
                .foregroundStyle(self.theme.palette.accentForeground)

            Text("Say it, and it’s written.")
                .font(AppFont.display)
                .foregroundStyle(self.theme.palette.primaryText)
                .accessibilityAddTraits(.isHeader)

            Group {
                if self.state.setupComplete {
                    HStack(spacing: Space.xs) {
                        Text("You’re all set. Press")
                        KeyCap(self.state.shortcut)
                        Text("in any app to dictate.")
                    }
                } else {
                    Text("Press your shortcut, speak, and SayIt types your words into the app you’re using.")
                }
            }
            .font(AppFont.body)
            .foregroundStyle(self.theme.palette.secondaryText)
            .id(self.state.setupComplete)
            .transition(self.reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4)))

            if !self.state.setupComplete {
                Label {
                    Text("SayIt lives in the menu bar. You can close this window — your shortcut keeps working.")
                } icon: {
                    Image(systemName: "menubar.rectangle")
                }
                .font(AppFont.caption)
                .foregroundStyle(self.theme.palette.tertiaryText)
                .padding(.top, Space.xxs)
            }
        }
    }

    // MARK: - Checklist

    private func checklistCard(proxy: ScrollViewProxy) -> some View {
        ThemedCard(style: .prominent) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Set Up SayIt")
                        .font(AppFont.sectionTitle)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("\(self.state.completedRequiredSteps) of \(HomeState.requiredStepCount) done")
                        .font(AppFont.caption)
                        .monospacedDigit()
                        .foregroundStyle(self.theme.palette.secondaryText)
                }
                .padding(.bottom, Space.xs)

                self.microphoneStep
                self.accessibilityStep
                self.speechModelStep
                self.firstDictationStep(proxy: proxy)

                Divider()
                    .padding(.vertical, Space.sm)

                self.aiEnhancementRow
            }
        }
    }

    /// The next step the user can act on. A blocked microphone is skipped so the
    /// remaining steps stay actionable.
    private var currentStep: Int? {
        if !self.state.micReady, self.state.micStatus != .restricted { return 1 }
        if !self.state.accessibilityDone { return 2 }
        if !self.state.modelReady { return 3 }
        if !self.state.firstDictationDone { return 4 }
        return nil
    }

    private func status(for step: Int, done: Bool) -> SetupStepStatus {
        if done { return .completed }
        return self.currentStep == step ? .current : .pending
    }

    private func stepButtonStyle(for step: Int) -> SayItButtonStyle {
        .sayIt(self.currentStep == step ? .primary : .secondary, size: .regular)
    }

    private var microphoneStep: some View {
        let micStatus = self.state.micStatus
        let title: String
        let description: String
        let status: SetupStepStatus

        switch micStatus {
        case .authorized:
            title = "Microphone access allowed"
            description = "SayIt listens only while your shortcut is active. Audio stays on this Mac."
            status = .completed
        case .denied:
            title = "Turn on microphone access"
            description = "Microphone access is off for SayIt. In System Settings, go to Privacy & Security → Microphone and turn on SayIt."
            status = self.status(for: 1, done: false)
        case .restricted:
            title = "Microphone access is blocked"
            description = "This Mac doesn’t let apps use the microphone, usually because of Screen Time or your organization’s device management. Ask whoever manages this Mac to allow SayIt."
            status = .blocked
        default:
            title = "Allow microphone access"
            description = "SayIt listens only while your shortcut is active. Audio stays on this Mac."
            status = self.status(for: 1, done: false)
        }

        return SetupStepRow(number: 1, title: title, description: description, status: status) {
            EmptyView()
        } action: {
            switch micStatus {
            case .notDetermined:
                Button("Allow Microphone", action: self.actions.requestMicrophone)
                    .buttonStyle(self.stepButtonStyle(for: 1))
            case .denied:
                Button("Open System Settings", action: self.actions.openMicrophoneSettings)
                    .buttonStyle(self.stepButtonStyle(for: 1))
            default:
                EmptyView()
            }
        }
    }

    private var accessibilityStep: some View {
        let title: String
        let description: String

        if self.state.accessibilityDone {
            title = "Accessibility access allowed"
            description = "SayIt can use your shortcut in any app and type where your cursor is."
        } else if self.state.accessibilityEnabled {
            title = "Restart to finish enabling Accessibility"
            description = "SayIt needs to restart once so your shortcut works in every app."
        } else {
            title = "Allow SayIt to type for you"
            description = "Accessibility access lets SayIt hear your shortcut in any app and type where your cursor is. In System Settings, turn on SayIt. If it’s already on after an update, turn it off and on again."
        }

        return SetupStepRow(
            number: 2,
            title: title,
            description: description,
            status: self.status(for: 2, done: self.state.accessibilityDone)
        ) {
            EmptyView()
        } action: {
            if self.state.accessibilityEnabled {
                Button("Restart Now", action: self.actions.restartApp)
                    .buttonStyle(self.stepButtonStyle(for: 2))
            } else {
                Button("Open System Settings", action: self.actions.openAccessibilitySettings)
                    .buttonStyle(self.stepButtonStyle(for: 2))
            }
        }
    }

    private var modelLine: String {
        if let size = self.state.model.sizeText {
            return "\(self.state.model.name) · \(size)"
        }
        return "\(self.state.model.name) · Built into macOS"
    }

    private var speechModelStep: some View {
        let model = self.state.model
        var title = model.isBuiltIn ? "Prepare the speech model" : "Download the speech model"
        var description = "\(self.modelLine). It runs on this Mac, so dictation works offline."
        var status = self.status(for: 3, done: self.state.modelReady)

        switch self.state.modelState {
        case .ready, .onDisk:
            title = "Speech model ready"
            description = "\(model.name) runs on this Mac — no internet needed to dictate."
        case .loading:
            title = "Loading the speech model…"
            description = "\(model.name) is loading into memory. The first time can take up to a minute."
            status = .working
        case .downloading:
            title = "Downloading the speech model…"
            description = "\(self.modelLine). You can keep setting up while this finishes."
            status = .working
        case let .failed(message):
            title = "The download didn’t finish"
            description = message
        case .cancelled:
            title = "Download cancelled"
            description = "\(self.modelLine). Download it whenever you’re ready."
        case .missing:
            break
        }

        return SetupStepRow(number: 3, title: title, description: description, status: status) {
            switch self.state.modelState {
            case let .downloading(fraction, _):
                InlineProgress(
                    fraction: fraction,
                    caption: fraction.map { "\(Int(($0 * 100).rounded()))% downloaded" } ?? "Downloading…"
                )
            case .missing, .failed, .cancelled:
                Button("Choose a Different Model…", action: self.actions.openVoiceEngine)
                    .buttonStyle(.sayIt(.quiet, size: .small))
                    // Quiet buttons carry a small inset; pull it back so the text aligns.
                    .padding(.leading, -Space.xs)
                    .padding(.top, Space.xxs)
            default:
                EmptyView()
            }
        } action: {
            switch self.state.modelState {
            case let .downloading(_, cancellable):
                if cancellable {
                    Button("Cancel", action: self.actions.cancelDownload)
                        .buttonStyle(.sayIt(.secondary, size: .regular))
                }
            case .missing, .cancelled:
                Button(model.isBuiltIn ? "Prepare" : "Download", action: self.actions.downloadModel)
                    .buttonStyle(self.stepButtonStyle(for: 3))
            case .failed:
                Button("Try Again", action: self.actions.downloadModel)
                    .buttonStyle(self.stepButtonStyle(for: 3))
            default:
                EmptyView()
            }
        }
    }

    private func firstDictationStep(proxy: ScrollViewProxy) -> some View {
        SetupStepRow(
            number: 4,
            title: self.state.firstDictationDone ? "First dictation complete" : "Try your first dictation",
            description: self.state.firstDictationDone
                ? "SayIt turned your speech into text. You’re ready to dictate anywhere."
                : "Press \(self.state.shortcut) in any app and speak, or use the test area below.",
            status: self.status(for: 4, done: self.state.firstDictationDone)
        ) {
            EmptyView()
        } action: {
            Button("Go to Test Area") {
                withMotion(Motion.state) {
                    proxy.scrollTo(Anchor.testArea, anchor: .top)
                }
                self.isTranscriptFocused.wrappedValue = true
            }
            .buttonStyle(self.stepButtonStyle(for: 4))
        }
    }

    private var aiEnhancementRow: some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: "sparkles")
                .font(AppFont.iconSmall)
                .foregroundStyle(self.theme.palette.accentForeground)
                .frame(width: self.optionalIconSize, height: self.optionalIconSize)
                .background(Circle().fill(self.theme.palette.accentSubtle))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.sm) {
                    Text(self.state.aiEnhancementConfigured ? "AI Enhancement" : "Clean up text with AI")
                        .font(AppFont.rowTitle)
                    Text("Optional")
                        .font(AppFont.micro)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .padding(.horizontal, Space.xs + Space.xxs)
                        .padding(.vertical, Space.xxs)
                        .overlay(Capsule().strokeBorder(self.theme.palette.hairline))
                }
                Text(self.aiEnhancementDescription)
                    .font(AppFont.callout)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button(self.state.aiEnhancementConfigured ? "Settings" : "Set Up", action: self.actions.openAIEnhancement)
                .buttonStyle(.sayIt(.quiet, size: .regular))
        }
        .padding(.vertical, Space.xs)
    }

    private var aiEnhancementDescription: String {
        if !self.state.aiEnhancementConfigured {
            return "Fix punctuation, casing and filler words with a model you choose. Without it, SayIt types exactly what it hears."
        }
        return self.state.aiEnhancementEnabled
            ? "On — SayIt cleans up punctuation and filler words before typing."
            : "Off — SayIt types exactly what it hears."
    }

    // MARK: - Status (after setup)

    private var statusCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("Status")
                    .font(AppFont.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, Space.xs)

                self.staggered(0) {
                    StatusRow(
                        systemImage: "waveform",
                        title: "Speech Model",
                        value: self.state.modelState == .ready ? self.state.model.name : "\(self.state.model.name) · loads on first use",
                        tone: .good
                    ) {
                        Button("Change", action: self.actions.openVoiceEngine)
                            .buttonStyle(.sayIt(.quiet, size: .small))
                    }
                }
                Divider()
                self.staggered(1) {
                    StatusRow(systemImage: "keyboard", title: "Shortcut", value: "") {
                        KeyCap(self.state.shortcut)
                        Button("Change", action: self.actions.openGeneral)
                            .buttonStyle(.sayIt(.quiet, size: .small))
                    }
                }
                Divider()
                self.staggered(2) {
                    StatusRow(systemImage: "mic", title: "Microphone", value: "Allowed", tone: .good)
                }
                Divider()
                self.staggered(3) {
                    StatusRow(systemImage: "accessibility", title: "Accessibility", value: "Allowed", tone: .good)
                }
                Divider()
                self.staggered(4) {
                    StatusRow(
                        systemImage: "sparkles",
                        title: "AI Enhancement",
                        value: self.state.aiEnhancementConfigured
                            ? (self.state.aiEnhancementEnabled ? "On" : "Off")
                            : "Not set up"
                    ) {
                        Button(self.state.aiEnhancementConfigured ? "Settings" : "Set Up", action: self.actions.openAIEnhancement)
                            .buttonStyle(.sayIt(.quiet, size: .small))
                    }
                }
            }
        }
    }

    /// Staggered entrance for rows that appear together (the setup-complete beat).
    private func staggered<Content: View>(_ index: Int, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .transition(
                self.reduceMotion
                    ? .opacity
                    : .opacity.combined(with: .offset(y: 6))
                    .animation(Motion.enter.delay(Double(index) * Motion.stagger))
            )
    }

    // MARK: - Test Area

    private var testAreaCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text("Test Area")
                            .font(AppFont.sectionTitle)
                            .accessibilityAddTraits(.isHeader)
                        Text("Try SayIt here without switching apps.")
                            .font(AppFont.callout)
                            .foregroundStyle(self.theme.palette.secondaryText)
                    }
                    Spacer()
                    if self.testArea.isRunning {
                        Label("Recording", systemImage: "circle.fill")
                            .labelStyle(RecordingLabelStyle(color: self.theme.palette.recording))
                            .font(AppFont.captionEmphasis)
                            .foregroundStyle(self.theme.palette.primaryText)
                            .motionTransition()
                    }
                }

                Button(action: self.actions.recordingControl) {
                    HStack(spacing: Space.sm) {
                        if self.testArea.action == .starting || self.testArea.action == .waitForModel {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: self.recordingIcon)
                        }
                        Text(self.recordingTitle)
                    }
                }
                .buttonStyle(.sayIt(
                    self.state.requirementsMet || self.testArea.isRunning ? .primary : .secondary,
                    size: .large,
                    fullWidth: true,
                    isRecording: self.testArea.isRunning
                ))
                .disabled(self.recordingDisabled)

                self.transcriptWell

                if let wordBoost = self.testArea.wordBoostText {
                    Label(wordBoost, systemImage: "text.magnifyingglass")
                        .font(AppFont.caption)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .lineLimit(1)
                }

                if !self.testArea.isRunning, !self.transcriptIsEmpty {
                    HStack(spacing: Space.sm) {
                        Text(CopyFormat.count(self.wordCount, "word"))
                            .font(AppFont.caption)
                            .monospacedDigit()
                            .foregroundStyle(self.theme.palette.secondaryText)
                        Spacer()
                        Button(action: self.actions.copyTranscript) {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.sayIt(.secondary, size: .small))
                        Button("Clear", action: self.actions.clearTranscript)
                            .buttonStyle(.sayIt(.quiet, size: .small))
                    }
                    .motionTransition()
                }
            }
        }
        .motion(Motion.state, value: self.testArea.isRunning)
    }

    private var transcriptIsEmpty: Bool {
        self.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var wordCount: Int {
        self.transcript.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private var transcriptWell: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        return TextEditor(text: self.$transcript)
            .font(AppFont.transcript)
            .focused(self.isTranscriptFocused)
            .scrollContentBackground(.hidden)
            .frame(height: self.transcriptHeight)
            .padding(Space.sm)
            .background(shape.fill(self.theme.palette.surfaceSunken))
            .overlay(
                shape.strokeBorder(
                    self.testArea.isRunning ? self.theme.palette.recording.opacity(0.6) : self.theme.palette.hairline,
                    lineWidth: 1
                )
            )
            .overlay(alignment: .topLeading) {
                if self.transcriptIsEmpty {
                    self.transcriptPlaceholder
                        .padding(Space.md)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Transcript")
    }

    @ViewBuilder
    private var transcriptPlaceholder: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if self.testArea.isDictatingElsewhere {
                Text("Dictating into another app…")
                    .font(AppFont.transcript)
                    .foregroundStyle(self.theme.palette.secondaryText)
                Text("Your words go where your cursor is. They also appear here when you stop.")
                    .font(AppFont.caption)
                    .foregroundStyle(self.theme.palette.tertiaryText)
            } else if self.testArea.isRunning {
                Text("Listening… speak now.")
                    .font(AppFont.transcript)
                    .foregroundStyle(self.theme.palette.secondaryText)
                Text("Your words appear when you stop recording.")
                    .font(AppFont.caption)
                    .foregroundStyle(self.theme.palette.tertiaryText)
            } else if self.testArea.action == .waitForModel {
                Text("Preparing the speech model…")
                    .font(AppFont.transcript)
                    .foregroundStyle(self.theme.palette.secondaryText)
                Text("Recording becomes available when it’s ready.")
                    .font(AppFont.caption)
                    .foregroundStyle(self.theme.palette.tertiaryText)
            } else {
                Text("Your words will appear here.")
                    .font(AppFont.transcript)
                    .foregroundStyle(self.theme.palette.tertiaryText)
                if self.testArea.action == .start || self.testArea.action == .prepareAndStart {
                    HStack(spacing: Space.xs) {
                        Text("Click Start Recording or press")
                        KeyCap(self.state.shortcut)
                    }
                    .font(AppFont.caption)
                    .foregroundStyle(self.theme.palette.tertiaryText)
                }
            }
        }
    }

    private var recordingDisabled: Bool {
        switch self.testArea.action {
        case .waitForModel, .starting, .showMicrophoneRestriction:
            return true
        default:
            return false
        }
    }

    private var recordingTitle: String {
        switch self.testArea.action {
        case .start, .prepareAndStart: return "Start Recording"
        case .starting: return "Starting Microphone…"
        case .stop: return "Stop Recording"
        case .waitForModel: return "Preparing Speech Model…"
        case .requestMicrophoneAccess: return "Allow Microphone"
        case .openMicrophoneSettings: return "Open Microphone Settings"
        case .showMicrophoneRestriction: return "Microphone Blocked"
        }
    }

    private var recordingIcon: String {
        switch self.testArea.action {
        case .stop: return "stop.fill"
        case .openMicrophoneSettings: return "gearshape"
        case .showMicrophoneRestriction: return "mic.slash"
        default: return "mic"
        }
    }

    // MARK: - Recent

    private var recentCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Recent Dictations")
                        .font(AppFont.sectionTitle)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if !self.state.recent.isEmpty {
                        Button("Show All", action: self.actions.openHistory)
                            .buttonStyle(.sayIt(.quiet, size: .small))
                    }
                }

                if self.state.recent.isEmpty {
                    Text(
                        self.state.historyEnabled
                            ? "Dictations you make with your shortcut will appear here."
                            : "History is off. Turn on “Save transcription history” in General to see recent dictations here."
                    )
                    .font(AppFont.callout)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .padding(.vertical, Space.xs)
                } else {
                    ForEach(Array(self.state.recent.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider() }
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text(entry.text)
                                .font(AppFont.transcript)
                                .foregroundStyle(self.theme.palette.primaryText)
                                .lineLimit(2)
                            Text("\(entry.appName) · \(entry.date.formatted(.relative(presentation: .named)))")
                                .font(AppFont.caption)
                                .foregroundStyle(self.theme.palette.tertiaryText)
                        }
                        .padding(.vertical, Space.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    // MARK: - More Ways

    private var moreWaysSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("More Ways to Use Your Voice")
                .font(AppFont.sectionTitle)
                .accessibilityAddTraits(.isHeader)

            // Side by side when each card can be at least `featureCardMinWidth` wide.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Space.lg) {
                    self.commandModeCard
                        .frame(minWidth: self.featureCardMinWidth, idealWidth: self.featureCardMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    self.editModeCard
                        .frame(minWidth: self.featureCardMinWidth, idealWidth: self.featureCardMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: Space.lg) {
                    self.commandModeCard
                    self.editModeCard
                }
            }
        }
    }

    private var commandModeCard: some View {
        self.featureCard(
            systemImage: "terminal",
            title: "Command Mode",
            badge: "Alpha",
            description: "Ask SayIt to do things on your Mac — open apps, find files, check settings. Review what it runs; AI can make mistakes.",
            shortcut: self.state.commandShortcut
        ) {
            Button("Open Command Mode", action: self.actions.openCommandMode)
                .buttonStyle(.sayIt(.quiet, size: .small))
        }
    }

    private var editModeCard: some View {
        self.featureCard(
            systemImage: "pencil.line",
            title: "Edit Mode",
            badge: nil,
            description: "Select text and say how to change it — “make this more formal”, “fix the grammar”. With nothing selected, say what to write.",
            shortcut: self.state.editShortcut
        ) {
            EmptyView()
        }
    }

    private func featureCard<Action: View>(
        systemImage: String,
        title: String,
        badge: String?,
        description: String,
        shortcut: String?,
        @ViewBuilder action: () -> Action
    ) -> some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(spacing: Space.sm) {
                    Image(systemName: systemImage)
                        .font(AppFont.icon)
                        .foregroundStyle(self.theme.palette.secondaryText)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(AppFont.rowTitle)
                    if let badge {
                        Text(badge)
                            .font(AppFont.micro)
                            .foregroundStyle(self.theme.palette.secondaryText)
                            .padding(.horizontal, Space.xs + Space.xxs)
                            .padding(.vertical, Space.xxs)
                            .overlay(Capsule().strokeBorder(self.theme.palette.hairline))
                    }
                }
                Text(description)
                    .font(AppFont.callout)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.xs) {
                    if let shortcut {
                        Text("Press")
                        KeyCap(shortcut)
                    } else {
                        Text("Turn on its shortcut in General.")
                    }
                    Spacer(minLength: Space.sm)
                    action()
                }
                .font(AppFont.caption)
                .foregroundStyle(self.theme.palette.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Small colored dot + label, used for the “Recording” indicator.
private struct RecordingLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.xs) {
            configuration.icon
                .font(AppFont.micro)
                .foregroundStyle(self.color)
                .ambientPulse(isActive: true)
            configuration.title
        }
    }
}
