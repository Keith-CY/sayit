//
//  LiveCaptionPanel.swift
//  SayIt
//
//  Floating panel that shows Live Captions for the audio the Mac is playing.
//

import AppKit
import SwiftUI
import Translation

// MARK: - Window controller

@MainActor
final class LiveCaptionPanelController {
    static let shared = LiveCaptionPanelController()

    /// v2: the panel is now exactly the card (earlier frames included room for a shadow).
    private static let frameAutosaveName = "LiveCaptionsPanel.v2"
    private var panel: NSPanel?
    /// Guards fade-out completions against a show that started in the meantime.
    private var visibilityGeneration: UInt64 = 0
    private var resizeObserver: NSObjectProtocol?

    private init() {}

    /// - Parameter translating: Starts wide enough for the translation column.
    @available(macOS 26.0, *)
    func show(translating: Bool) {
        self.visibilityGeneration &+= 1
        let panel = self.panel ?? self.makePanel()
        self.panel = panel

        if !panel.setFrameUsingName(Self.frameAutosaveName) {
            panel.setFrame(self.defaultFrame(), display: false)
        }
        var frame = panel.frame
        if translating, let wide = Self.widened(frame, on: panel.screen ?? NSScreen.main) {
            frame = wide
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

    /// Makes room for the translation column: widens the panel around its center, staying
    /// on screen. A panel already that wide is left alone.
    func widenForTranslation() {
        guard let panel = self.panel, panel.isVisible,
              let frame = Self.widened(panel.frame, on: panel.screen ?? NSScreen.main)
        else { return }
        if Motion.prefersReducedMotion {
            panel.setFrame(frame, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.standard
                context.timingFunction = OverlayWindowMotion.enter
                panel.animator().setFrame(frame, display: true)
            }
        }
    }

    @available(macOS 26.0, *)
    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: LiveCaptionLayout.defaultSize),
            // Resizable from its edges: people make it taller to read back, wider to translate.
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The window server draws the shadow from the card's rounded shape.
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.contentMinSize = LiveCaptionLayout.minimumSize
        panel.setFrameAutosaveName(Self.frameAutosaveName)

        let hostingView = NSHostingView(rootView: LiveCaptionPanelView())
        // The window sets the size (people resize it); the content fills it.
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = hostingView
        self.resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { panel.invalidateShadow() }
        }
        return panel
    }

    /// `frame` widened to the translating width around its center and kept on screen, or
    /// nil when it's already that wide.
    private static func widened(_ frame: NSRect, on screen: NSScreen?) -> NSRect? {
        guard frame.width < LiveCaptionLayout.translatingWidth, let visible = screen?.visibleFrame else { return nil }
        let width = min(LiveCaptionLayout.translatingWidth, visible.width - 2 * Space.xl)
        guard width > frame.width else { return nil }
        var widened = frame
        widened.origin.x = min(max(frame.midX - width / 2, visible.minX + Space.xl), visible.maxX - Space.xl - width)
        widened.size.width = width
        return widened
    }

    /// Centered, above where the bottom recording overlay appears.
    private func defaultFrame() -> NSRect {
        let size = LiveCaptionLayout.defaultSize
        guard let screen = NSScreen.main else { return NSRect(origin: .zero, size: size) }
        let visible = screen.visibleFrame
        let y = visible.minY + CGFloat(SettingsStore.shared.overlayBottomOffset) + LiveCaptionLayout.clearanceAboveOverlay
        return NSRect(
            x: visible.midX - size.width / 2,
            y: min(y, visible.maxY - size.height),
            width: size.width,
            height: size.height
        )
    }
}

// MARK: - Layout

enum LiveCaptionLayout {
    /// About four caption lines below the header.
    static let defaultSize = CGSize(width: 620, height: 180)
    /// Room for the compact header and one caption line.
    static let minimumSize = CGSize(width: 420, height: 112)
    /// Wide enough for two readable columns when translating.
    static let translatingWidth: CGFloat = 980
    /// Keeps the panel clear of the bottom recording overlay at its largest size.
    static let clearanceAboveOverlay: CGFloat = 200
    /// Height of the fade at the top edge of the caption area.
    static let topFade: CGFloat = Space.lg
    /// How close to the end counts as reading the latest line.
    static let followTolerance: CGFloat = Space.xl
}

// MARK: - Views

/// Root of the panel. Always dark, like the recording overlay: it sits over video and
/// arbitrary content.
@available(macOS 26.0, *)
struct LiveCaptionPanelView: View {
    @ObservedObject private var service = LiveCaptionService.shared
    /// Set to ask macOS to download translation languages; macOS shows its own sheet.
    @State private var download: TranslationSession.Configuration?

    var body: some View {
        LiveCaptionContent(
            state: self.service.viewState,
            actions: LiveCaptionActions(
                selectLanguage: { self.service.setLanguage($0) },
                selectTranslation: { self.service.setTranslationTarget($0) },
                downloadTranslation: { self.requestDownload() },
                toggleSpeakers: { self.service.setSpeakerLabelsEnabled(self.service.viewState.speakers == .off) },
                toggleMicrophone: { self.service.setMicrophoneEnabled(self.service.viewState.microphone == .off) },
                showTranscripts: { self.service.showTranscripts() },
                close: { self.service.stop() }
            )
        )
        .sayItOverlayTheme()
        .translationTask(self.download) { session in
            do {
                try await session.prepareTranslation()
            } catch {
                DebugLogger.shared.info("Live Captions: translation download ended: \(error.localizedDescription)", source: "LiveCaptions")
            }
            self.download = nil
            self.service.translationDownloadEnded()
        }
    }

    private func requestDownload() {
        let state = self.service.viewState
        guard let target = state.translation?.target else { return }
        self.download = TranslationSession.Configuration(
            source: state.language.translationLanguage,
            target: target.translationLanguage
        )
    }
}

/// What the panel's controls do; empty in snapshot fixtures.
struct LiveCaptionActions {
    var selectLanguage: (LiveCaptionLanguage) -> Void = { _ in }
    var selectTranslation: (LiveCaptionLanguage?) -> Void = { _ in }
    var downloadTranslation: () -> Void = {}
    var toggleSpeakers: () -> Void = {}
    var toggleMicrophone: () -> Void = {}
    var showTranscripts: () -> Void = {}
    var close: () -> Void = {}
}

@available(macOS 26.0, *)
struct LiveCaptionContent: View {
    @Environment(\.theme) private var theme
    let state: LiveCaptionViewState
    var actions = LiveCaptionActions()

    private static let screenRecordingSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )
    private static let filesSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
    )

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
        VStack(alignment: .leading, spacing: Space.md) {
            self.header
            self.content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .padding(.horizontal, Space.lg)
        .padding(.top, Space.md)
        .padding(.bottom, Space.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(shape.fill(self.theme.overlay.surface))
        .overlay(shape.strokeBorder(self.theme.overlay.hairline, lineWidth: 1))
        .clipShape(shape)
        .modifier(WindowDragModifier())
    }

    // MARK: - Header

    /// Full labels when they fit; icons only (with the language name) when the panel is narrow.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            self.headerRow(compact: false)
            self.headerRow(compact: true)
        }
        .font(AppFont.Overlay.label)
        .foregroundStyle(self.theme.overlay.tertiaryText)
    }

    private func headerRow(compact: Bool) -> some View {
        HStack(spacing: Space.sm) {
            Label("Live Captions", systemImage: "captions.bubble")
                .labelStyle(CaptionLabelStyle(showsTitle: !compact))
            Spacer(minLength: Space.sm)
            if self.state.phase == .listening {
                LanguageMenu(
                    language: self.state.language,
                    isChanging: self.state.isChangingLanguage,
                    onSelect: self.actions.selectLanguage
                )
                TranslationMenu(
                    translation: self.state.translation,
                    language: self.state.language,
                    compact: compact,
                    onSelect: self.actions.selectTranslation
                )
                SpeakerToggle(state: self.state.speakers, compact: compact, action: self.actions.toggleSpeakers)
                MicrophoneToggle(state: self.state.microphone, compact: compact, action: self.actions.toggleMicrophone)
            }
            IconButton("Show Transcripts in Finder", systemName: "folder", size: 22, action: self.actions.showTranscripts)
            IconButton("Turn Off Live Captions", systemName: "xmark", size: 22, action: self.actions.close)
        }
        .fixedSize(horizontal: true, vertical: false)
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
            VStack(alignment: .leading, spacing: Space.sm) {
                self.notices
                if !self.state.rows.isEmpty {
                    CaptionScroll(state: self.state)
                } else if self.state.showsSilenceHint {
                    self.message(
                        "Nothing has played yet",
                        detail: "If something is playing, allow SayIt in Screen & System Audio Recording.",
                        settingsURL: Self.screenRecordingSettingsURL
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
    }

    /// One-line problems that need the person: translation languages to download, a pair
    /// macOS can't translate, a transcript that couldn't be saved.
    @ViewBuilder
    private var notices: some View {
        if let translation = self.state.translation {
            switch translation.status {
            case .needsDownload:
                self.notice(
                    "Translating \(self.state.language.name) into \(translation.target.name) needs a one-time download.",
                    icon: "arrow.down.circle",
                    button: ("Download…", self.actions.downloadTranslation)
                )
            case .unsupported:
                self.notice(
                    "macOS can’t translate \(self.state.language.name) into \(translation.target.name). Choose another language.",
                    icon: "exclamationmark.triangle",
                    isWarning: true
                )
            case .preparing, .ready:
                EmptyView()
            }
        }
        if self.state.transcriptSaveFailed {
            self.notice(
                "Couldn’t save the transcript. Allow SayIt to use the Documents folder in Privacy & Security → Files & Folders.",
                icon: "exclamationmark.triangle",
                isWarning: true,
                button: ("Open Privacy Settings", { Self.filesSettingsURL.map { _ = NSWorkspace.shared.open($0) } })
            )
        }
    }

    private func notice(
        _ text: String,
        icon: String,
        isWarning: Bool = false,
        button: (title: String, action: () -> Void)? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Image(systemName: icon)
                .foregroundStyle(isWarning ? self.theme.overlay.warning : self.theme.overlay.secondaryText)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(self.theme.overlay.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.sm)
            if let button {
                Button(button.title, action: button.action)
                    .buttonStyle(SayItButtonStyle(role: .secondary, size: .small))
            }
        }
        .font(AppFont.LiveCaption.detail)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Messages

    @ViewBuilder
    private func failure(_ failure: LiveCaptionFailure) -> some View {
        switch failure {
        case .cantHearMac:
            self.message(
                "SayIt can’t hear your Mac’s audio",
                detail: "Allow SayIt in Privacy & Security → Screen & System Audio Recording, then turn Live Captions on again.",
                settingsURL: Self.screenRecordingSettingsURL,
                isError: true
            )
        case .speechUnavailable:
            self.message(
                "Live Captions can’t start",
                detail: "The speech model for \(self.state.language.name) isn’t available. Check your internet connection, then turn Live Captions on again.",
                isError: true
            )
        }
    }

    private func message(
        _ title: String,
        detail: String?,
        pulsing: Bool = false,
        settingsURL: URL? = nil,
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
                if let settingsURL {
                    Button("Open Privacy Settings") { NSWorkspace.shared.open(settingsURL) }
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

// MARK: - Captions

/// Every caption line kept, newest at the bottom. Follows new lines while the person is
/// at the end; scrolling up to read back stops following until they return to the end
/// or choose Jump to Latest.
@available(macOS 26.0, *)
private struct CaptionScroll: View {
    @Environment(\.theme) private var theme
    let state: LiveCaptionViewState

    @State private var position = ScrollPosition(edge: .bottom)
    @State private var isAtEnd = true
    @State private var isFollowing = true
    @State private var phase: ScrollPhase = .idle

    var body: some View {
        let rows = self.state.rows
        // Mark where each line came from once the microphone is in the mix.
        let showsSources = self.state.microphone == .on || rows.contains { $0.source == .microphone }
        let speakerLabels = LiveCaptionViewState.turnLabels(for: rows)
        let translating = self.state.translation?.status == .ready

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    CaptionRow(
                        row: row,
                        speakerLabel: speakerLabels[row.id],
                        showsSource: showsSources,
                        translating: translating
                    )
                }
            }
            .font(AppFont.LiveCaption.text)
            .lineSpacing(Space.xxs)
        }
        .scrollIndicators(.automatic)
        .scrollPosition(self.$position)
        .defaultScrollAnchor(.bottom)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.containerSize.height
                >= geometry.contentSize.height - LiveCaptionLayout.followTolerance
        } action: { _, isAtEnd in
            self.isAtEnd = isAtEnd
        }
        .onScrollPhaseChange { _, phase in
            self.phase = phase
            // Only the person's scrolling decides; new lines growing the content don't.
            if phase == .idle { self.isFollowing = self.isAtEnd }
        }
        .onChange(of: rows) {
            if self.isFollowing, self.phase == .idle { self.position.scrollTo(edge: .bottom) }
        }
        .mask(alignment: .top) {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: LiveCaptionLayout.topFade)
                Rectangle()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !self.isFollowing {
                Button {
                    self.isFollowing = true
                    withMotion(Motion.enter) {
                        self.position.scrollTo(edge: .bottom)
                    }
                } label: {
                    Label("Jump to Latest", systemImage: "arrow.down")
                        .labelStyle(CaptionLabelStyle(showsTitle: true))
                }
                .buttonStyle(LiveCaptionChipStyle(isOn: true, isWarning: false))
                .transition(.opacity)
            }
        }
        .motion(Motion.fade, value: self.isFollowing)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live Captions")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// One caption line: who said it, the words, and (when translating) the translation in
/// a second column, so original and translation read side by side.
@available(macOS 26.0, *)
private struct CaptionRow: View {
    @Environment(\.theme) private var theme
    let row: LiveCaptionViewState.Row
    let speakerLabel: String?
    let showsSource: Bool
    let translating: Bool

    /// Space between lines, so a wrapped line reads as one.
    private static let rowGap = Space.sm

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                if self.showsSource {
                    Image(systemName: LiveCaptionContent.glyph(for: self.row.source))
                        .font(AppFont.LiveCaption.sourceIcon)
                        .foregroundStyle(self.ink.forming)
                        .frame(width: Space.lg)
                        .accessibilityLabel(self.row.source == .microphone ? "You" : "Mac Audio")
                }
                self.original
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Self.rowGap / 2)

            if self.translating {
                Rectangle()
                    .fill(self.theme.overlay.hairline)
                    .frame(width: 1)
                    .padding(.horizontal, Space.md)
                    .accessibilityHidden(true)
                self.translation
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Self.rowGap / 2)
            }
        }
        // Lets the column divider run the full height of the taller column.
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    /// Settled words in full ink; words that may still change (Apple's draft, awaiting
    /// Qwen) one step quieter; the forming tail quieter still. Your words (microphone)
    /// are in their own color. A turn starts with the speaker's name.
    private var original: some View {
        let ink = self.ink
        let label = self.speakerLabel.map {
            Text("\($0)\u{2003}").font(AppFont.LiveCaption.speaker).foregroundStyle(self.theme.overlay.tertiaryText)
        } ?? Text("")
        return (label
            + Text(self.row.text).foregroundStyle(self.row.isDraft ? ink.draft : ink.settled)
            + Text(self.row.formingTail).foregroundStyle(ink.forming))
            .contentTransition(.opacity)
            .motion(Motion.state, value: self.row.text)
            .motion(Motion.state, value: self.row.isDraft)
    }

    /// Lines are translated once settled; until then the column stays empty, with an
    /// ellipsis while a settled line is being translated.
    @ViewBuilder
    private var translation: some View {
        if let translation = self.row.translation {
            Text(translation)
                .foregroundStyle(self.ink.settled)
                .transition(.opacity)
        } else if !self.row.isDraft {
            Text("…")
                .foregroundStyle(self.ink.forming)
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(height: 0)
        }
    }

    private var ink: (settled: Color, draft: Color, forming: Color) {
        let overlay = self.theme.overlay
        switch self.row.source {
        case .macAudio: return (overlay.primaryText, overlay.secondaryText, overlay.tertiaryText)
        case .microphone: return (overlay.you, overlay.youDraft, overlay.youForming)
        }
    }
}

// MARK: - Controls

/// The language being spoken. Changing it restarts Apple's recognizer in that language
/// (downloading its model the first time); lines already shown stay.
@available(macOS 26.0, *)
private struct LanguageMenu: View {
    let language: LiveCaptionLanguage
    let isChanging: Bool
    let onSelect: (LiveCaptionLanguage) -> Void

    var body: some View {
        Menu {
            Section("Language Being Spoken") {
                ForEach(LiveCaptionLanguage.captionable) { option in
                    Toggle(option.name, isOn: Binding(get: { option == self.language }, set: { if $0 { self.onSelect(option) } }))
                }
            }
        } label: {
            Label {
                Text(self.language.name)
            } icon: {
                Image(systemName: "globe")
                    .ambientPulse(isActive: self.isChanging)
            }
            .labelStyle(CaptionLabelStyle(showsTitle: true))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(LiveCaptionChipStyle(isOn: false, isWarning: false))
        .fixedSize()
        .disabled(self.isChanging)
        .help(self.isChanging ? "Getting \(self.language.name) ready…" : "Language being spoken")
        .accessibilityLabel("Language Being Spoken")
        .accessibilityValue(self.language.name)
    }
}

/// Translation on macOS (on this Mac): off, or the language to translate into.
@available(macOS 26.0, *)
private struct TranslationMenu: View {
    let translation: LiveCaptionViewState.Translation?
    let language: LiveCaptionLanguage
    let compact: Bool
    let onSelect: (LiveCaptionLanguage?) -> Void

    var body: some View {
        Menu {
            Toggle("Off", isOn: Binding(get: { self.translation == nil }, set: { if $0 { self.onSelect(nil) } }))
            Section("Translate Into") {
                ForEach(LiveCaptionLanguage.allCases.filter { !$0.isSameLanguage(as: self.language) }) { option in
                    Toggle(
                        option.name,
                        isOn: Binding(get: { self.translation?.target == option }, set: { if $0 { self.onSelect(option) } })
                    )
                }
            }
        } label: {
            Label {
                Text(self.translation?.target.name ?? "Translate")
            } icon: {
                Image(systemName: self.translation?.status == .unsupported ? "exclamationmark.triangle" : "translate")
                    .ambientPulse(isActive: self.translation?.status == .preparing)
            }
            .labelStyle(CaptionLabelStyle(showsTitle: !self.compact))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(LiveCaptionChipStyle(isOn: self.translation != nil, isWarning: self.translation?.status == .unsupported))
        .fixedSize()
        .help(self.help)
        .accessibilityLabel("Translate")
        .accessibilityValue(self.translation?.target.name ?? "Off")
    }

    private var help: String {
        guard let translation = self.translation else { return "Translate captions on this Mac" }
        switch translation.status {
        case .preparing: return "Getting translation ready…"
        case .ready: return "Translating into \(translation.target.name) on this Mac"
        case .needsDownload: return "Translating into \(translation.target.name) needs a one-time download"
        case .unsupported: return "macOS can’t translate \(self.language.name) into \(translation.target.name)"
        }
    }
}

/// Turns speaker labels on and off. Off by default: the speaker model is a separate
/// download of about 250 MB.
private struct SpeakerToggle: View {
    let state: LiveCaptionViewState.Speakers
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Label {
                Text("Speakers")
            } icon: {
                Image(systemName: self.glyph)
                    .ambientPulse(isActive: self.state == .preparing)
            }
            .labelStyle(CaptionLabelStyle(showsTitle: !self.compact))
        }
        .buttonStyle(LiveCaptionChipStyle(isOn: self.state == .on || self.state == .preparing, isWarning: self.state == .unavailable))
        .help(self.help)
        .accessibilityLabel("Speakers")
        .accessibilityValue(self.state == .off ? "Off" : "On")
    }

    private var glyph: String {
        switch self.state {
        case .off: return "person.2.slash"
        case .preparing, .on: return "person.2"
        case .unavailable: return "exclamationmark.triangle"
        }
    }

    private var help: String {
        switch self.state {
        case .off: return "Label who is speaking. The first time, SayIt downloads a 250 MB speaker model."
        case .preparing: return "Getting speaker labels ready…"
        case .on: return "Stop labeling speakers"
        case .unavailable: return "The speaker model couldn’t be loaded. Check your internet connection, then turn it on again."
        }
    }
}

/// Turns the microphone source on and off. Off by default: an open microphone puts
/// AirPods in call mode, which lowers playback quality.
private struct MicrophoneToggle: View {
    let state: LiveCaptionViewState.Microphone
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Label("Microphone", systemImage: self.glyph)
                .labelStyle(CaptionLabelStyle(showsTitle: !self.compact))
        }
        .buttonStyle(LiveCaptionChipStyle(isOn: self.state == .on, isWarning: self.state == .unavailable))
        .help(self.help)
        .accessibilityLabel("Microphone")
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

/// Icon and title, or the icon alone when the panel is narrow.
private struct CaptionLabelStyle: LabelStyle {
    let showsTitle: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.xs) {
            configuration.icon
            if self.showsTitle {
                configuration.title
            }
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
