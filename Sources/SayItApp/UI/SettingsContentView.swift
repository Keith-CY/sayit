import SayItCore
import SwiftUI

private enum SettingsPanel: String, CaseIterable, Identifiable {
    case general
    case access
    case pipeline
    case models

    var id: String { rawValue }
}

struct SettingsContentView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var modelsViewModel: LocalModelsViewModel
    @EnvironmentObject private var language: AppLanguageCenter
    @State private var selectedPanel: SettingsPanel = .general
    @Namespace private var sidebarSelection

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Divider()

                ScrollView {
                    ZStack(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 14) {
                            contentTitle
                            panelContent
                        }
                        .id(selectedPanel)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            Divider()
            HStack(spacing: 8) {
                Button(language.text("settings.save")) {
                    viewModel.save()
                }
                Button(language.text("history.refresh")) {
                    viewModel.load()
                    modelsViewModel.refresh()
                }
                Spacer()
                if !viewModel.status.isEmpty {
                    Text(viewModel.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .animation(.easeInOut(duration: 0.18), value: selectedPanel)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(SettingsPanel.allCases) { panel in
                Button {
                    selectedPanel = panel
                } label: {
                    Text(title(for: panel))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            ZStack {
                                if selectedPanel == panel {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.16))
                                        .matchedGeometryEffect(id: "settings-panel-selection", in: sidebarSelection)
                                } else {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.clear)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(12)
        .frame(minWidth: 180, maxWidth: 220, maxHeight: .infinity, alignment: .topLeading)
    }

    private var contentTitle: some View {
        Text(title(for: selectedPanel))
            .font(.title3.weight(.semibold))
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private var panelContent: some View {
        switch selectedPanel {
        case .general:
            generalPanel
        case .access:
            accessPanel
        case .pipeline:
            pipelinePanel
        case .models:
            modelsPanel
        }
    }

    private var generalPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox(language.text("settings.locale")) {
                Picker("", selection: $viewModel.selectedLocale) {
                    Text("中文").tag("zh-Hans")
                    Text("English").tag("en")
                    Text("日本語").tag("ja")
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.selectedLocale) { _, newValue in
                    language.setLocale(newValue)
                }
            }

            GroupBox(language.text("settings.primaryStt")) {
                Picker("", selection: $viewModel.selectedPrimarySTT) {
                    ForEach(viewModel.availablePrimarySTT, id: \.self) { item in
                        Text(item).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }

            GroupBox(language.text("settings.localFallback")) {
                Picker("", selection: $viewModel.selectedLocalFallback) {
                    ForEach(viewModel.availableLocalFallbacks, id: \.self) { item in
                        Text(item).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }

            GroupBox(language.text("settings.refinePrimary")) {
                Picker("", selection: $viewModel.selectedRefinePrimary) {
                    ForEach(viewModel.availableRefineProviders, id: \.self) { item in
                        Text(item).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }

            GroupBox(language.text("settings.ttsPrimary")) {
                Picker("", selection: $viewModel.selectedTTSPrimary) {
                    ForEach(viewModel.availableTTSProviders, id: \.self) { item in
                        Text(item).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var accessPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox(language.text("settings.apiKey")) {
                SecureField("sk-...", text: $viewModel.openAIAPIKey)
                    .textFieldStyle(.roundedBorder)
            }

            GroupBox(language.text("settings.codexOAuth")) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker(
                        language.text("settings.codexAuthMode"),
                        selection: Binding(
                            get: { viewModel.codexAuthMode },
                            set: { viewModel.setCodexAuthMode($0) }
                        )
                    ) {
                        Text(language.text("settings.codexAuthModeOAuth")).tag(CodexAuthMode.oauth)
                        Text(language.text("settings.codexAuthModeManual")).tag(CodexAuthMode.manual)
                    }
                    .pickerStyle(.segmented)

                    if viewModel.codexAuthMode == .oauth {
                        oauthGuide
                    } else {
                        manualTokenEditor
                    }
                }
                .animation(.easeInOut(duration: 0.16), value: viewModel.codexAuthMode)
            }
        }
    }

    private var oauthGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(language.text("settings.codexOAuthStatus")): \(viewModel.codexOAuthStatusLine)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !viewModel.codexOAuthSourcePath.isEmpty {
                Text("\(language.text("settings.codexOAuthSource")): \(viewModel.codexOAuthSourcePath)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !viewModel.codexOAuthLastRefreshText.isEmpty {
                Text("\(language.text("settings.codexOAuthLastRefresh")): \(viewModel.codexOAuthLastRefreshText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("1. \(language.text("settings.codexOAuthStep1"))")
                .font(.callout)
            HStack(spacing: 8) {
                Button(language.text("settings.codexOAuthStart")) {
                    viewModel.startCodexDeviceLogin()
                }
                .disabled(viewModel.codexOAuthInProgress)

                Button(language.text("settings.codexOAuthCancel")) {
                    viewModel.cancelCodexDeviceLogin()
                }
                .disabled(!viewModel.codexOAuthInProgress)

                Button(language.text("settings.codexOAuthRefresh")) {
                    Task { await viewModel.refreshCodexOAuthStatus() }
                }

                Button(language.text("settings.codexOAuthLogout")) {
                    viewModel.logoutCodexOAuth()
                }
            }

            if !viewModel.codexDeviceAuthURL.isEmpty {
                Text("2. \(language.text("settings.codexOAuthStep2"))")
                    .font(.callout)
                HStack(alignment: .top, spacing: 8) {
                    if let url = URL(string: viewModel.codexDeviceAuthURL) {
                        Link(viewModel.codexDeviceAuthURL, destination: url)
                            .font(.caption)
                    } else {
                        Text(viewModel.codexDeviceAuthURL)
                            .font(.caption)
                    }
                    Spacer()
                    Button(language.text("settings.codexOAuthCopyURL")) {
                        viewModel.copyCodexAuthURL()
                    }
                }
            }

            if !viewModel.codexDeviceAuthCode.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(language.text("settings.codexOAuthCode")):")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.codexDeviceAuthCode)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                    Spacer()
                    Button(language.text("settings.codexOAuthCopyCode")) {
                        viewModel.copyCodexDeviceCode()
                    }
                }
            }

            Text("3. \(language.text("settings.codexOAuthStep3"))")
                .font(.callout)

            Button(language.text("settings.importCodex")) {
                viewModel.importFromCodexCLI()
            }

            if !viewModel.codexOAuthLogs.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(viewModel.codexOAuthLogs.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption2.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(minHeight: 80, maxHeight: 160)
            }
        }
    }

    private var manualTokenEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text("settings.codexManualTokenHint"))
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField("token", text: $viewModel.codexAccessToken)
                .textFieldStyle(.roundedBorder)

            TextField("acc_...", text: $viewModel.codexAccountID)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var pipelinePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox(language.text("settings.defaultPipeline")) {
                if viewModel.availablePipelines.isEmpty {
                    Text(language.text("settings.noPipeline"))
                        .foregroundStyle(.secondary)
                } else {
                    Picker("", selection: $viewModel.selectedPipelineID) {
                        ForEach(viewModel.availablePipelines) { pipeline in
                            Text(pipeline.name).tag(Optional(pipeline.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            GroupBox(language.text("settings.pipelineEditor")) {
                PipelineEditorView(viewModel: viewModel)
            }
        }
    }

    private var modelsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(modelsViewModel.catalog) { model in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(modelTitle(for: model))
                            Text("\(model.engine.rawValue) • \(modelsViewModel.sizeLabel(for: model))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(modelsViewModel.runtimeRequirementHint(for: model))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(modelsViewModel.isInstalled(model) ? language.text("settings.remove") : language.text("settings.download")) {
                            Task { await modelsViewModel.toggle(model) }
                        }
                        .disabled(modelsViewModel.isBusy)
                    }

                    Text("\(language.text("settings.modelPath")): \(modelsViewModel.installedPath(for: model))")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Text("\(language.text("settings.modelQuickStatus")): \(quickStatusText(for: model))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(language.text("settings.modelVerifyStatus")): \(verifyStatusText(for: model))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let progress = modelsViewModel.progress(for: model), progress > 0, progress < 1 {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                    }

                    HStack(spacing: 8) {
                        Button(language.text("settings.modelVerify")) {
                            Task { await modelsViewModel.verify(model) }
                        }
                        .disabled(modelsViewModel.isBusy)

                        Button(language.text("settings.modelRetry")) {
                            Task { await modelsViewModel.retry(model) }
                        }
                        .disabled(modelsViewModel.isBusy)

                        Button(language.text("settings.modelCleanup")) {
                            Task { await modelsViewModel.cleanup(model) }
                        }
                        .disabled(modelsViewModel.isBusy)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(8)
            }

            HStack {
                Button(language.text("settings.modelRefresh")) {
                    modelsViewModel.refresh()
                }
                Text(modelsViewModel.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func title(for panel: SettingsPanel) -> String {
        switch panel {
        case .general:
            return language.text("settings.sectionGeneral")
        case .access:
            return language.text("settings.sectionAccess")
        case .pipeline:
            return language.text("settings.sectionPipeline")
        case .models:
            return language.text("settings.sectionModels")
        }
    }

    private func quickStatusText(for model: LocalModelDescriptor) -> String {
        switch modelsViewModel.quickStatus(for: model) {
        case .installed:
            return language.text("settings.modelQuickInstalled")
        case .sizeMismatch:
            return language.text("settings.modelQuickSizeMismatch")
        case .partialOnly:
            return language.text("settings.modelQuickPartialOnly")
        case .notInstalled:
            return language.text("settings.modelQuickNotInstalled")
        }
    }

    private func verifyStatusText(for model: LocalModelDescriptor) -> String {
        if modelsViewModel.isVerifying(model) {
            return language.text("settings.modelVerifyChecking")
        }

        guard let result = modelsViewModel.verification(for: model) else {
            return language.text("settings.modelVerifyNotChecked")
        }

        if result.isValid {
            return language.text("settings.modelVerifyValid")
        }

        switch result.reason {
        case "missing":
            return language.text("settings.modelVerifyMissing")
        case "size_mismatch":
            return language.text("settings.modelVerifySizeMismatch")
        case "checksum_mismatch":
            return language.text("settings.modelVerifyChecksumMismatch")
        default:
            return language.text("settings.modelVerifyInvalid")
        }
    }

    private func modelTitle(for model: LocalModelDescriptor) -> String {
        if model.engine == .whisper {
            return "WHISPER (default) • \(model.name)"
        }
        return "\(model.engine.rawValue.uppercased()) • \(model.name)"
    }
}
