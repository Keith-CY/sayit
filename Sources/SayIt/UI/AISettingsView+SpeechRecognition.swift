//
//  AISettingsView+SpeechRecognition.swift
//  SayIt
//
//  Voice Engine page sections: engine in use, model list, language, clean-up.
//

import SwiftUI

extension VoiceEngineSettingsView {
    private enum Layout {
        static let heroLogoSize: CGFloat = 44
        static let rowLogoSize: CGFloat = 28
        static let actionColumnWidth: CGFloat = 168
        static let progressWidth: CGFloat = 96
        static let activeMarkerWidth: CGFloat = 3
    }

    // MARK: - In Use

    var inUseCard: some View {
        let model = self.settings.selectedSpeechModel
        let palette = self.theme.palette

        return ThemedCard(style: .prominent) {
            VStack(alignment: .leading, spacing: Space.lg) {
                HStack(alignment: .top, spacing: Space.lg) {
                    self.speechModelLogoView(for: model, size: Layout.heroLogoSize)

                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack(spacing: Space.sm) {
                            Text("In use")
                                .font(AppFont.captionEmphasis)
                                .foregroundStyle(palette.secondaryText)
                            self.engineStatusBadge(for: model)
                        }
                        Text(model.uiName)
                            .font(AppFont.pageTitle)
                            .foregroundStyle(palette.primaryText)
                            .contentTransition(.opacity)
                        Text(model.cardDescription)
                            .font(AppFont.callout)
                            .foregroundStyle(palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: Space.sm) {
                        SettingsKit.Rating(label: "Speed", value: model.speedRating)
                        SettingsKit.Rating(label: "Accuracy", value: model.accuracyRating)
                    }
                }

                self.chips(for: model)

                if !model.isInstalled, self.viewModel.downloadingModel != model {
                    SettingsKit.Notice(
                        .warning,
                        title: "\(model.uiName) isn’t downloaded yet",
                        message: "Download it (\(model.uiSizePhrase)) to start dictating, or choose another model below."
                    ) {
                        Button("Download") {
                            self.viewModel.downloadSpeechModel(model)
                        }
                        .buttonStyle(.sayIt(.primary, size: .small))
                        .disabled(self.viewModel.isBusy)
                    }
                }
            }
            .motion(Motion.state, value: model)
        }
    }

    @ViewBuilder
    private func engineStatusBadge(for model: SettingsStore.SpeechModel) -> some View {
        if self.viewModel.downloadingModel == model {
            SettingsKit.StatusBadge(
                text: "Downloading \(Int(self.viewModel.downloadProgress * 100))%",
                systemImage: "arrow.down.circle",
                tone: .info
            )
        } else if self.viewModel.isActiveModelLoading {
            SettingsKit.StatusBadge(text: "Loading…", systemImage: "hourglass", tone: .neutral)
        } else if !model.isInstalled {
            SettingsKit.StatusBadge(text: "Not downloaded", systemImage: "arrow.down.circle", tone: .warning)
        } else if self.viewModel.asr.isAsrReady {
            SettingsKit.StatusBadge(text: "Ready", systemImage: "checkmark.circle.fill", tone: .success)
        } else {
            SettingsKit.StatusBadge(text: "Loads on first use", systemImage: "circle.dashed", tone: .neutral)
        }
    }

    private func chips(for model: SettingsStore.SpeechModel) -> some View {
        FlowLayout(spacing: Space.xs) {
            SettingsKit.Chip(text: model.uiSize, systemImage: model.usesAppleLogo ? "checkmark.seal" : "internaldrive")
            SettingsKit.Chip(text: model.uiLanguages, systemImage: "globe")
            if model.uiTranscribesAfterRecording {
                SettingsKit.Chip(text: "Text appears after you stop", systemImage: "text.append")
            } else {
                SettingsKit.Chip(text: "Live text while you speak", systemImage: "text.bubble")
            }
            if model.requiresAppleSilicon {
                SettingsKit.Chip(text: "Apple silicon", systemImage: "cpu")
            }
        }
    }

    // MARK: - Models

    var modelsSection: some View {
        SettingsKit.Section(
            "Speech Models",
            footer: "Every model runs on this Mac. Downloads stay until you delete them.",
            accessory: {
                HStack(spacing: Space.md) {
                    Picker("Show", selection: self.$viewModel.providerFilter) {
                        ForEach(SpeechProviderFilter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()

                    Picker("Sort by", selection: self.$viewModel.modelSortOption) {
                        ForEach(ModelSortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                .font(AppFont.callout)
            }
        ) {
            if let issue = self.viewModel.issue {
                SettingsKit.Notice(.error, title: issue.title, message: issue.message) {
                    if issue.retry != nil {
                        Button("Try Again") { self.viewModel.retry(issue) }
                            .buttonStyle(.sayIt(.secondary, size: .small))
                            .disabled(self.viewModel.isBusy)
                    }
                    Button("Dismiss") { self.viewModel.dismissIssue() }
                        .buttonStyle(.sayIt(.quiet, size: .small))
                }
                .padding(Space.md)
                .motionTransition(edge: .top)
            }

            let models = self.viewModel.filteredSpeechModels
            if models.isEmpty {
                SettingsKit.EmptyState(
                    systemImage: "line.3.horizontal.decrease.circle",
                    title: "No models match this filter",
                    message: "Show all providers to see every available model."
                ) {
                    Button("Show All") { self.viewModel.providerFilter = .all }
                        .buttonStyle(.sayItSecondary)
                }
            } else {
                ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                    if index > 0 {
                        SettingsKit.RowDivider()
                    }
                    self.speechModelRow(for: model)
                }
            }
        }
        .motion(Motion.state, value: self.viewModel.issue)
    }

    func speechModelRow(for model: SettingsStore.SpeechModel) -> some View {
        let palette = self.theme.palette
        let isExpanded = self.viewModel.previewSpeechModel == model
        let isActive = self.viewModel.isActiveSpeechModel(model)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Space.md) {
                Button {
                    withMotion(Motion.state) {
                        self.viewModel.previewSpeechModel = model
                    }
                } label: {
                    HStack(alignment: .center, spacing: Space.md) {
                        Image(systemName: "chevron.right")
                            .font(AppFont.iconSmall)
                            .foregroundStyle(palette.tertiaryText)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .accessibilityHidden(true)

                        self.speechModelLogoView(for: model, size: Layout.rowLogoSize)

                        VStack(alignment: .leading, spacing: Space.xxs) {
                            HStack(spacing: Space.sm) {
                                Text(model.uiName)
                                    .font(AppFont.rowTitle)
                                    .foregroundStyle(palette.primaryText)
                                if isActive {
                                    SettingsKit.StatusBadge(text: "In Use", systemImage: "checkmark", tone: .accent)
                                }
                            }
                            Text(model.uiTagline)
                                .font(AppFont.callout)
                                .foregroundStyle(palette.secondaryText)
                        }
                        Spacer(minLength: Space.sm)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(model.uiName), \(model.uiTagline)")
                .accessibilityValue(self.statusDescription(for: model))
                .accessibilityHint(isExpanded ? "Details are shown below" : "Shows details")
                .accessibilityAddTraits(isExpanded ? .isSelected : [])

                self.modelAction(for: model, isActive: isActive)
                    .frame(width: Layout.actionColumnWidth, alignment: .trailing)
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)

            if isExpanded {
                self.modelDetails(for: model, isActive: isActive)
                    .padding(.leading, Space.lg + Space.md + Layout.rowLogoSize + Space.lg)
                    .padding(.trailing, Space.lg)
                    .padding(.bottom, Space.lg)
                    .motionTransition(edge: .top)
            }
        }
        .background(isExpanded ? palette.surfaceRaised : .clear)
        .overlay(alignment: .leading) {
            if isActive {
                Rectangle()
                    .fill(palette.accent)
                    .frame(width: Layout.activeMarkerWidth)
                    .accessibilityHidden(true)
            }
        }
        .opacity(self.viewModel.asr.isRunning ? 0.6 : 1)
        .disabled(self.viewModel.asr.isRunning)
        .motion(Motion.state, value: isExpanded)
    }

    @ViewBuilder
    private func modelAction(for model: SettingsStore.SpeechModel, isActive: Bool) -> some View {
        if self.viewModel.downloadingModel == model {
            VStack(alignment: .trailing, spacing: Space.xxs) {
                HStack(spacing: Space.xs) {
                    ProgressView(value: self.viewModel.downloadProgress)
                        .progressViewStyle(.linear)
                        .frame(width: Layout.progressWidth)
                        .accessibilityLabel("Download progress")
                    IconButton("Cancel Download", systemName: "xmark.circle") {
                        self.viewModel.cancelDownload()
                    }
                    .disabled(self.viewModel.isCancellingDownload)
                }
                Text(self.viewModel.isCancellingDownload
                    ? "Cancelling…"
                    : "\(Int(self.viewModel.downloadProgress * 100))% of \(model.downloadSize.replacingOccurrences(of: "~", with: ""))")
                    .font(AppFont.caption)
                    .monospacedDigit()
                    .foregroundStyle(self.theme.palette.secondaryText)
            }
        } else if isActive && self.viewModel.isActiveModelLoading {
            HStack(spacing: Space.sm) {
                ProgressView().controlSize(.small)
                Text("Loading…")
                    .font(AppFont.caption)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }
        } else if isActive {
            EmptyView()
        } else if model.isInstalled {
            Button("Use") {
                self.viewModel.activateSpeechModel(model)
            }
            .buttonStyle(.sayIt(.secondary, size: .small))
            .disabled(self.viewModel.isBusy)
            .accessibilityLabel("Use \(model.uiName)")
        } else {
            Button("Download") {
                self.viewModel.previewSpeechModel = model
                self.viewModel.downloadSpeechModel(model)
            }
            .buttonStyle(.sayIt(.secondary, size: .small))
            .disabled(self.viewModel.isBusy)
            .help("Download \(model.uiSizePhrase)")
            .accessibilityLabel("Download \(model.uiName), \(model.uiSizePhrase)")
        }
    }

    private func modelDetails(for model: SettingsStore.SpeechModel, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text(model.cardDescription)
                .font(AppFont.callout)
                .foregroundStyle(self.theme.palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.xl) {
                SettingsKit.Rating(label: "Speed", value: model.speedRating, compact: true)
                SettingsKit.Rating(label: "Accuracy", value: model.accuracyRating, compact: true)
            }

            self.chips(for: model)

            if let note = model.uiMemoryNote {
                Label(note, systemImage: "memorychip")
                    .font(AppFont.caption)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }

            if model == .parakeetTDT {
                HStack(spacing: Space.sm) {
                    Label("Learns your custom words", systemImage: "character.book.closed")
                        .font(AppFont.caption)
                        .foregroundStyle(self.theme.palette.secondaryText)
                    Button("Open Dictionary") {
                        NotificationCenter.default.post(name: .openCustomDictionaryFromVoiceEngine, object: nil)
                    }
                    .buttonStyle(.sayIt(.quiet, size: .small))
                }
            }

            if model.isInstalled, model.uiCanDelete, self.viewModel.downloadingModel != model {
                Button("Delete Download…") {
                    self.pendingDeletion = model
                }
                .buttonStyle(.sayIt(.destructive, size: .small))
                .disabled(self.viewModel.isBusy)
                .help(isActive ? "SayIt will need to download this model again before you can dictate." : "")
            }
        }
    }

    private func statusDescription(for model: SettingsStore.SpeechModel) -> String {
        if self.viewModel.downloadingModel == model {
            return "Downloading, \(Int(self.viewModel.downloadProgress * 100)) percent"
        }
        if self.viewModel.isActiveSpeechModel(model) {
            return "In use"
        }
        return model.isInstalled ? "Downloaded" : "Not downloaded, \(model.uiSizePhrase)"
    }

    // MARK: - Language

    var languageSection: some View {
        let currentMode = self.settings.speechLanguageMode

        return SettingsKit.Section("Language", footer: currentMode.uiExplanation) {
            SettingsKit.Row("Speech language", description: "The language you dictate in.", systemImage: "globe") {
                Picker("Speech language", selection: Binding(
                    get: { self.settings.speechLanguageMode },
                    set: { mode in
                        self.settings.speechLanguageMode = mode
                        self.viewModel.asr.resetTranscriptionProvider()
                    }
                )) {
                    ForEach(SettingsStore.SpeechLanguageMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: SettingsKit.pickerWidth)
            }
            SettingsKit.RowDivider()
            SettingsKit.ToggleRow(
                "Detect language automatically",
                description: currentMode.isAutomatic
                    ? "Tries several languages and keeps the best match."
                    : "Available when Speech language is set to Auto.",
                systemImage: "sparkle.magnifyingglass",
                isOn: Binding(
                    get: { self.settings.enableSmartLanguageDetection },
                    set: { newValue in
                        self.settings.enableSmartLanguageDetection = newValue
                        self.viewModel.asr.resetTranscriptionProvider()
                    }
                )
            )
            .disabled(!currentMode.isAutomatic)
        }
    }

    // MARK: - Clean-Up

    var cleanUpSection: some View {
        SettingsKit.Section("Clean-Up") {
            SettingsKit.ToggleRow(
                "Remove filler words",
                description: "Drops sounds like “um”, “uh” and “er” from your text.",
                systemImage: "scissors",
                isOn: self.$viewModel.removeFillerWordsEnabled
            )
            .onChange(of: self.viewModel.removeFillerWordsEnabled) { _, newValue in
                self.settings.removeFillerWordsEnabled = newValue
            }

            if self.viewModel.removeFillerWordsEnabled {
                SettingsKit.RowDivider()
                FillerWordsEditor()
                    .padding(Space.lg)
                    .motionTransition(edge: .top)
            }
        }
        .motion(Motion.state, value: self.viewModel.removeFillerWordsEnabled)
    }

    // MARK: - Vocabulary

    var vocabularySection: some View {
        SettingsKit.Section("Vocabulary") {
            SettingsKit.Row(
                "Dictionary",
                description: "Replacements fix words SayIt mishears with any model. Custom words also help Parakeet recognize names and terms.",
                systemImage: "character.book.closed"
            ) {
                Button("Open Dictionary") {
                    NotificationCenter.default.post(name: .openCustomDictionaryFromVoiceEngine, object: nil)
                }
                .buttonStyle(.sayIt(.secondary, size: .small))
            }
        }
    }

    // MARK: - Model Logo

    func speechModelLogoView(for model: SettingsStore.SpeechModel, size: CGFloat) -> some View {
        let imageName = self.speechModelImageName(for: model)
        let shape = RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)

        return ZStack {
            shape.fill(self.speechModelPlateColor(for: model))

            if model.usesAppleLogo {
                Image(systemName: "apple.logo")
                    .font(size > Layout.rowLogoSize ? AppFont.iconLarge : AppFont.icon)
                    .foregroundStyle(self.theme.palette.primaryText)
            } else if let imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .padding(size * (model.provider == .nvidia ? 0.1 : 0.2))
            } else {
                Text(String(model.brandName.prefix(2)).uppercased())
                    .font(AppFont.micro)
                    .foregroundStyle(Color(hex: model.brandColorHex) ?? self.theme.palette.primaryText)
            }
        }
        .frame(width: size, height: size)
        .overlay(shape.strokeBorder(self.theme.palette.hairline, lineWidth: 1))
        .accessibilityHidden(true)
    }

    /// Brand logos with dark artwork sit on a white plate; others on the sunken surface
    /// tinted with the brand color.
    private func speechModelPlateColor(for model: SettingsStore.SpeechModel) -> Color {
        switch model.provider {
        case .nvidia, .openai:
            return .white
        case .apple:
            return self.theme.palette.surfaceSunken
        case .qwen:
            return self.theme.palette.subtle(Color(hex: model.brandColorHex) ?? self.theme.palette.accent)
        }
    }

    private func speechModelImageName(for model: SettingsStore.SpeechModel) -> String? {
        switch model.provider {
        case .nvidia: return "Provider_NVIDIA"
        case .openai: return "Provider_OpenAI"
        default: return nil
        }
    }
}

extension Notification.Name {
    static let openCustomDictionaryFromVoiceEngine = Notification.Name("OpenCustomDictionaryFromVoiceEngine")
}
