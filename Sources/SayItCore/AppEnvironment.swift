import Foundation

public final class SayItCoreRuntime {
    public let configManager: AppConfigManager
    public let keychain: KeychainStore
    public let sqliteStore: SQLiteStore
    public let historyRepository: HistoryRepository
    public let pipelineStore: PipelineStore
    public let exportService: ExportService
    public let modelDownloadManager: ModelDownloadManager
    public let audioAssetStore: AudioAssetStore
    public let codexOAuthManager: CodexOAuthManager

    public let fallbackStateMachine: FallbackStateMachine
    public let primarySTTProvider: STTProvider
    public let whisperProvider: STTProvider
    public let fasterWhisperProvider: STTProvider
    public let parakeetProvider: STTProvider
    public let moonshineProvider: STTProvider
    public let orchestrator: TranscriptionOrchestrator

    public let codexRefineProvider: RefineProvider
    public let openAIRefineProvider: RefineProvider
    public let openAITTSProvider: TTSProvider
    public let systemTTSProvider: TTSProvider
    private let openAIKeyResolver: OpenAIAPIKeyResolver

    public init(configURL: URL? = nil, databaseURL: URL? = nil) throws {
        let configManager = AppConfigManager(configURL: configURL)
        let keychain = KeychainStore()
        let sqliteStore = try SQLiteStore(url: databaseURL)
        let historyRepository = HistoryRepository(store: sqliteStore)
        let pipelineStore = PipelineStore()
        let exportService = ExportService(repository: historyRepository)
        let modelDownloadManager = ModelDownloadManager()
        let audioAssetStore = AudioAssetStore()
        let codexOAuthManager = CodexOAuthManager(keychain: keychain)
        let openAIKeyResolver = OpenAIAPIKeyResolver(keychain: keychain)

        var config = try configManager.load()
        let availablePipelines = try pipelineStore.load()
        if config.pipeline.defaultID == nil, let first = availablePipelines.first?.id {
            config.pipeline.defaultID = first
            try configManager.save(config)
        }
        let fallbackStateMachine = FallbackStateMachine(policy: config.fallbackPolicy)

        let fasterWhisperProvider = FasterWhisperSTTProvider()
        let whisperProvider: STTProvider = WhisperSTTProvider()
        let parakeetProvider: STTProvider = ParakeetSTTProvider()
        let moonshineProvider: STTProvider = MoonshineSTTProvider()
        let primarySTTProvider: STTProvider = fasterWhisperProvider

        let openAIRefineProvider = OpenAIRefineProvider {
            try await openAIKeyResolver.apiKey()
        }

        let codexRefineProvider = CodexOAuthRefineProvider(keychain: keychain, oauthManager: codexOAuthManager)
        let pipelineExecutor = PipelineExecutor(refineProvider: codexRefineProvider)

        let orchestrator = TranscriptionOrchestrator(
            primary: primarySTTProvider,
            localFallback: fasterWhisperProvider,
            fallbackStateMachine: fallbackStateMachine,
            pipelineExecutor: pipelineExecutor,
            repository: historyRepository
        )

        let openAITTSProvider = OpenAITTSProvider {
            try await openAIKeyResolver.apiKey()
        }
        let systemTTSProvider = SystemTTSProvider()

        self.configManager = configManager
        self.keychain = keychain
        self.sqliteStore = sqliteStore
        self.historyRepository = historyRepository
        self.pipelineStore = pipelineStore
        self.exportService = exportService
        self.modelDownloadManager = modelDownloadManager
        self.audioAssetStore = audioAssetStore
        self.codexOAuthManager = codexOAuthManager
        self.fallbackStateMachine = fallbackStateMachine
        self.primarySTTProvider = primarySTTProvider
        self.whisperProvider = whisperProvider
        self.fasterWhisperProvider = fasterWhisperProvider
        self.parakeetProvider = parakeetProvider
        self.moonshineProvider = moonshineProvider
        self.orchestrator = orchestrator
        self.codexRefineProvider = codexRefineProvider
        self.openAIRefineProvider = openAIRefineProvider
        self.openAITTSProvider = openAITTSProvider
        self.systemTTSProvider = systemTTSProvider
        self.openAIKeyResolver = openAIKeyResolver
    }

    public func invalidateOpenAIAPIKeyCache() {
        Task { [openAIKeyResolver] in
            await openAIKeyResolver.invalidate()
        }
    }

    public func sttProvider(for id: String) -> STTProvider {
        switch id {
        case fasterWhisperProvider.id:
            return fasterWhisperProvider
        case whisperProvider.id:
            return whisperProvider
        case parakeetProvider.id:
            return parakeetProvider
        case moonshineProvider.id:
            return moonshineProvider
        case "openai":
            // OpenAI STT is intentionally disabled; keep legacy config usable.
            return fasterWhisperProvider
        default:
            return fasterWhisperProvider
        }
    }

    public func refineProvider(for id: String) -> RefineProvider {
        switch id {
        case codexRefineProvider.id:
            return codexRefineProvider
        case openAIRefineProvider.id:
            return openAIRefineProvider
        default:
            return codexRefineProvider
        }
    }

    public func ttsProvider(for id: String) -> TTSProvider {
        switch id {
        case systemTTSProvider.id:
            return systemTTSProvider
        case openAITTSProvider.id:
            return openAITTSProvider
        default:
            return openAITTSProvider
        }
    }
}

private actor OpenAIAPIKeyResolver {
    private let keychain: KeychainStore
    private var cachedCredential: String?
    private var cachedSTTCredential: OpenAISTTProvider.Credential?

    init(keychain: KeychainStore) {
        self.keychain = keychain
    }

    func apiKey() throws -> String {
        if let cachedCredential, !cachedCredential.isEmpty {
            return cachedCredential
        }

        if let key = normalized(try keychain.get("openai_api_key")) {
            cachedCredential = key
            return key
        }

        if let snapshot = try? CodexAuthImporter.importFromDefaultLocations(),
           let key = normalized(snapshot.openAIAPIKey)
        {
            cachedCredential = key
            return key
        }

        throw SayItError.authentication(
            "OpenAI API key is missing. Set openai_api_key or ensure ~/.codex/auth.json contains OPENAI_API_KEY."
        )
    }

    func sttCredential() throws -> OpenAISTTProvider.Credential {
        if let cachedSTTCredential, !cachedSTTCredential.token.isEmpty {
            return cachedSTTCredential
        }

        if let key = normalized(try keychain.get("openai_api_key")) {
            let credential = OpenAISTTProvider.Credential(token: key, mode: .apiKey)
            cache(credential)
            return credential
        }

        if let snapshot = try? CodexAuthImporter.importFromDefaultLocations() {
            if let openAIKey = normalized(snapshot.openAIAPIKey) {
                let credential = OpenAISTTProvider.Credential(token: openAIKey, mode: .apiKey)
                cache(credential)
                return credential
            }
            if let codexAccessToken = normalized(snapshot.codexAccessToken) {
                let credential = OpenAISTTProvider.Credential(
                    token: codexAccessToken,
                    mode: .codexOAuth,
                    accountID: normalized(snapshot.codexAccountID),
                    chatGPTBaseURL: preferredChatGPTBaseURL()
                )
                cache(credential)
                return credential
            }
        }

        if let codexAccessToken = normalized(try keychain.get("codex_access_token")) {
            let credential = OpenAISTTProvider.Credential(
                token: codexAccessToken,
                mode: .codexOAuth,
                accountID: normalized(try keychain.get("codex_account_id")),
                chatGPTBaseURL: preferredChatGPTBaseURL()
            )
            cache(credential)
            return credential
        }

        throw SayItError.authentication(
            "OpenAI credential is missing. Set openai_api_key, or run Codex login and ensure ~/.codex/auth.json contains usable credentials."
        )
    }

    func invalidate() {
        cachedCredential = nil
        cachedSTTCredential = nil
    }

    private func cache(_ credential: OpenAISTTProvider.Credential) {
        cachedCredential = credential.token
        cachedSTTCredential = credential
    }

    private func preferredChatGPTBaseURL() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let value = normalized(env["SAYIT_CHATGPT_BASE_URL"]) {
            return value
        }
        if let value = normalized(env["CHATGPT_BASE_URL"]) {
            return value
        }
        return nil
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
