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
    private static let runLlamaCppE2EEnvKey = "RUN_LLAMA_CPP_E2E_TESTS"
    private static let llamaCppBaseURLEnvKey = "LLAMA_CPP_BASE_URL"
    private static let llamaCppTestModelEnvKey = "LLAMA_CPP_TEST_MODEL"

    @MainActor
    func testAppVersion_displayNameIncludesBuildNumber() {
        let version = AppVersion(marketingVersion: "1.6.0", buildNumber: "9")

        XCTAssertEqual(version.displayName, "1.6.0 (9)")
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

    func testMixedChineseEnglishMode_selectsWhisper() {
        self.withRestoredDefaults(keys: [
            self.selectedSpeechLanguageModeKey,
            self.selectedSpeechModelKey,
        ]) {
            let settings = SettingsStore.shared
            settings.speechLanguageMode = .auto
            settings.selectedSpeechModel = .appleSpeech

            settings.speechLanguageMode = .chineseEnglishMixed

            XCTAssertEqual(settings.selectedSpeechModel, .whisperMedium)
        }
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

        // Arrange
        SettingsStore.shared.selectedSpeechModel = .whisperMedium
        AnalyticsService.shared.setEnabled(false)

        let modelDirectory = Self.modelDirectoryForRun()
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        let provider = WhisperProvider(modelDirectory: modelDirectory)

        // Act
        try await provider.prepare()
        let samples = try AudioFixtureLoader.load16kMonoFloatSamples(named: "dictation_fixture", ext: "wav")
        let result = try await provider.transcribe(samples)

        // Assert
        let raw = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(raw.isEmpty, "Expected non-empty transcription text.")

        let normalized = Self.normalize(raw)
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

        XCTAssertTrue(response.content.contains("review"), "Expected English word 'review' to be preserved. Got: \(response.content)")
        XCTAssertTrue(response.content.contains("pull request"), "Expected English phrase 'pull request' to be preserved. Got: \(response.content)")
        XCTAssertTrue(response.content.contains("deploy"), "Expected English word 'deploy' to be preserved. Got: \(response.content)")
        XCTAssertTrue(response.content.contains("staging"), "Expected English word 'staging' to be preserved. Got: \(response.content)")
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
}
