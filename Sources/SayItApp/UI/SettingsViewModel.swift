import AppKit
import Foundation
import SayItCore

enum CodexAuthMode: String, CaseIterable, Identifiable {
    case oauth
    case manual

    var id: String { rawValue }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var openAIAPIKey: String = ""
    @Published var codexAccessToken: String = ""
    @Published var codexAccountID: String = ""
    @Published var availablePipelines: [TextPipeline] = []
    @Published var selectedPipelineID: UUID?
    @Published var editingPipelineID: UUID?
    @Published var selectedLocale: String = "zh-Hans"
    @Published var selectedPrimarySTT: String = "faster_whisper"
    @Published var selectedLocalFallback: String = "faster_whisper"
    @Published var selectedRefinePrimary: String = "codex_oauth"
    @Published var selectedTTSPrimary: String = "openai_tts"
    @Published var hotkeyKeyCode: UInt32 = AppConfig.HotkeyConfig().keyCode
    @Published var hotkeyModifiers: UInt32 = AppConfig.HotkeyConfig().modifiers
    @Published var codexOAuthStatusLine: String = "Unknown"
    @Published var codexOAuthSourcePath: String = ""
    @Published var codexOAuthLastRefreshText: String = ""
    @Published var codexDeviceAuthURL: String = ""
    @Published var codexDeviceAuthCode: String = ""
    @Published var codexOAuthLogs: [String] = []
    @Published var codexOAuthInProgress: Bool = false
    @Published var codexAuthMode: CodexAuthMode = .oauth
    @Published var status: String = ""

    let availableLocales: [String] = ["zh-Hans", "en", "ja"]
    let availablePrimarySTT: [String] = ["faster_whisper"]
    let availableLocalFallbacks: [String] = ["faster_whisper"]
    let availableRefineProviders: [String] = ["codex_oauth", "openai_api"]
    let availableTTSProviders: [String] = ["openai_tts", "system_tts"]

    private let runtime: SayItCoreRuntime?
    private let onSaved: ((AppConfig) -> Void)?
    private var codexDeviceAuthTask: Task<Void, Never>?
    private var hasLoadedSensitiveCredentials = false
    private var hasLoadedManualCodexCredentials = false

    var hotkeyDisplayText: String {
        HotkeyFormatter.displayString(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
    }

    var editingPipeline: TextPipeline? {
        guard let index = editingPipelineIndex() else { return nil }
        return availablePipelines[index]
    }

    init(runtime: SayItCoreRuntime?, onSaved: ((AppConfig) -> Void)? = nil) {
        self.runtime = runtime
        self.onSaved = onSaved
        load(includeSecrets: false)
    }

    deinit {
        codexDeviceAuthTask?.cancel()
    }

    func load(includeSecrets: Bool = true, forceSecretsReload: Bool = false) {
        guard let runtime else {
            status = "Settings unavailable"
            return
        }

        do {
            let config = try runtime.configManager.load()
            availablePipelines = try runtime.pipelineStore.load()
            selectedPipelineID = config.pipeline.defaultID ?? availablePipelines.first?.id
            editingPipelineID = selectedPipelineID ?? availablePipelines.first?.id
            selectedLocale = config.locale
            selectedPrimarySTT = "faster_whisper"
            selectedLocalFallback = "faster_whisper"
            selectedRefinePrimary = config.refine.primary
            selectedTTSPrimary = config.tts.primary
            hotkeyKeyCode = config.hotkey.keyCode
            hotkeyModifiers = HotkeyFormatter.normalizedModifiers(config.hotkey.modifiers)
            if includeSecrets {
                try loadSensitiveCredentials(forceReload: forceSecretsReload)
                Task { await refreshCodexOAuthStatus() }
            }
            status = ""
        } catch {
            status = "Load error: \(error.localizedDescription)"
        }
    }

    func createPipeline() {
        let pipeline = TextPipeline(
            name: "New Pipeline",
            stages: [PipelineStage(type: .whitespaceNormalize)]
        )
        availablePipelines.append(pipeline)
        editingPipelineID = pipeline.id
        if selectedPipelineID == nil {
            selectedPipelineID = pipeline.id
        }
        persistPipelines(statusMessage: "Pipeline created")
    }

    func duplicateEditingPipeline() {
        guard let pipeline = editingPipeline else {
            status = "No pipeline selected"
            return
        }

        let duplicatedStages = pipeline.stages.map { stage in
            PipelineStage(id: UUID(), type: stage.type, enabled: stage.enabled, config: stage.config)
        }
        let duplicated = TextPipeline(
            name: "\(pipeline.name) Copy",
            enabled: pipeline.enabled,
            stages: duplicatedStages
        )
        availablePipelines.append(duplicated)
        editingPipelineID = duplicated.id
        persistPipelines(statusMessage: "Pipeline duplicated")
    }

    func deleteEditingPipeline() {
        guard let targetID = editingPipelineID else {
            status = "No pipeline selected"
            return
        }

        availablePipelines.removeAll { $0.id == targetID }
        if availablePipelines.isEmpty {
            availablePipelines = DefaultPipelines.all()
        }
        if let selectedPipelineID, !availablePipelines.contains(where: { $0.id == selectedPipelineID }) {
            self.selectedPipelineID = availablePipelines.first?.id
        }
        if let editingPipelineID, !availablePipelines.contains(where: { $0.id == editingPipelineID }) {
            self.editingPipelineID = availablePipelines.first?.id
        }
        persistPipelines(statusMessage: "Pipeline removed")
    }

    func renameEditingPipeline(_ name: String) {
        mutateEditingPipeline { pipeline in
            pipeline.name = name
        }
    }

    func setEditingPipelineEnabled(_ enabled: Bool) {
        mutateEditingPipeline { pipeline in
            pipeline.enabled = enabled
        }
    }

    func addStage(type: PipelineStageType) {
        mutateEditingPipeline { pipeline in
            pipeline.stages.append(
                PipelineStage(type: type, config: Self.defaultConfig(for: type))
            )
        }
    }

    func removeStage(stageID: UUID) {
        mutateEditingPipeline { pipeline in
            pipeline.stages.removeAll { $0.id == stageID }
        }
    }

    func updateStageEnabled(stageID: UUID, enabled: Bool) {
        mutateEditingPipeline { pipeline in
            guard let index = pipeline.stages.firstIndex(where: { $0.id == stageID }) else { return }
            pipeline.stages[index].enabled = enabled
        }
    }

    func updateStageType(stageID: UUID, type: PipelineStageType) {
        mutateEditingPipeline { pipeline in
            guard let index = pipeline.stages.firstIndex(where: { $0.id == stageID }) else { return }
            pipeline.stages[index].type = type
            if pipeline.stages[index].config.isEmpty {
                pipeline.stages[index].config = Self.defaultConfig(for: type)
            }
        }
    }

    func updateStageConfig(stageID: UUID, key: String, value: String) {
        mutateEditingPipeline { pipeline in
            guard let index = pipeline.stages.firstIndex(where: { $0.id == stageID }) else { return }
            if value.isEmpty {
                pipeline.stages[index].config.removeValue(forKey: key)
            } else {
                pipeline.stages[index].config[key] = value
            }
        }
    }

    func stageConfigValue(stageID: UUID, key: String) -> String {
        guard
            let pipeline = editingPipeline,
            let stage = pipeline.stages.first(where: { $0.id == stageID })
        else {
            return ""
        }
        return stage.config[key] ?? ""
    }

    func canMoveStageUp(stageID: UUID) -> Bool {
        guard
            let pipeline = editingPipeline,
            let index = pipeline.stages.firstIndex(where: { $0.id == stageID })
        else {
            return false
        }
        return index > 0
    }

    func canMoveStageDown(stageID: UUID) -> Bool {
        guard
            let pipeline = editingPipeline,
            let index = pipeline.stages.firstIndex(where: { $0.id == stageID })
        else {
            return false
        }
        return index < pipeline.stages.count - 1
    }

    func moveStageUp(stageID: UUID) {
        mutateEditingPipeline { pipeline in
            guard let index = pipeline.stages.firstIndex(where: { $0.id == stageID }), index > 0 else { return }
            pipeline.stages.swapAt(index, index - 1)
        }
    }

    func moveStageDown(stageID: UUID) {
        mutateEditingPipeline { pipeline in
            guard let index = pipeline.stages.firstIndex(where: { $0.id == stageID }), index < pipeline.stages.count - 1 else { return }
            pipeline.stages.swapAt(index, index + 1)
        }
    }

    func save() {
        guard let runtime else {
            status = "Settings unavailable"
            return
        }

        do {
            var config = try runtime.configManager.load()
            config.pipeline.defaultID = selectedPipelineID ?? availablePipelines.first?.id
            config.locale = selectedLocale
            config.stt.primary = "faster_whisper"
            config.stt.localDefault = "faster_whisper"
            config.fallbackPolicy.primarySTT = "faster_whisper"
            config.fallbackPolicy.localFallback = "faster_whisper"
            config.refine.primary = selectedRefinePrimary
            config.tts.primary = selectedTTSPrimary
            config.hotkey.keyCode = hotkeyKeyCode
            config.hotkey.modifiers = HotkeyFormatter.normalizedModifiers(hotkeyModifiers)
            guard HotkeyFormatter.hasModifier(config.hotkey.modifiers) else {
                status = "Hotkey requires at least one modifier"
                return
            }
            try runtime.configManager.save(config)
            if !openAIAPIKey.isEmpty {
                try runtime.keychain.set(openAIAPIKey, for: "openai_api_key")
            } else {
                runtime.keychain.delete("openai_api_key")
            }
            runtime.invalidateOpenAIAPIKeyCache()
            hasLoadedSensitiveCredentials = true

            if codexAuthMode == .manual {
                if !codexAccessToken.isEmpty {
                    try runtime.keychain.set(codexAccessToken, for: "codex_access_token")
                } else {
                    runtime.keychain.delete("codex_access_token")
                }
                if !codexAccountID.isEmpty {
                    try runtime.keychain.set(codexAccountID, for: "codex_account_id")
                } else {
                    runtime.keychain.delete("codex_account_id")
                }
                hasLoadedManualCodexCredentials = true
            }
            status = "Saved"
            onSaved?(config)
        } catch {
            status = "Save error: \(error.localizedDescription)"
        }
    }

    func updateHotkey(keyCode: UInt32, modifiers: UInt32) {
        let normalized = HotkeyFormatter.normalizedModifiers(modifiers)
        guard HotkeyFormatter.hasModifier(normalized) else {
            status = "Hotkey requires at least one modifier"
            return
        }
        hotkeyKeyCode = keyCode
        hotkeyModifiers = normalized
        status = "Hotkey updated: \(hotkeyDisplayText)"
    }

    func resetHotkeyToDefault() {
        let defaultConfig = AppConfig.HotkeyConfig()
        hotkeyKeyCode = defaultConfig.keyCode
        hotkeyModifiers = HotkeyFormatter.normalizedModifiers(defaultConfig.modifiers)
        status = "Hotkey reset: \(hotkeyDisplayText)"
    }

    func importFromCodexCLI() {
        Task {
            await importFromCodexCLIAsync()
        }
    }

    func refreshCodexOAuthStatus() async {
        guard let runtime else {
            codexOAuthStatusLine = "Unavailable"
            return
        }

        do {
            let result = try await runtime.codexOAuthManager.status()
            codexOAuthStatusLine = result.statusLine
            codexOAuthSourcePath = result.sourcePath ?? ""
            if let date = result.lastRefresh {
                codexOAuthLastRefreshText = DateFormatter.codexStatus.string(from: date)
            } else {
                codexOAuthLastRefreshText = ""
            }
            if result.isLoggedIn {
                codexAuthMode = .oauth
            }
        } catch {
            codexOAuthStatusLine = "Status error: \(error.localizedDescription)"
            codexOAuthSourcePath = ""
            codexOAuthLastRefreshText = ""
        }
    }

    func setCodexAuthMode(_ mode: CodexAuthMode) {
        codexAuthMode = mode
        if mode == .manual {
            cancelCodexDeviceLogin()
            codexDeviceAuthURL = ""
            codexDeviceAuthCode = ""
            codexOAuthLogs = []
            do {
                try loadManualCodexCredentials(forceReload: false)
            } catch {
                statusMessage("Keychain read error: \(error.localizedDescription)")
            }
        }
    }

    func startCodexDeviceLogin() {
        guard let runtime else {
            status = "Settings unavailable"
            return
        }
        guard codexDeviceAuthTask == nil else {
            status = "Codex login already running"
            return
        }

        codexOAuthLogs = []
        codexDeviceAuthURL = ""
        codexDeviceAuthCode = ""
        codexOAuthInProgress = true
        codexAuthMode = .oauth
        codexOAuthStatusLine = "Starting device auth..."

        codexDeviceAuthTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = await runtime.codexOAuthManager.startDeviceAuthFlow()
                for try await event in stream {
                    if Task.isCancelled { break }
                    switch event {
                    case .output(let line):
                        appendOAuthLog(line)
                    case .challenge(let url, let code):
                        codexDeviceAuthURL = url.absoluteString
                        codexDeviceAuthCode = code
                        codexOAuthStatusLine = "Waiting for browser confirmation"
                    case .completed(let status):
                        codexOAuthStatusLine = status.statusLine
                        codexOAuthSourcePath = status.sourcePath ?? ""
                        if let date = status.lastRefresh {
                            codexOAuthLastRefreshText = DateFormatter.codexStatus.string(from: date)
                        } else {
                            codexOAuthLastRefreshText = ""
                        }
                        codexAuthMode = .oauth
                        loadFromKeychainOnly()
                        statusMessage("Codex OAuth login complete")
                    }
                }
                codexOAuthInProgress = false
                codexDeviceAuthTask = nil
            } catch {
                codexOAuthInProgress = false
                codexDeviceAuthTask = nil
                codexOAuthStatusLine = "Login failed"
                statusMessage("Codex login error: \(error.localizedDescription)")
            }
        }
    }

    func cancelCodexDeviceLogin() {
        codexDeviceAuthTask?.cancel()
        codexDeviceAuthTask = nil
        codexOAuthInProgress = false
        codexOAuthStatusLine = "Device auth cancelled"
        guard let runtime else { return }
        Task {
            await runtime.codexOAuthManager.cancelActiveLogin()
        }
    }

    func copyCodexDeviceCode() {
        let code = codexDeviceAuthCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            statusMessage("No device code to copy")
            return
        }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(code, forType: .string)
        statusMessage("Device code copied")
    }

    func copyCodexAuthURL() {
        let value = codexDeviceAuthURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            statusMessage("No auth URL to copy")
            return
        }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(value, forType: .string)
        statusMessage("Auth URL copied")
    }

    func logoutCodexOAuth() {
        guard let runtime else {
            status = "Settings unavailable"
            return
        }

        Task {
            do {
                try await runtime.codexOAuthManager.logout()
                codexAccessToken = ""
                codexAccountID = ""
                codexDeviceAuthCode = ""
                codexDeviceAuthURL = ""
                codexOAuthLogs = []
                codexOAuthStatusLine = "Logged out"
                codexOAuthSourcePath = ""
                codexOAuthLastRefreshText = ""
                codexAuthMode = .manual
                statusMessage("Codex OAuth logged out")
            } catch {
                statusMessage("Logout error: \(error.localizedDescription)")
            }
        }
    }

    private func mutateEditingPipeline(_ mutation: (inout TextPipeline) -> Void) {
        guard let index = editingPipelineIndex() else {
            status = "No pipeline selected"
            return
        }
        mutation(&availablePipelines[index])
        persistPipelines(statusMessage: nil)
    }

    private func editingPipelineIndex() -> Int? {
        guard let targetID = editingPipelineID ?? availablePipelines.first?.id else { return nil }
        return availablePipelines.firstIndex(where: { $0.id == targetID })
    }

    private func persistPipelines(statusMessage: String?) {
        guard let runtime else {
            status = "Settings unavailable"
            return
        }

        do {
            try runtime.pipelineStore.save(availablePipelines)
            var config = try runtime.configManager.load()
            if let selectedPipelineID, availablePipelines.contains(where: { $0.id == selectedPipelineID }) {
                config.pipeline.defaultID = selectedPipelineID
            } else {
                config.pipeline.defaultID = availablePipelines.first?.id
                selectedPipelineID = config.pipeline.defaultID
            }
            if let editingPipelineID, !availablePipelines.contains(where: { $0.id == editingPipelineID }) {
                self.editingPipelineID = availablePipelines.first?.id
            } else if self.editingPipelineID == nil {
                self.editingPipelineID = availablePipelines.first?.id
            }
            try runtime.configManager.save(config)
            if let statusMessage {
                status = statusMessage
            }
        } catch {
            status = "Pipeline save error: \(error.localizedDescription)"
        }
    }

    private static func defaultConfig(for type: PipelineStageType) -> [String: String] {
        switch type {
        case .regexReplace:
            return ["pattern": "", "replacement": ""]
        case .templateApply:
            return ["template": "{{text}}"]
        case .codeCommentTemplate:
            return ["style": "swift"]
        case .llmRewrite:
            return ["prompt": ""]
        default:
            return [:]
        }
    }

    private func importFromCodexCLIAsync() async {
        guard let runtime else {
            statusMessage("Settings unavailable")
            return
        }

        do {
            let oauthStatus = try await runtime.codexOAuthManager.syncFromDefaultAuthFile()
            loadFromKeychainOnly()
            codexOAuthStatusLine = oauthStatus.statusLine
            codexOAuthSourcePath = oauthStatus.sourcePath ?? ""
            if let date = oauthStatus.lastRefresh {
                codexOAuthLastRefreshText = DateFormatter.codexStatus.string(from: date)
            } else {
                codexOAuthLastRefreshText = ""
            }
            codexAuthMode = .oauth
            statusMessage("Imported from Codex auth file")
        } catch {
            statusMessage("Import error: \(error.localizedDescription)")
        }
    }

    private func loadFromKeychainOnly() {
        guard let runtime else { return }
        do {
            openAIAPIKey = (try runtime.keychain.get("openai_api_key")) ?? openAIAPIKey
            hasLoadedSensitiveCredentials = true
        } catch {
            statusMessage("Keychain read error: \(error.localizedDescription)")
        }
    }

    private func loadSensitiveCredentials(forceReload: Bool) throws {
        guard let runtime else { return }
        if forceReload || !hasLoadedSensitiveCredentials {
            openAIAPIKey = (try runtime.keychain.get("openai_api_key")) ?? ""
            hasLoadedSensitiveCredentials = true
        }

        if codexAuthMode == .manual {
            try loadManualCodexCredentials(forceReload: forceReload)
        }
    }

    private func loadManualCodexCredentials(forceReload: Bool) throws {
        guard let runtime else { return }
        if forceReload || !hasLoadedManualCodexCredentials {
            codexAccessToken = (try runtime.keychain.get("codex_access_token")) ?? ""
            codexAccountID = (try runtime.keychain.get("codex_account_id")) ?? ""
            hasLoadedManualCodexCredentials = true
        }
    }

    private func appendOAuthLog(_ line: String) {
        codexOAuthLogs.append(line)
        if codexOAuthLogs.count > 80 {
            codexOAuthLogs.removeFirst(codexOAuthLogs.count - 80)
        }
    }

    private func statusMessage(_ message: String) {
        status = message
    }
}

private extension DateFormatter {
    static let codexStatus: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}
