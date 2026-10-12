import Combine
import SwiftUI

/// A problem on the Voice Engine page, shown inline next to the model it concerns.
struct VoiceEngineIssue: Identifiable, Equatable {
    enum Retry: Equatable {
        case download(SettingsStore.SpeechModel)
        case activate(SettingsStore.SpeechModel)
        case delete(SettingsStore.SpeechModel)
    }

    let id = UUID()
    let title: String
    let message: String
    let retry: Retry?
}

@MainActor
final class VoiceEngineSettingsViewModel: ObservableObject {
    let settings: SettingsStore
    private let appServices: AppServices

    var asr: ASRService { self.appServices.asr }

    @Published var modelSortOption: ModelSortOption = .provider
    @Published var providerFilter: SpeechProviderFilter = .all
    @Published var englishOnlyFilter: Bool = false
    @Published var installedOnlyFilter: Bool = false
    @Published var showSpeechFilters: Bool = false

    @Published var selectedSpeechProvider: SettingsStore.SpeechModel.Provider
    /// The model whose details are expanded in the list. Selecting a model never
    /// changes the engine in use; only "Use" does.
    @Published var previewSpeechModel: SettingsStore.SpeechModel
    @Published var showAdvancedSpeechInfo: Bool = false
    @Published var suppressSpeechProviderSync: Bool = false
    @Published var skipNextSpeechModelSync: Bool = false

    /// The model currently being downloaded (nil if no download in progress)
    @Published var downloadingModel: SettingsStore.SpeechModel?
    /// Download progress for the current model (0.0 to 1.0)
    @Published var downloadProgress: Double = 0.0
    /// True after the user cancelled, until the download task has actually stopped.
    @Published var isCancellingDownload = false
    /// The most recent failure, shown inline until dismissed or retried.
    @Published var issue: VoiceEngineIssue?

    @Published var removeFillerWordsEnabled: Bool

    private var downloadTask: Task<Void, Never>?

    init(settings: SettingsStore, appServices: AppServices) {
        self.settings = settings
        self.appServices = appServices
        self.previewSpeechModel = settings.selectedSpeechModel
        self.selectedSpeechProvider = settings.selectedSpeechModel.provider
        self.removeFillerWordsEnabled = settings.removeFillerWordsEnabled
    }

    func onAppear() {
        self.previewSpeechModel = self.settings.selectedSpeechModel
        self.selectedSpeechProvider = self.settings.selectedSpeechModel.provider
        self.removeFillerWordsEnabled = self.settings.removeFillerWordsEnabled

        Task {
            await self.asr.checkIfModelsExistAsync()
        }
    }

    func handleSelectedSpeechModelChange(_ newValue: SettingsStore.SpeechModel) {
        if self.skipNextSpeechModelSync {
            self.skipNextSpeechModelSync = false
            return
        }
        guard !self.suppressSpeechProviderSync else { return }
        self.previewSpeechModel = newValue
        self.setSelectedSpeechProvider(newValue.provider)
    }

    var filteredSpeechModels: [SettingsStore.SpeechModel] {
        var models = SettingsStore.SpeechModel.availableModels

        switch self.providerFilter {
        case .all:
            break
        case .nvidia:
            models = models.filter { $0.provider == .nvidia }
        case .apple:
            models = models.filter { $0.provider == .apple }
        case .openai:
            models = models.filter { $0.provider == .openai }
        case .qwen:
            models = models.filter { $0.provider == .qwen }
        }

        if self.englishOnlyFilter {
            models = models.filter { model in
                let label = model.languageSupport.lowercased()
                let title = model.humanReadableName.lowercased()
                return label.contains("english only") || title.contains("english")
            }
        }

        if self.installedOnlyFilter {
            models = models.filter { $0.isInstalled }
        }

        switch self.modelSortOption {
        case .provider:
            models.sort { $0.brandName.localizedCaseInsensitiveCompare($1.brandName) == .orderedAscending }
        case .accuracy:
            models.sort { $0.accuracyPercent > $1.accuracyPercent }
        case .speed:
            models.sort { $0.speedPercent > $1.speedPercent }
        }

        return models
    }

    /// Whether model actions should be blocked (recording or another download running).
    var isBusy: Bool {
        self.asr.isRunning || self.downloadingModel != nil
    }

    /// Loading state of the engine currently in use.
    var isActiveModelLoading: Bool {
        (self.asr.isLoadingModel || self.asr.isDownloadingModel) && !self.asr.isAsrReady
    }

    func activateSpeechModel(_ model: SettingsStore.SpeechModel) {
        guard !self.asr.isRunning else { return }
        self.issue = nil
        withMotion(Motion.state) {
            self.settings.selectedSpeechModel = model
            self.previewSpeechModel = model
            self.setSelectedSpeechProvider(model.provider)
        }
        self.asr.resetTranscriptionProvider()
        Task {
            do {
                try await self.asr.ensureAsrReady()
            } catch {
                DebugLogger.shared.error("Failed to prepare model after activation: \(error)", source: "VoiceEngineVM")
                self.issue = VoiceEngineIssue(
                    title: "\(model.uiName) couldn’t load",
                    message: error.localizedDescription,
                    retry: .activate(model)
                )
            }
        }
    }

    func downloadSpeechModel(_ model: SettingsStore.SpeechModel) {
        guard !self.asr.isRunning else { return }
        guard self.downloadingModel == nil else { return } // Prevent concurrent downloads
        self.issue = nil
        self.downloadingModel = model
        self.downloadProgress = 0.0
        self.isCancellingDownload = false

        self.downloadTask = Task {
            do {
                // Download the model WITHOUT changing the active selection.
                // Capture the model ID to guard against stale progress callbacks.
                let downloadingModelId = model.id
                try await self.asr.downloadModel(model, progressHandler: { [weak self] progress in
                    Task { @MainActor in
                        guard let self, self.downloadingModel?.id == downloadingModelId else { return }
                        self.downloadProgress = progress
                    }
                })

                DebugLogger.shared.info("Model download completed: \(model.displayName)", source: "VoiceEngineVM")

                if self.settings.selectedSpeechModel == model {
                    self.asr.resetTranscriptionProvider()
                    try await self.asr.ensureAsrReady()
                    DebugLogger.shared.info("Downloaded active model is ready", source: "VoiceEngineVM")
                }
            } catch is CancellationError {
                DebugLogger.shared.info("Model download cancelled: \(model.displayName)", source: "VoiceEngineVM")
            } catch {
                if self.isCancellingDownload || Task.isCancelled {
                    DebugLogger.shared.info("Model download stopped after cancel: \(model.displayName)", source: "VoiceEngineVM")
                } else {
                    DebugLogger.shared.error("Failed to download model \(model.displayName): \(error)", source: "VoiceEngineVM")
                    self.issue = VoiceEngineIssue(
                        title: "\(model.uiName) didn’t finish downloading",
                        message: error.localizedDescription,
                        retry: .download(model)
                    )
                }
            }

            self.downloadingModel = nil
            self.downloadProgress = 0.0
            self.isCancellingDownload = false
            self.downloadTask = nil
        }
    }

    /// Stops the current download. The row shows "Cancelling…" until the download
    /// task has actually stopped, so the UI never claims more than happened.
    func cancelDownload() {
        guard self.downloadingModel != nil, let task = self.downloadTask else { return }
        self.isCancellingDownload = true
        task.cancel()
    }

    func deleteSpeechModel(_ model: SettingsStore.SpeechModel) {
        guard !self.asr.isRunning else { return }
        self.issue = nil
        let previousActive = self.settings.selectedSpeechModel

        Task {
            let shouldRestore = previousActive != model
            if shouldRestore {
                self.suppressSpeechProviderSync = true
            }
            self.settings.selectedSpeechModel = model
            self.asr.resetTranscriptionProvider()

            let succeeded = await self.deleteModels()

            if shouldRestore {
                self.skipNextSpeechModelSync = true
                self.settings.selectedSpeechModel = previousActive
                self.asr.resetTranscriptionProvider()
                self.suppressSpeechProviderSync = false
            }
            self.previewSpeechModel = model

            if !succeeded {
                self.issue = VoiceEngineIssue(
                    title: "\(model.uiName) couldn’t be deleted",
                    message: self.lastDeleteError ?? "SayIt couldn’t remove the downloaded files.",
                    retry: .delete(model)
                )
            }
        }
    }

    func retry(_ issue: VoiceEngineIssue) {
        guard let retry = issue.retry else {
            self.issue = nil
            return
        }
        switch retry {
        case let .download(model):
            self.downloadSpeechModel(model)
        case let .activate(model):
            self.activateSpeechModel(model)
        case let .delete(model):
            self.deleteSpeechModel(model)
        }
    }

    func dismissIssue() {
        withMotion(Motion.exit) {
            self.issue = nil
        }
    }

    func isActiveSpeechModel(_ model: SettingsStore.SpeechModel) -> Bool {
        self.settings.selectedSpeechModel == model
    }

    var modelDescriptionText: String {
        let model = self.settings.selectedSpeechModel
        switch model {
        case .appleSpeech:
            return "Apple Speech (Legacy) uses on-device recognition. No download required, works on Intel and Apple silicon."
        case .appleSpeechAnalyzer:
            return "Apple Speech uses advanced on-device recognition with fast, accurate transcription. Requires macOS 26 or later."
        case .parakeetTDT:
            return "Parakeet TDT v3 uses Core ML and the Neural Engine for the fastest transcription (25 languages) on Apple silicon."
        case .qwen3Asr:
            return "Qwen3-ASR 1.7B runs locally on Apple silicon. Supports Chinese, English and mixed speech; transcribes when recording stops."
        default:
            return "Whisper models support 99 languages and work on any Mac."
        }
    }

    private var lastDeleteError: String?

    func downloadModels() async {
        do {
            try await self.asr.ensureAsrReady()
        } catch {
            DebugLogger.shared.error("Failed to download models: \(error)", source: "VoiceEngineVM")
            let model = self.settings.selectedSpeechModel
            self.issue = VoiceEngineIssue(
                title: "\(model.uiName) couldn’t load",
                message: error.localizedDescription,
                retry: .activate(model)
            )
        }
    }

    /// Clears the active provider's model cache. Returns whether it succeeded.
    @discardableResult
    func deleteModels() async -> Bool {
        do {
            try await self.asr.clearModelCache()
            self.lastDeleteError = nil
            return true
        } catch {
            DebugLogger.shared.error("Failed to delete models: \(error)", source: "VoiceEngineVM")
            self.lastDeleteError = error.localizedDescription
            return false
        }
    }

    func setSelectedSpeechProvider(_ provider: SettingsStore.SpeechModel.Provider) {
        self.selectedSpeechProvider = provider
    }
}
