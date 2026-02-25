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

        let primarySTTProvider = OpenAISTTProvider {
            try await openAIKeyResolver.apiKey()
        }

        let whisperProvider = WhisperSTTProvider()
        let parakeetProvider = ParakeetSTTProvider()
        let moonshineProvider = MoonshineSTTProvider()

        let openAIRefineProvider = OpenAIRefineProvider {
            try await openAIKeyResolver.apiKey()
        }

        let codexRefineProvider = CodexOAuthRefineProvider(keychain: keychain, oauthManager: codexOAuthManager)
        let pipelineExecutor = PipelineExecutor(refineProvider: codexRefineProvider)

        let orchestrator = TranscriptionOrchestrator(
            primary: primarySTTProvider,
            localFallback: whisperProvider,
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
        case whisperProvider.id:
            return whisperProvider
        case parakeetProvider.id:
            return parakeetProvider
        case moonshineProvider.id:
            return moonshineProvider
        default:
            return primarySTTProvider
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
    private var cachedKey: String?

    init(keychain: KeychainStore) {
        self.keychain = keychain
    }

    func apiKey() throws -> String {
        if let cachedKey, !cachedKey.isEmpty {
            return cachedKey
        }

        guard let key = try keychain.get("openai_api_key"), !key.isEmpty else {
            throw SayItError.authentication("OpenAI API key is missing. Save it to keychain with key openai_api_key")
        }

        cachedKey = key
        return key
    }

    func invalidate() {
        cachedKey = nil
    }
}
