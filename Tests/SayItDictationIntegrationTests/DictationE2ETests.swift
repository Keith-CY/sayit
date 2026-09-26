import Foundation
import XCTest

@testable import SayIt

final class DictationE2ETests: XCTestCase {
    private let enableTranscriptionSoundsKey = "EnableTranscriptionSounds"
    private let transcriptionStartSoundKey = "TranscriptionStartSound"
    private let selectedProviderIDKey = "SelectedProviderID"
    private let selectedModelByProviderKey = "SelectedModelByProvider"
    private let providerBaseURLOverridesKey = "ProviderBaseURLOverrides"
    private let savedProvidersKey = "SavedProviders"
    private let enableAIProcessingKey = "EnableAIProcessing"
    private let selectedSpeechLanguageModeKey = "SelectedSpeechLanguageMode"
    private let selectedSpeechModelKey = "SelectedSpeechModel"
    private static let runWhisperE2EEnvKey = "RUN_WHISPER_E2E_TESTS"
    private static let whisperE2EAudioPathEnvKey = "WHISPER_E2E_AUDIO_PATH"
    private static let whisperE2EModelDirectoryEnvKey = "WHISPER_E2E_MODEL_DIRECTORY"
    private static let runAppleSpeechE2EEnvKey = "RUN_APPLE_SPEECH_E2E_TESTS"
    private static let appleSpeechE2EAudioPathEnvKey = "APPLE_SPEECH_E2E_AUDIO_PATH"
    private static let runLlamaCppE2EEnvKey = "RUN_LLAMA_CPP_E2E_TESTS"
    private static let llamaCppBaseURLEnvKey = "LLAMA_CPP_BASE_URL"
    private static let llamaCppTestModelEnvKey = "LLAMA_CPP_TEST_MODEL"

    @MainActor
    func testAppVersion_displayNameIncludesBuildNumber() {
        let version = AppVersion(marketingVersion: "1.6.1", buildNumber: "10")

        XCTAssertEqual(version.displayName, "1.6.1 (10)")
        XCTAssertEqual(
            AppVersion(marketingVersion: "Development", buildNumber: "").displayName,
            "Development"
        )
    }

    @MainActor
    func testUpdateConfigurationUsesStableSignedGitHubReleaseFeed() {
        let feedURL = URL(string: UpdateConfiguration.feedURLString)

        XCTAssertEqual(feedURL?.scheme, "https")
        XCTAssertEqual(feedURL?.host, "github.com")
        XCTAssertEqual(feedURL?.path, "/Keith-CY/sayit/releases/latest/download/appcast.xml")
        XCTAssertNil(feedURL?.query)
        XCTAssertNil(feedURL?.fragment)

        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            UpdateConfiguration.feedURLString
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            "okwvFkt/6hyeTGXaFgUIqODpG2pJo6HwkxD47p8fQRs="
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "SURequireSignedFeed") as? Bool,
            true
        )
    }

    func testModelRepository_includesCompatibleProviderMetadata() {
        let repository = ModelRepository.shared

        XCTAssertTrue(ModelRepository.builtInProviderIDs.contains("compatible"))
        XCTAssertEqual(repository.displayName(for: "compatible"), "OpenAI-Compatible")
        XCTAssertEqual(repository.defaultBaseURL(for: "compatible"), "")
        XCTAssertEqual(repository.defaultModels(for: "compatible"), [])

        XCTAssertTrue(ModelRepository.builtInProviderIDs.contains("llamacpp"))
        XCTAssertEqual(repository.displayName(for: "llamacpp"), "llama.cpp")
        XCTAssertEqual(repository.defaultBaseURL(for: "llamacpp"), "http://127.0.0.1:8080/v1")
        XCTAssertEqual(repository.defaultModels(for: "llamacpp"), [])

        let list = repository.builtInProvidersList(includeAppleIntelligence: false)
        XCTAssertTrue(list.contains(where: { $0.id == "compatible" && $0.name == "OpenAI-Compatible" }))
        XCTAssertTrue(list.contains(where: { $0.id == "llamacpp" && $0.name == "llama.cpp" }))
    }

    func testSettingsStore_baseURLOverride_forBuiltInCompatible() {
        self.withRestoredDefaults(keys: [self.providerBaseURLOverridesKey]) {
            let settings = SettingsStore.shared

            settings.clearBaseURLOverride(for: "compatible")
            XCTAssertEqual(settings.baseURL(for: "compatible"), "")

            settings.setBaseURLOverride("http://localhost:11434/v1", for: "compatible")
            XCTAssertEqual(settings.baseURL(for: "compatible"), "http://localhost:11434/v1")

            settings.clearBaseURLOverride(for: "compatible")
            XCTAssertEqual(settings.baseURL(for: "compatible"), "")
        }
    }

    func testSettingsStore_baseURLOverride_forLlamaCpp() {
        self.withRestoredDefaults(keys: [self.providerBaseURLOverridesKey]) {
            let settings = SettingsStore.shared

            settings.clearBaseURLOverride(for: "llamacpp")
            XCTAssertEqual(settings.baseURL(for: "llamacpp"), "http://127.0.0.1:8080/v1")

            settings.setBaseURLOverride("http://127.0.0.1:18080/v1", for: "llamacpp")
            XCTAssertEqual(settings.baseURL(for: "llamacpp"), "http://127.0.0.1:18080/v1")

            settings.clearBaseURLOverride(for: "llamacpp")
        }
    }

    func testSettingsStore_baseURLResolution_prefersSavedCustomProvider() {
        self.withRestoredDefaults(keys: [self.savedProvidersKey]) {
            let settings = SettingsStore.shared
            let provider = SettingsStore.SavedProvider(id: "custom-provider", name: "Custom Provider", baseURL: "http://127.0.0.1:9999/v1", models: [])
            settings.savedProviders = [provider]

            XCTAssertEqual(settings.baseURL(for: "custom-provider"), "http://127.0.0.1:9999/v1")
        }
    }

    func testSettingsStore_isAIConfigured_requiresNonEmptyBaseURL() {
        self.withRestoredDefaults(keys: [self.selectedProviderIDKey, self.selectedModelByProviderKey, self.providerBaseURLOverridesKey]) {
            let settings = SettingsStore.shared

            settings.selectedProviderID = "compatible"
            settings.selectedModelByProvider = ["compatible": "llama3.2"]
            settings.clearBaseURLOverride(for: "compatible")
            XCTAssertFalse(settings.isAIConfigured)

            settings.setBaseURLOverride("http://localhost:11434/v1", for: "compatible")
            XCTAssertTrue(settings.isAIConfigured)
        }
    }

    func testDictationGate_requiresSelectedLocalModel() {
        self.withRestoredDefaults(keys: [
            self.enableAIProcessingKey,
            self.selectedProviderIDKey,
            self.selectedModelByProviderKey,
            self.providerBaseURLOverridesKey,
        ]) {
            let settings = SettingsStore.shared
            settings.enableAIProcessing = true
            settings.selectedProviderID = "compatible"
            settings.setBaseURLOverride("http://localhost:11434/v1", for: "compatible")
            settings.selectedModelByProvider = [:]

            XCTAssertFalse(DictationAIPostProcessingGate.isConfigured())

            settings.selectedModelByProvider = ["compatible": "qwen2.5:3b"]
            XCTAssertTrue(DictationAIPostProcessingGate.isConfigured())
        }
    }

    func testMixedChineseEnglishMode_selectsBestLocalMixedLanguageEngine() {
        self.withRestoredDefaults(keys: [
            self.selectedSpeechLanguageModeKey,
            self.selectedSpeechModelKey,
        ]) {
            let settings = SettingsStore.shared
            settings.speechLanguageMode = .auto
            settings.selectedSpeechModel = .appleSpeech

            settings.speechLanguageMode = .chineseEnglishMixed

            if #available(macOS 26.0, *) {
                XCTAssertEqual(settings.selectedSpeechModel, .appleSpeechAnalyzer)
            } else {
                XCTAssertEqual(settings.selectedSpeechModel, .whisperSmall)
            }
        }
    }

    func testMixedChineseEnglishModePrioritizesSupportedChineseLocale() {
        XCTAssertEqual(
            SettingsStore.SpeechLanguageMode.chineseEnglishMixed.localeCandidates,
            ["zh-CN", "zh-Hans-CN", "zh-Hans", "zh", "en-US", "en"]
        )
        XCTAssertEqual(
            SettingsStore.SpeechLanguageMode.chineseSimplified.localeCandidates.first,
            "zh-CN"
        )
        XCTAssertEqual(
            SettingsStore.SpeechLanguageMode.chineseTraditional.localeCandidates.prefix(2),
            ["zh-TW", "zh-HK"]
        )
    }

    func testMixedChineseEnglishMode_preservesLargerWhisperSelection() {
        self.withRestoredDefaults(keys: [
            self.selectedSpeechLanguageModeKey,
            self.selectedSpeechModelKey,
        ]) {
            let settings = SettingsStore.shared
            settings.speechLanguageMode = .auto
            settings.selectedSpeechModel = .whisperLarge

            settings.speechLanguageMode = .chineseEnglishMixed

            XCTAssertEqual(settings.selectedSpeechModel, .whisperLarge)
        }
    }

    @MainActor
    func testMixedChineseEnglishMode_preservesQwenAndRoutesToMLX() throws {
        guard CPUArchitecture.isAppleSilicon else { throw XCTSkip("Qwen requires Apple Silicon.") }
        self.withRestoredDefaults(keys: [self.selectedSpeechLanguageModeKey, self.selectedSpeechModelKey]) {
            let settings = SettingsStore.shared
            settings.speechLanguageMode = .chineseEnglishMixed
            settings.selectedSpeechModel = .qwen3Asr
            XCTAssertEqual(settings.selectedSpeechModel, .qwen3Asr)
            XCTAssertTrue(SettingsStore.SpeechModel.availableModels.contains(.qwen3Asr))
            XCTAssertTrue(ASRService().fileTranscriptionProvider is QwenASRProvider)

            settings.speechLanguageMode = .english
            XCTAssertEqual(settings.selectedSpeechModel, .qwen3Asr)
            settings.speechLanguageMode = .auto
            XCTAssertEqual(settings.selectedSpeechModel, .qwen3Asr)

            settings.selectedSpeechModel = .whisperMedium
            XCTAssertEqual(settings.selectedSpeechModel, .whisperMedium)
            XCTAssertTrue(ASRService().fileTranscriptionProvider is WhisperProvider)
        }
    }

    func testQwenInstallationRequiresCompletePinnedFilesAndDeletesOnlyItsDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = QwenModelStore(directory: root.appendingPathComponent("qwen"))
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let neighbor = root.appendingPathComponent("another-model")
        try Data("keep".utf8).write(to: neighbor)
        XCTAssertFalse(store.isInstalled)

        // Sparse files let us validate completeness without allocating/downloading model weights.
        for file in QwenModelStore.files {
            let url = store.directory.appendingPathComponent(file.name)
            XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: UInt64(file.size))
            try handle.close()
        }
        XCTAssertFalse(store.isInstalled, "Files without a completed installation receipt must remain unavailable.")
        let receipt = store.directory.appendingPathComponent("sayit-installation.json")
        for revision in ["outdated", QwenModelStore.revision] {
            try JSONSerialization.data(withJSONObject: [
                "repository": QwenModelStore.repository,
                "revision": revision,
            ]).write(to: receipt)
            XCTAssertEqual(store.isInstalled, revision == QwenModelStore.revision)
        }
        try FileManager.default.removeItem(at: store.directory.appendingPathComponent("tokenizer_config.json"))
        XCTAssertFalse(store.isInstalled, "Missing tokenizer files must disable activation.")
        try store.remove()
        XCTAssertFalse(store.isInstalled)
        XCTAssertEqual(try String(contentsOf: neighbor), "keep")
    }

    func testAppBundleContainsQwenMetalLibrary() throws {
        guard CPUArchitecture.isAppleSilicon else { throw XCTSkip("Qwen requires Apple Silicon.") }
        let resources = try XCTUnwrap(Bundle.main.resourceURL)
        let library = resources.appendingPathComponent("mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib")
        let attributes = try FileManager.default.attributesOfItem(atPath: library.path)
        XCTAssertGreaterThan((attributes[.size] as? NSNumber)?.intValue ?? 0, 0)
    }

    @MainActor
    func testDictationEndToEnd_qwenMLX_transcribesAndReloadsOffline() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["RUN_QWEN_E2E_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_QWEN_E2E_TESTS=1 to run the real Qwen model.")
        }
        guard CPUArchitecture.isAppleSilicon else { throw XCTSkip("Qwen requires Apple Silicon.") }
        let directory = environment["QWEN_E2E_MODEL_DIRECTORY"].map { URL(fileURLWithPath: $0) }
            ?? QwenModelStore.defaultDirectory
        try await self.withRestoredDefaultsAsync(keys: [self.selectedSpeechLanguageModeKey, self.selectedSpeechModelKey]) {
            let settings = SettingsStore.shared
            settings.speechLanguageMode = .auto
            settings.selectedSpeechModel = .whisperMedium
            let provider = QwenASRProvider(modelDirectory: directory)
            try await provider.download(progressHandler: nil)
            XCTAssertEqual(settings.selectedSpeechModel, .whisperMedium, "Downloading must not switch the active model.")
            XCTAssertFalse(provider.isReady, "Download-only must not load GPU weights.")
            XCTAssertTrue(provider.modelsExistOnDisk())

            settings.speechLanguageMode = .chineseEnglishMixed
            settings.selectedSpeechModel = .qwen3Asr
            // Reject fallback downloads; the runtime itself loads from the local directory.
            let configuration = URLSessionConfiguration.ephemeral
            configuration.connectionProxyDictionary = [
                "HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 9,
                "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": 9,
            ]
            let offlineProvider = QwenASRProvider(modelDirectory: directory, session: URLSession(configuration: configuration))
            try await offlineProvider.prepare(progressHandler: nil)
            XCTAssertTrue(offlineProvider.isReady)

            let audioPath = environment["QWEN_E2E_AUDIO_PATH"]
            let samples = try audioPath.map { try AudioFixtureLoader.load16kMonoFloatSamples(from: URL(fileURLWithPath: $0)) }
                ?? AudioFixtureLoader.load16kMonoFloatSamples(named: "dictation_fixture", ext: "wav")
            let started = Date()
            let result = try await offlineProvider.transcribeFinal(samples)
            print("QWEN_E2E_TRANSCRIPT=\(result.text)")
            print("QWEN_E2E_SECONDS=\(Date().timeIntervalSince(started)) AUDIO_SECONDS=\(Double(samples.count) / 16000)")
            let normalized = Self.normalize(result.text)
            XCTAssertFalse(normalized.isEmpty)
            if audioPath != nil {
                XCTAssertTrue(result.text.unicodeScalars.contains { (0x4E00 ... 0x9FFF).contains(Int($0.value)) })
                for term in ["review", "pull", "request", "deploy", "staging"] {
                    XCTAssertTrue(normalized.contains(term), "Missing English term '\(term)' in: \(result.text)")
                }
            } else {
                XCTAssertTrue(normalized.contains("hello"))
            }
            let silent = try await offlineProvider.transcribeFinal([Float](repeating: 0, count: 16000))
            XCTAssertEqual(silent.text, "")
        }
    }

    func testStartupPolicyLoadsCachedModelOnlyWhenNeeded() {
        XCTAssertTrue(ASRStartupPolicy.shouldLoadCachedModel(isReady: false, modelsExistOnDisk: true))
        XCTAssertFalse(ASRStartupPolicy.shouldLoadCachedModel(isReady: true, modelsExistOnDisk: true))
        XCTAssertFalse(ASRStartupPolicy.shouldLoadCachedModel(isReady: false, modelsExistOnDisk: false))
        XCTAssertTrue(
            ASRStartupPolicy.isModelPreloadDisabled(
                environment: [ASRStartupPolicy.disablePreloadEnvironmentKey: "1"]
            )
        )
        XCTAssertFalse(ASRStartupPolicy.isModelPreloadDisabled(environment: [:]))
    }

    func testWhisperCoreMLSupportDerivesCompanionNames() {
        XCTAssertEqual(
            WhisperCoreMLSupport.compiledModelDirectoryName(for: "ggml-medium.bin"),
            "ggml-medium-encoder.mlmodelc"
        )
        XCTAssertEqual(
            WhisperCoreMLSupport.archiveName(for: "ggml-large-v3.bin"),
            "ggml-large-v3-encoder.mlmodelc.zip"
        )
        XCTAssertEqual(
            WhisperCoreMLSupport.compiledModelDirectoryName(for: "ggml-small-q5_1.bin"),
            "ggml-small-encoder.mlmodelc"
        )
        XCTAssertNil(WhisperCoreMLSupport.archiveName(for: "unexpected-model"))
    }

    func testWhisperCoreMLSupportOnlyInstallsMissingAppleSiliconCompanion() {
        XCTAssertTrue(
            WhisperCoreMLSupport.shouldInstallCompanion(
                isAppleSilicon: true,
                compiledModelExists: false
            )
        )
        XCTAssertFalse(
            WhisperCoreMLSupport.shouldInstallCompanion(
                isAppleSilicon: true,
                compiledModelExists: true
            )
        )
        XCTAssertFalse(
            WhisperCoreMLSupport.shouldInstallCompanion(
                isAppleSilicon: false,
                compiledModelExists: false
            )
        )
    }

    @MainActor
    func testRecordingControlPreparesAndStartsWhenModelIsMissing() {
        XCTAssertEqual(
            RecordingControlPolicy.action(
                isRunning: false,
                isReady: false,
                isPreparingModel: false
            ),
            .prepareAndStart
        )
        XCTAssertEqual(
            RecordingControlPolicy.action(
                isRunning: false,
                isReady: false,
                isPreparingModel: true
            ),
            .waitForModel
        )
        XCTAssertEqual(
            RecordingControlPolicy.action(
                isRunning: false,
                isReady: true,
                isPreparingModel: false
            ),
            .start
        )
        XCTAssertEqual(
            RecordingControlPolicy.action(
                isRunning: true,
                isReady: true,
                isPreparingModel: false
            ),
            .stop
        )
    }

    @MainActor
    func testRecordingControlShowsRequiredMicrophoneActionBeforeStarting() {
        XCTAssertEqual(
            RecordingControlPolicy.action(
                isRunning: false,
                isReady: true,
                isPreparingModel: false,
                micStatus: .notDetermined
            ),
            .requestMicrophoneAccess
        )
        XCTAssertEqual(
            RecordingControlPolicy.action(
                isRunning: false,
                isReady: true,
                isPreparingModel: false,
                micStatus: .denied
            ),
            .openMicrophoneSettings
        )
        XCTAssertEqual(
            RecordingControlPolicy.action(
                isRunning: false,
                isReady: true,
                isPreparingModel: false,
                micStatus: .restricted
            ),
            .showMicrophoneRestriction
        )
        XCTAssertEqual(
            RecordingControlPolicy.action(
                isRunning: true,
                isReady: true,
                isPreparingModel: false,
                micStatus: .denied
            ),
            .stop
        )
    }

    @MainActor
    func testRecordingControlShowsStartingStateImmediatelyWhileAudioEngineStarts() {
        XCTAssertEqual(
            RecordingControlPolicy.action(
                isRunning: false,
                isStarting: true,
                isReady: true,
                isPreparingModel: false,
                micStatus: .authorized
            ),
            .starting
        )
    }

    func testAccessibilityPromptCooldownDoesNotSuppressNewBuild() {
        let now: TimeInterval = 10_000
        let lastPromptAt: TimeInterval = 9_900

        XCTAssertFalse(
            AccessibilityPromptPolicy.shouldPrompt(
                isTrusted: false,
                hasPromptedThisSession: false,
                now: now,
                lastPromptAt: lastPromptAt,
                lastPromptBuild: "9",
                currentBuild: "9",
                cooldown: 86_400
            )
        )
        XCTAssertTrue(
            AccessibilityPromptPolicy.shouldPrompt(
                isTrusted: false,
                hasPromptedThisSession: false,
                now: now,
                lastPromptAt: lastPromptAt,
                lastPromptBuild: "9",
                currentBuild: "10",
                cooldown: 86_400
            )
        )
    }

    @MainActor
    func testAccessibilityPermissionActionPromptsAndOpensSystemSettings() {
        var didPrompt = false
        var openedURL: URL?

        AccessibilityPermissionAction.perform(
            prompt: { didPrompt = true },
            openSettings: { openedURL = $0 }
        )

        XCTAssertTrue(didPrompt)
        XCTAssertEqual(
            openedURL?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    func testDefaultDictationPrompt_preservesMixedLanguages() {
        let prompt = SettingsStore.baseDictationPromptText().lowercased()

        XCTAssertTrue(prompt.contains("never translate"))
        XCTAssertTrue(prompt.contains("copy every english word"))
        XCTAssertTrue(prompt.contains("language lock"))
    }

    func testChatCompletionsEndpoint_normalizesTrailingSlash() {
        let repository = ModelRepository.shared

        XCTAssertEqual(
            repository.chatCompletionsEndpoint(for: "http://localhost:11434/v1/"),
            "http://localhost:11434/v1/chat/completions"
        )
        XCTAssertEqual(
            repository.chatCompletionsEndpoint(for: "http://localhost:11434/api/chat"),
            "http://localhost:11434/api/chat"
        )
    }

    func testLocalEndpoint_supportsIPv6Loopback() {
        XCTAssertTrue(ModelRepository.shared.isLocalEndpoint("http://[::1]:11434/v1"))
    }

    @MainActor
    func testLLMClient_zeroRetriesStillMakesOneAttempt() async {
        var config = LLMClient.Config(
            messages: [["role": "user", "content": "hello"]],
            model: "local-test-model",
            baseURL: "file:///tmp/sayit-unsupported-endpoint",
            apiKey: "",
            streaming: false,
            temperature: 0,
            providerID: "compatible"
        )
        config.maxRetries = 0
        config.timeoutSeconds = 1

        do {
            _ = try await LLMClient.shared.call(config)
            XCTFail("Expected the unsupported local test URL to fail.")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testTranscriptionStartSound_noneOptionHasNoFile() {
        XCTAssertEqual(SettingsStore.TranscriptionStartSound.none.displayName, "None")
        XCTAssertNil(SettingsStore.TranscriptionStartSound.none.soundFileName)
    }

    func testTranscriptionStartSound_legacyDisabledToggleMigratesToNone() {
        self.withRestoredDefaults(keys: [self.enableTranscriptionSoundsKey, self.transcriptionStartSoundKey]) {
            let defaults = UserDefaults.standard
            defaults.set(false, forKey: self.enableTranscriptionSoundsKey)
            defaults.set(SettingsStore.TranscriptionStartSound.startupSfx1.rawValue, forKey: self.transcriptionStartSoundKey)

            let value = SettingsStore.shared.transcriptionStartSound

            XCTAssertEqual(value, .none)
            XCTAssertNil(defaults.object(forKey: self.enableTranscriptionSoundsKey))
            XCTAssertEqual(defaults.string(forKey: self.transcriptionStartSoundKey), SettingsStore.TranscriptionStartSound.none.rawValue)
        }
    }

    func testTranscriptionStartSound_legacyEnabledToggleKeepsSelectedSound() {
        self.withRestoredDefaults(keys: [self.enableTranscriptionSoundsKey, self.transcriptionStartSoundKey]) {
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: self.enableTranscriptionSoundsKey)
            defaults.set(SettingsStore.TranscriptionStartSound.startupSfx2.rawValue, forKey: self.transcriptionStartSoundKey)

            let value = SettingsStore.shared.transcriptionStartSound

            XCTAssertEqual(value, .startupSfx2)
            XCTAssertNil(defaults.object(forKey: self.enableTranscriptionSoundsKey))
            XCTAssertEqual(defaults.string(forKey: self.transcriptionStartSoundKey), SettingsStore.TranscriptionStartSound.startupSfx2.rawValue)
        }
    }

    @MainActor
    func testDictationEndToEnd_whisperMedium_transcribesFixture() async throws {
        guard ProcessInfo.processInfo.environment[Self.runWhisperE2EEnvKey] == "1" else {
            throw XCTSkip("Skipping Whisper E2E test. Set \(Self.runWhisperE2EEnvKey)=1 to enable.")
        }

        try await self.assertWhisperTranscribesFixture(model: .whisperMedium)
    }

    @MainActor
    func testDictationEndToEnd_whisperSmall_transcribesFixture() async throws {
        guard ProcessInfo.processInfo.environment[Self.runWhisperE2EEnvKey] == "1" else {
            throw XCTSkip("Skipping Whisper E2E test. Set \(Self.runWhisperE2EEnvKey)=1 to enable.")
        }

        try await self.assertWhisperTranscribesFixture(model: .whisperSmall)
    }

    @MainActor
    func testDictationEndToEnd_appleSpeechAnalyzer_transcribesFixture() async throws {
        guard ProcessInfo.processInfo.environment[Self.runAppleSpeechE2EEnvKey] == "1" else {
            throw XCTSkip("Skipping Apple Speech E2E test. Set \(Self.runAppleSpeechE2EEnvKey)=1 to enable.")
        }
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("Apple Speech Analyzer requires macOS 26 or newer.")
        }

        try await self.withRestoredDefaultsAsync(keys: [
            self.selectedSpeechLanguageModeKey,
            self.selectedSpeechModelKey,
        ]) {
            let settings = SettingsStore.shared
            settings.speechLanguageMode = .chineseEnglishMixed
            settings.selectedSpeechModel = .appleSpeechAnalyzer
            let provider = AppleSpeechAnalyzerProvider()

            try await provider.prepare(progressHandler: nil)
            let externalAudioPath = ProcessInfo.processInfo.environment[
                Self.appleSpeechE2EAudioPathEnvKey
            ]
            let samples: [Float]
            if let externalAudioPath {
                samples = try AudioFixtureLoader.load16kMonoFloatSamples(
                    from: URL(fileURLWithPath: externalAudioPath)
                )
            } else {
                samples = try AudioFixtureLoader.load16kMonoFloatSamples(
                    named: "dictation_fixture",
                    ext: "wav"
                )
            }
            let result = try await provider.transcribe(samples)
            let normalized = Self.normalize(result.text)

            if externalAudioPath != nil {
                XCTAssertTrue(
                    result.text.unicodeScalars.contains(where: {
                        (0x4E00 ... 0x9FFF).contains(Int($0.value))
                    }),
                    "Expected mixed-language engine to retain Chinese. Got: \(result.text)"
                )
                XCTAssertTrue(
                    ["review", "pull", "request", "deploy", "staging"].contains(where: normalized.contains),
                    "Expected mixed-language engine to retain English words. Got: \(result.text)"
                )
            } else {
                XCTAssertTrue(
                    normalized.contains("hello"),
                    "Expected mixed-language engine to retain English. Got: \(result.text)"
                )
            }
            XCTAssertFalse(normalized.isEmpty, "Expected non-empty Apple Speech transcription.")
        }
    }

    @MainActor
    private func assertWhisperTranscribesFixture(model: SettingsStore.SpeechModel) async throws {
        let defaults = UserDefaults.standard
        let previousSpeechModel = defaults.object(forKey: self.selectedSpeechModelKey)
        defer {
            if let previousSpeechModel {
                defaults.set(previousSpeechModel, forKey: self.selectedSpeechModelKey)
            } else {
                defaults.removeObject(forKey: self.selectedSpeechModelKey)
            }
        }

        SettingsStore.shared.selectedSpeechModel = model
        AnalyticsService.shared.setEnabled(false)

        let environment = ProcessInfo.processInfo.environment
        let modelDirectory = environment[Self.whisperE2EModelDirectoryEnvKey]
            .flatMap { path in
                let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : URL(fileURLWithPath: trimmed, isDirectory: true)
            }
            ?? Self.modelDirectoryForRun()
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        let provider = WhisperProvider(modelDirectory: modelDirectory)

        // Act
        try await provider.prepare()
        let externalAudioPath = environment[Self.whisperE2EAudioPathEnvKey]
        let samples: [Float]
        if let externalAudioPath {
            samples = try AudioFixtureLoader.load16kMonoFloatSamples(
                from: URL(fileURLWithPath: externalAudioPath)
            )
        } else {
            samples = try AudioFixtureLoader.load16kMonoFloatSamples(
                named: "dictation_fixture",
                ext: "wav"
            )
        }
        let result = try await provider.transcribe(samples)

        // Assert
        let raw = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(raw.isEmpty, "Expected non-empty transcription text.")

        let normalized = Self.normalize(raw)
        if externalAudioPath != nil {
            print("WHISPER_E2E_TRANSCRIPT=\(raw)")
            XCTAssertTrue(
                raw.unicodeScalars.contains(where: {
                    (0x4E00 ... 0x9FFF).contains(Int($0.value))
                }),
                "Expected Whisper to retain Chinese. Got: \(raw)"
            )
            for term in ["review", "staging", "local", "model"] {
                XCTAssertTrue(
                    normalized.contains(term),
                    "Expected Whisper to retain English term '\(term)'. Got: \(raw)"
                )
            }
            return
        }

        XCTAssertTrue(normalized.contains("hello"), "Expected transcription to contain 'hello'. Got: \(raw)")
        XCTAssertTrue(normalized.contains("fluid"), "Expected transcription to contain 'fluid'. Got: \(raw)")
        XCTAssertTrue(
            normalized.contains("voice") || normalized.contains("fluidvoice") || normalized.contains("boys"),
            "Expected transcription to contain 'voice' (or a close variant like 'boys'). Got: \(raw)"
        )
    }

    @MainActor
    func testLocalEnhancementEndToEnd_llamaCpp_preservesMixedLanguages() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment[Self.runLlamaCppE2EEnvKey] == "1" else {
            throw XCTSkip("Skipping llama.cpp E2E test. Set \(Self.runLlamaCppE2EEnvKey)=1 to enable.")
        }

        let baseURL = environment[Self.llamaCppBaseURLEnvKey]
            ?? ModelRepository.shared.defaultBaseURL(for: "llamacpp")
        let models = try await ModelRepository.shared.fetchModels(
            for: "llamacpp",
            baseURL: baseURL,
            apiKey: nil
        )
        guard let model = environment[Self.llamaCppTestModelEnvKey]
            .flatMap({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 })
            ?? models.first
        else {
            XCTFail("llama.cpp returned no models from \(baseURL).")
            return
        }
        XCTAssertTrue(models.contains(model), "Expected llama.cpp model list to contain \(model).")

        var config = LLMClient.Config(
            messages: [
                ["role": "system", "content": SettingsStore.baseDictationPromptText()],
                ["role": "user", "content": "呃今天我想 review 一下这个 pull request 然后 deploy 到 staging 环境"],
            ],
            model: model,
            baseURL: baseURL,
            apiKey: "",
            streaming: false,
            temperature: 0,
            providerID: "llamacpp"
        )
        config.maxRetries = 0
        config.timeoutSeconds = 120

        let response = try await LLMClient.shared.call(config)

        XCTAssertTrue(
            response.content.unicodeScalars.contains(where: {
                (0x4E00 ... 0x9FFF).contains(Int($0.value))
            }),
            "Expected surrounding Chinese to be preserved. Got: \(response.content)"
        )
        XCTAssertFalse(response.content.contains("呃"), "Expected Chinese filler word '呃' to be removed. Got: \(response.content)")
        XCTAssertTrue(response.content.contains("review"), "Expected English word 'review' to be preserved. Got: \(response.content)")
        XCTAssertTrue(response.content.contains("pull request"), "Expected English phrase 'pull request' to be preserved. Got: \(response.content)")
        XCTAssertTrue(response.content.contains("deploy"), "Expected English word 'deploy' to be preserved. Got: \(response.content)")
        XCTAssertTrue(response.content.contains("staging"), "Expected English word 'staging' to be preserved. Got: \(response.content)")

        var repairConfig = LLMClient.Config(
            messages: [
                ["role": "system", "content": SettingsStore.baseDictationPromptText()],
                [
                    "role": "user",
                    "content": "今天我们 review 这个 plorequest，然后 Daploy 到 staging 环境，明天继续测试 ATI 和 local model。",
                ],
            ],
            model: model,
            baseURL: baseURL,
            apiKey: "",
            streaming: false,
            temperature: 0,
            providerID: "llamacpp"
        )
        repairConfig.maxRetries = 0
        repairConfig.timeoutSeconds = 120
        let repairedResponse = try await LLMClient.shared.call(repairConfig)
        let repaired = repairedResponse.content.lowercased()

        XCTAssertTrue(
            repairedResponse.content.unicodeScalars.contains(where: {
                (0x4E00 ... 0x9FFF).contains(Int($0.value))
            }),
            "Expected repaired output to retain Chinese. Got: \(repairedResponse.content)"
        )
        XCTAssertTrue(repaired.contains("review"), "Expected 'review' to remain intact. Got: \(repairedResponse.content)")
        XCTAssertTrue(repaired.contains("pull request"), "Expected obvious ASR error 'plorequest' to become 'pull request'. Got: \(repairedResponse.content)")
        XCTAssertTrue(repaired.contains("deploy"), "Expected obvious ASR error 'Daploy' to become 'deploy'. Got: \(repairedResponse.content)")
        XCTAssertTrue(repaired.contains("api"), "Expected obvious ASR error 'ATI' to become 'API'. Got: \(repairedResponse.content)")
        XCTAssertTrue(repaired.contains("local model"), "Expected 'local model' to remain intact. Got: \(repairedResponse.content)")
    }

    private static func modelDirectoryForRun() -> URL {
        // Use a stable path on CI so GitHub Actions cache can speed up runs.
        if ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" ||
            ProcessInfo.processInfo.environment["CI"] == "true"
        {
            guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                preconditionFailure("Could not find caches directory")
            }
            return caches.appendingPathComponent("WhisperModels")
        }

        // Local runs: isolate per test execution.
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SayItTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return base.appendingPathComponent("WhisperModels", isDirectory: true)
    }

    private static func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let noPunct = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.punctuationCharacters.contains(scalar) { return " " }
            return Character(scalar)
        }
        let collapsed = String(noPunct)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return collapsed
    }

    private func withRestoredDefaults(keys: [String], run: () -> Void) {
        let defaults = UserDefaults.standard
        var snapshot: [String: Any] = [:]
        for key in keys {
            if let value = defaults.object(forKey: key) {
                snapshot[key] = value
            }
        }

        defer {
            for key in keys {
                if let previous = snapshot[key] {
                    defaults.set(previous, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        run()
    }

    private func withRestoredDefaultsAsync(
        keys: [String],
        run: () async throws -> Void
    ) async rethrows {
        let defaults = UserDefaults.standard
        var snapshot: [String: Any] = [:]
        for key in keys {
            if let value = defaults.object(forKey: key) {
                snapshot[key] = value
            }
        }

        defer {
            for key in keys {
                if let previous = snapshot[key] {
                    defaults.set(previous, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        try await run()
    }
}
