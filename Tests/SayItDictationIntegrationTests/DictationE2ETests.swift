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
    func testTranscriptContent_treatsHesitationOnlyTranscriptsAsNoSpeech() {
        let noFillers: [String] = []
        for text in ["", "  ", "嗯。", "嗯嗯", "呃……", "Um.", "hmmm", "Uh, um.", "…"] {
            XCTAssertTrue(TranscriptContent.hasNoWords(text, fillers: noFillers), "\(text) should count as no speech")
        }
        for text in ["好的。", "OK.", "嗯，我们下午开会。", "Um, ship it.", "请帮我 review 这个 pull request"] {
            XCTAssertFalse(TranscriptContent.hasNoWords(text, fillers: noFillers), "\(text) has words")
        }
        XCTAssertTrue(TranscriptContent.hasNoWords("like, you know", fillers: ["like", "you", "know"]))
    }

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
            // prepare() already warmed up, so this is the per-recording cost of a resident model.
            let warmUpStarted = Date()
            await offlineProvider.warmUp()
            print("QWEN_E2E_WARMUP_SECONDS=\(Date().timeIntervalSince(warmUpStarted))")

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

    // MARK: - Live Captions

    @MainActor
    func testLiveCaptionTranscript_pauseStartsNewLineAndClosesPrevious() {
        var transcript = LiveCaptionTranscript()
        XCTAssertEqual(transcript.applyFinal("请帮我 review", start: 0, end: 1.2), [])
        XCTAssertEqual(transcript.applyFinal("这个 pull request。", start: 1.4, end: 2.6), [], "A short gap continues the line")
        XCTAssertEqual(transcript.lines.map(\.text), ["请帮我 review这个 pull request。"])

        let closed = transcript.applyFinal("Then deploy.", start: 3.6, end: 4.5)
        XCTAssertEqual(closed, [0], "A 1 s pause closes the first line")
        XCTAssertEqual(transcript.lines.map(\.state), [.awaitingRefinement, .open])
        XCTAssertEqual(transcript.lines[1].start, 3.6)
    }

    @MainActor
    func testLiveCaptionTranscript_longSpeechClosesAtMaxLength() {
        var transcript = LiveCaptionTranscript()
        var closed: [Int] = []
        for second in stride(from: 0.0, to: 10, by: 2) {
            closed += transcript.applyFinal("phrase", start: second, end: second + 1.9)
        }
        XCTAssertEqual(closed, [0], "The line closes once it spans 8 s")
        XCTAssertEqual(transcript.lines.first?.text, "phrase phrase phrase phrase phrase")
    }

    @MainActor
    func testLiveCaptionLanguage_mapsIdentifiersAndPicksDefaults() {
        XCTAssertEqual(LiveCaptionLanguage(languageIdentifier: "zh-Hans-CN"), .chinese)
        XCTAssertEqual(LiveCaptionLanguage(languageIdentifier: "zh-TW"), .chineseTraditional)
        XCTAssertEqual(LiveCaptionLanguage(languageIdentifier: "ja-JP"), .japanese)
        XCTAssertNil(LiveCaptionLanguage(languageIdentifier: "nl"))
        XCTAssertFalse(LiveCaptionLanguage.captionable.contains(.russian), "Apple's speech model has no Russian")

        XCTAssertEqual(LiveCaptionLanguage.initial(dictation: .chineseEnglishMixed, preferredLanguages: ["en-US"]), .chinese)
        XCTAssertEqual(LiveCaptionLanguage.initial(dictation: .auto, preferredLanguages: ["ja-JP", "en-US"]), .japanese)
        XCTAssertEqual(LiveCaptionLanguage.initial(dictation: .russian, preferredLanguages: ["ru-RU"]), .english)

        // Watching Japanese on a Chinese Mac: translate into Chinese.
        XCTAssertEqual(LiveCaptionLanguage.suggestedTarget(for: .japanese, preferredLanguages: ["zh-Hans-CN", "en"]), .chinese)
        // Captions already in the Mac's language: English, or Chinese for English captions.
        XCTAssertEqual(LiveCaptionLanguage.suggestedTarget(for: .chineseTraditional, preferredLanguages: ["zh-Hans-CN"]), .english)
        XCTAssertEqual(LiveCaptionLanguage.suggestedTarget(for: .english, preferredLanguages: ["en-US"]), .chinese)
    }

    @MainActor
    func testLiveCaptionRecord_writesTurnsInSpokenOrderWithTranslations() throws {
        let start = Date(timeIntervalSince1970: 1_760_000_000) // 2025-10-09 08:53:20 UTC
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        var record = LiveCaptionRecord(startedAt: start, language: .japanese)
        record.translationTarget = .chinese
        func entry(_ id: String, _ seconds: Double, _ source: LiveCaptionSource, _ speaker: Int?, _ text: String) -> LiveCaptionRecord.Entry {
            .init(id: id, time: start.addingTimeInterval(seconds), source: source, speaker: speaker, text: text)
        }
        // Settled out of order: the microphone line waited for its echo check.
        record.add(entry("macAudio-0", 1, .macAudio, 1, "こんにちは。"))
        record.add(entry("macAudio-1", 4, .macAudio, 1, "始めましょう。"))
        record.add(entry("microphone-0", 2.5, .microphone, nil, "はい。"))
        record.add(entry("macAudio-2", 90, .macAudio, 2, "質問があります。"))
        record.add(entry("macAudio-0", 1, .macAudio, 1, "duplicate"))
        record.setTranslation("你好。", for: "macAudio-0")

        XCTAssertEqual(record.markdown(timeZone: utc), """
        # Live Captions 2025-10-09 08:53

        日本語 → 中文

        **08:53:21 · Speaker 1**

        こんにちは。
        > 你好。

        **08:53:22 · You**

        はい。

        **08:53:24 · Speaker 1**

        始めましょう。

        **08:54:50 · Speaker 2**

        質問があります。

        """)
        XCTAssertEqual(LiveCaptionRecord.fileName(startedAt: start, timeZone: utc), "Live Captions 2025-10-09 08.53.20.md")
    }

    @MainActor
    func testLiveCaptionRecord_marksTimeWithinALongTurn() throws {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        var record = LiveCaptionRecord(startedAt: start, language: .english)
        for (index, seconds) in [0.0, 30, 59, 61].enumerated() {
            record.add(.init(id: "macAudio-\(index)", time: start.addingTimeInterval(seconds), source: .macAudio, text: "Line \(index)."))
        }
        let markdown = try record.markdown(timeZone: XCTUnwrap(TimeZone(identifier: "UTC")))
        // One voice, no microphone: times only, no names; a new mark after a minute.
        XCTAssertTrue(markdown.contains("**08:53:20**\n\nLine 0.\n\nLine 1.\n\nLine 2.\n\n**08:54:21**\n\nLine 3.\n"), markdown)
    }

    @MainActor
    func testLiveCaptionTranscript_longCommittedPhraseClosesItsNewLine() {
        // Unbroken speech: Apple commits only when asked, about 10 s at a time.
        var transcript = LiveCaptionTranscript()
        XCTAssertEqual(transcript.applyFinal("first ten seconds", start: 0, end: 10), [0])
        XCTAssertEqual(transcript.applyFinal("next ten seconds", start: 10, end: 20), [1], "Each phrase gets its own line")
        XCTAssertEqual(transcript.lines.map(\.text), ["first ten seconds", "next ten seconds"])
    }

    @MainActor
    func testLiveCaptionTranscript_idleClosesOnlyWhenNoWordsAreForming() {
        var transcript = LiveCaptionTranscript()
        _ = transcript.applyFinal("Hello there.", start: 0, end: 1)
        XCTAssertEqual(transcript.applyVolatile("and", start: 1.1), [])
        XCTAssertEqual(transcript.closeIfIdle(now: 5), [], "Forming words keep the line open")

        _ = transcript.applyFinal("and welcome.", start: 1.1, end: 2)
        XCTAssertEqual(transcript.volatileText, "", "A final covering the tail clears it")
        XCTAssertEqual(transcript.closeIfIdle(now: 2.5), [])
        XCTAssertEqual(transcript.closeIfIdle(now: 3.3), [0])
        XCTAssertEqual(transcript.lines.first?.text, "Hello there. and welcome.")
    }

    @MainActor
    func testLiveCaptionTranscript_wordsAfterAPauseCloseTheLineBeforeTheySettle() {
        var transcript = LiveCaptionTranscript()
        _ = transcript.applyFinal("请帮我 review 这个 pull request。", start: 0.4, end: 5.5)
        XCTAssertEqual(transcript.applyVolatile("Live", start: 5.9), [], "A short gap may continue the line")
        XCTAssertEqual(transcript.applyVolatile("Live captions", start: 7.9), [0])
        XCTAssertEqual(transcript.lines.first?.state, .awaitingRefinement)

        _ = transcript.applyFinal("Live captions now refine every line.", start: 7.9, end: 11.8)
        XCTAssertEqual(transcript.lines.map(\.state), [.awaitingRefinement, .open])
    }

    @MainActor
    func testLiveCaptionTranscript_heardPauseClosesTheLineOnceAppleCommitsIt() {
        var transcript = LiveCaptionTranscript()
        _ = transcript.applyFinal("Hello", start: 0, end: 1)
        _ = transcript.applyVolatile("there", start: 1.0)
        XCTAssertEqual(transcript.speechEnded(at: 1.6), [], "Apple hasn't committed the last words yet")

        XCTAssertEqual(transcript.applyFinal("there.", start: 1.05, end: 1.5), [0], "Committed words before the pause close the line")
        XCTAssertEqual(transcript.lines.first?.text, "Hello there.")

        XCTAssertEqual(transcript.applyFinal("Next", start: 3, end: 3.5), [], "Speech after the pause starts an open line")
        XCTAssertEqual(transcript.lines.last?.state, .open)
        XCTAssertEqual(transcript.speechEnded(at: 3.9), [1], "With nothing pending, a pause closes the line at once")
    }

    @MainActor
    func testLiveCaptionTranscript_lineAudioDoesNotOverlapNeighbours() throws {
        var transcript = LiveCaptionTranscript()
        _ = transcript.applyFinal("不过有两个用户反馈，", start: 15.2, end: 19.0)
        XCTAssertEqual(transcript.applyFinal("长时间不用之后，第一次转", start: 19.1, end: 23.3), [0], "Closed at max length")
        _ = transcript.applyFinal("写会比较慢。", start: 23.4, end: 25.0)
        XCTAssertEqual(transcript.lines.count, 2)

        let first = try XCTUnwrap(transcript.audioRange(for: 0, padding: 0.25))
        XCTAssertEqual(first.lowerBound, 14.95, accuracy: 0.001)
        XCTAssertEqual(first.upperBound, 23.4, accuracy: 0.001, "Stops where the next line starts")
        let second = try XCTUnwrap(transcript.audioRange(for: 1, padding: 0.25))
        XCTAssertEqual(second.lowerBound, 23.3, accuracy: 0.001, "Starts where the previous line ends")
        XCTAssertEqual(second.upperBound, 25.25, accuracy: 0.001)
    }

    @MainActor
    func testLiveCaptionTranscript_refinementReplacesOrKeepsAppleText() {
        var transcript = LiveCaptionTranscript()
        _ = transcript.applyFinal("请帮我 review 这个 pull request", start: 0, end: 2)
        _ = transcript.applyFinal("然后 deploy 到 staging", start: 4, end: 6)
        _ = transcript.closeIfIdle(now: 10)

        transcript.refine(0, with: "请帮我 review 这个 pull request。")
        transcript.refine(1, with: nil)
        XCTAssertEqual(transcript.lines.map(\.state), [.refined, .draftOnly])
        XCTAssertEqual(transcript.lines[0].text, "请帮我 review 这个 pull request。")
        XCTAssertEqual(transcript.lines[1].text, "然后 deploy 到 staging")

        transcript.refine(0, with: "ignored")
        XCTAssertEqual(transcript.lines[0].text, "请帮我 review 这个 pull request。", "Only lines awaiting refinement change")
    }

    @MainActor
    func testLiveCaptionTranscript_keepsAudioForDraftLinesAndTrimsFinishedOnes() {
        var transcript = LiveCaptionTranscript(policy: .init(maxLines: 2))
        _ = transcript.applyFinal("one", start: 0, end: 1)
        _ = transcript.applyFinal("two", start: 3, end: 4)
        _ = transcript.applyFinal("three", start: 6, end: 7)
        XCTAssertEqual(transcript.lines.count, 3, "Unrefined lines are never dropped")
        XCTAssertEqual(transcript.earliestNeededTime(now: 8), 0)

        transcript.refine(0, with: "One.")
        XCTAssertEqual(transcript.lines.map(\.text), ["two", "three"])
        XCTAssertEqual(transcript.earliestNeededTime(now: 8), 3)
    }

    @MainActor
    func testLiveCaptionTranscript_joinsLatinWordsWithSpacesOnly() {
        XCTAssertEqual(LiveCaptionTranscript.join("Hello", "world"), "Hello world")
        XCTAssertEqual(LiveCaptionTranscript.join("Hello", "."), "Hello.")
        XCTAssertEqual(LiveCaptionTranscript.join("Done.", "Next"), "Done. Next")
        XCTAssertEqual(LiveCaptionTranscript.join("你好", "世界"), "你好世界")
        XCTAssertEqual(LiveCaptionTranscript.join("review", "这个"), "review这个")
        XCTAssertEqual(LiveCaptionTranscript.join("version", "2"), "version 2")
    }

    /// Plays speech through the Mac's speakers and checks it comes back as captions:
    /// system audio tap → Apple draft → lines → Qwen refinement.
    @MainActor
    func testLiveCaptionsEndToEnd_captionsSpeechPlayedByTheMac() async throws {
        let service = try Self.startLiveCaptions(env: "RUN_LIVE_CAPTION_E2E_TESTS")
        defer { service.stop() }
        try await Self.waitUntil(timeout: 60) { service.viewState.phase != .preparing }
        XCTAssertEqual(service.viewState.phase, .listening)

        let started = Date()
        for (voice, text) in [
            ("Tingting", "请帮我 review 这个 pull request，然后 deploy 到 staging。"),
            ("Samantha", "Live captions now refine every line on this Mac."),
        ] {
            try await Self.say(text, voice: voice)
            try await Task.sleep(for: .seconds(1.5))
        }
        try await Self.waitUntil(timeout: 30) {
            let rows = service.viewState.rows
            return rows.count >= 2 && !rows.contains(where: \.isDraft)
        }

        let rows = service.viewState.rows
        Self.printRows(rows, prefix: "LIVE_CAPTION_E2E")
        print("LIVE_CAPTION_E2E_SECONDS=\(Date().timeIntervalSince(started))")
        let joined = rows.map(\.text).joined(separator: " ")
        let text = Self.normalize(joined)
        XCTAssertGreaterThanOrEqual(rows.count, 2, "The pause between the two sentences should split them")
        XCTAssertTrue(rows.contains(where: \.isRefined), "At least one line should come from Qwen")
        XCTAssertTrue(
            joined.unicodeScalars.contains { (0x4E00 ... 0x9FFF).contains(Int($0.value)) },
            "Chinese speech must stay Chinese, not be translated: \(joined)"
        )
        for term in ["review", "deploy", "staging", "captions"] {
            XCTAssertTrue(text.contains(term), "Missing '\(term)' in: \(text)")
        }
    }

    /// Japanese captions: Apple's Japanese model (downloaded the first time) and Qwen in
    /// Japanese; the session's transcript is saved as Markdown.
    @MainActor
    func testLiveCaptionsEndToEnd_captionsJapaneseAndSavesTheTranscript() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "sayit-live-captions-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let mac = MicrophoneFeed()
        let service = try Self.startLiveCaptions(
            env: "RUN_LIVE_CAPTION_E2E_TESTS",
            macAudio: mac,
            language: .japanese,
            transcriptFolder: folder
        )
        defer { service.stop() }
        try await Self.waitUntil(timeout: 180) { service.viewState.phase != .preparing }
        XCTAssertEqual(service.viewState.phase, .listening)

        mac.play(try await Self.render("今日はリリースの話をしましょう。テストは全部通りました。", voice: "Kyoko"))
        try await Self.waitUntil(timeout: 30) {
            let rows = service.viewState.rows
            return !rows.isEmpty && !rows.contains(where: \.isDraft)
        }
        let rows = service.viewState.rows
        Self.printRows(rows, prefix: "LIVE_CAPTION_JA")
        let joined = rows.map(\.text).joined()
        XCTAssertTrue(joined.unicodeScalars.contains { (0x3040 ... 0x30FF).contains(Int($0.value)) }, "Expected kana: \(joined)")
        XCTAssertTrue(joined.contains("リリース"), joined)

        service.stop()
        try await Self.waitUntil(timeout: 10) {
            ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).contains { $0.hasSuffix(".md") }
        }
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
        let markdown = try String(contentsOf: file, encoding: .utf8)
        print("LIVE_CAPTION_JA_TRANSCRIPT=\(markdown)")
        XCTAssertTrue(markdown.hasPrefix("# Live Captions "), markdown)
        XCTAssertTrue(markdown.contains("日本語"), markdown)
        XCTAssertTrue(markdown.contains("リリース"), markdown)
    }

    /// Switching language mid-session restarts Apple's recognizers; earlier lines stay and
    /// later speech is captioned in the new language.
    @MainActor
    func testLiveCaptionsEndToEnd_switchesLanguageMidSession() async throws {
        let mac = MicrophoneFeed()
        let service = try Self.startLiveCaptions(env: "RUN_LIVE_CAPTION_E2E_TESTS", macAudio: mac, language: .english)
        defer { service.stop() }
        try await Self.waitUntil(timeout: 60) { service.viewState.phase != .preparing }

        mac.play(try await Self.render("Live captions now refine every line on this Mac.", voice: "Samantha"))
        try await Self.waitUntil(timeout: 30) { service.viewState.rows.contains { !$0.isDraft } }

        service.setLanguage(.japanese, remember: false)
        try await Self.waitUntil(timeout: 180) {
            service.viewState.language == .japanese && !service.viewState.isChangingLanguage
        }
        XCTAssertEqual(service.viewState.language, .japanese)
        XCTAssertEqual(service.viewState.phase, .listening)

        mac.play(try await Self.render("来週の月曜日にリリースします。", voice: "Kyoko"))
        try await Self.waitUntil(timeout: 30) {
            service.viewState.rows.contains { !$0.isDraft && $0.text.unicodeScalars.contains { (0x3040 ... 0x30FF).contains(Int($0.value)) } }
        }
        let rows = service.viewState.rows
        Self.printRows(rows, prefix: "LIVE_CAPTION_SWITCH")
        XCTAssertTrue(Self.normalize(rows.map(\.text).joined(separator: " ")).contains("captions"), "English lines stay")
    }

    /// Translation on this Mac, shown next to each settled line. Needs the Japanese →
    /// Chinese languages downloaded (the panel's Download… button does that).
    @MainActor
    func testLiveCaptionsEndToEnd_translatesSettledLines() async throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Live Captions need macOS 26.") }
        guard await LiveCaptionTranslator.readiness(from: .japanese, to: .chinese) == .ready else {
            throw XCTSkip("Download Japanese and Chinese for translation first (System Settings → General → Language & Region → Translation Languages).")
        }
        let mac = MicrophoneFeed()
        let service = try Self.startLiveCaptions(
            env: "RUN_LIVE_CAPTION_E2E_TESTS",
            macAudio: mac,
            language: .japanese,
            translateInto: .chinese
        )
        defer { service.stop() }
        try await Self.waitUntil(timeout: 60) { service.viewState.translation?.status == .ready }

        mac.play(try await Self.render("今日はリリースの話をしましょう。", voice: "Kyoko"))
        try await Self.waitUntil(timeout: 30) { service.viewState.rows.contains { $0.translation != nil } }
        let rows = service.viewState.rows
        for row in rows {
            print("LIVE_CAPTION_TRANSLATE_LINE text=\(row.text) translation=\(row.translation ?? "-")")
        }
        let translation = try XCTUnwrap(rows.compactMap(\.translation).first)
        XCTAssertFalse(translation.unicodeScalars.contains { (0x3040 ... 0x30FF).contains(Int($0.value)) }, "No kana in Chinese: \(translation)")
        XCTAssertTrue(translation.contains("发布"), translation)
    }

    /// Keeps a real panel full of captions on screen for a while, so its controls can be
    /// clicked, scrolled and resized from outside (synthetic events). Prints what changed.
    @MainActor
    func testLiveCaptionsPanel_holdsForInspection() async throws {
        let mac = MicrophoneFeed()
        let environment = ProcessInfo.processInfo.environment
        // LIVE_CAPTION_HOLD_LANGUAGE=japanese speaks Japanese; LIVE_CAPTION_HOLD_TARGET=chinese translates.
        let language = environment["LIVE_CAPTION_HOLD_LANGUAGE"].flatMap(LiveCaptionLanguage.init(rawValue:)) ?? .english
        let target = environment["LIVE_CAPTION_HOLD_TARGET"].flatMap(LiveCaptionLanguage.init(rawValue:))
        let service = try Self.startLiveCaptions(
            env: "RUN_LIVE_CAPTION_PANEL_HOLD",
            macAudio: mac,
            language: language,
            translateInto: target
        )
        defer { service.stop() }
        try await Self.waitUntil(timeout: 60) { service.viewState.phase != .preparing }
        let japanese = language == .japanese
        let passage = japanese
            ? "今日はリリースの話をしましょう。テストは全部通りました。来週の月曜日に出します。"
            : "The panel keeps every line, so you can scroll back and read what was said a minute ago."
        for _ in 0..<6 {
            mac.play(try await Self.render(passage, voice: japanese ? "Kyoko" : "Samantha"))
            mac.play([Float](repeating: 0, count: 16000))
        }
        let seconds = Double(ProcessInfo.processInfo.environment["LIVE_CAPTION_HOLD_SECONDS"] ?? "") ?? 90
        let end = Date().addingTimeInterval(seconds)
        var last = ""
        while Date() < end {
            let state = service.viewState
            let summary = "rows=\(state.rows.count) microphone=\(state.microphone) speakers=\(state.speakers) "
                + "translation=\(state.translation.map { "\($0.status)" } ?? "off") translated=\(state.rows.filter { $0.translation != nil }.count)"
            if summary != last {
                print("LIVE_CAPTION_HOLD \(summary)")
                last = summary
            }
            try await Task.sleep(for: .milliseconds(500))
        }
    }

    /// The microphone hears exactly what the Mac plays (speakers, no headphones): those
    /// words are already captioned, so no microphone line may appear.
    @MainActor
    func testLiveCaptionsEndToEnd_dropsSpeakerSoundHeardByTheMicrophone() async throws {
        guard #available(macOS 14.2, *) else { throw XCTSkip("Needs macOS 14.2") }
        let service = try Self.startLiveCaptions(env: "RUN_LIVE_CAPTION_E2E_TESTS", microphone: { EchoMicrophone(onSamples: $0) })
        defer { service.stop() }
        try await Self.waitUntil(timeout: 60) { service.viewState.phase != .preparing }

        for (voice, text) in [
            ("Tingting", "请帮我 review 这个 pull request，然后 deploy 到 staging。"),
            ("Samantha", "Live captions now refine every line on this Mac."),
        ] {
            try await Self.say(text, voice: voice)
            try await Task.sleep(for: .seconds(1.5))
        }
        try await Self.waitUntil(timeout: 30) {
            let rows = service.viewState.rows
            return rows.filter { $0.source == .macAudio }.count >= 2 && !rows.contains(where: \.isDraft)
        }
        // Give the microphone's lines time to close and be checked.
        try await Task.sleep(for: .seconds(5))

        let rows = service.viewState.rows
        Self.printRows(rows, prefix: "LIVE_CAPTION_ECHO")
        XCTAssertEqual(service.viewState.microphone, .on)
        XCTAssertEqual(rows.filter { $0.source == .microphone }.map(\.text), [], "Speaker sound must not be captioned twice")
        XCTAssertGreaterThanOrEqual(rows.filter { $0.source == .macAudio }.count, 2)
    }

    /// The user speaks while the Mac is quiet, between two things the Mac plays: their line
    /// is kept, marked as theirs, and ordered between the Mac's lines.
    @MainActor
    func testLiveCaptionsEndToEnd_captionsTheMicrophoneBetweenMacAudio() async throws {
        let feed = MicrophoneFeed()
        let service = try Self.startLiveCaptions(
            env: "RUN_LIVE_CAPTION_E2E_TESTS",
            microphone: { FakeMicrophone(feed: feed, onSamples: $0) }
        )
        defer { service.stop() }
        try await Self.waitUntil(timeout: 60) { service.viewState.phase != .preparing }
        let reply = try await Self.render("Sounds good. I will send the draft on Monday.", voice: "Samantha")

        try await Self.say("我们这周先把迁移指南写完。", voice: "Tingting")
        try await Task.sleep(for: .seconds(1.5))
        feed.play(reply)
        try await Task.sleep(for: .seconds(Double(reply.count) / 16000 + 1.5))
        try await Self.say("好的，那就周一见。", voice: "Tingting")

        try await Self.waitUntil(timeout: 30) {
            let rows = service.viewState.rows
            return rows.count >= 3 && !rows.contains(where: \.isDraft)
        }
        let rows = service.viewState.rows
        Self.printRows(rows, prefix: "LIVE_CAPTION_MIC")
        XCTAssertEqual(rows.map(\.source), [.macAudio, .microphone, .macAudio])
        let replyText = Self.normalize(rows.first { $0.source == .microphone }?.text ?? "")
        for term in ["draft", "monday"] {
            XCTAssertTrue(replyText.contains(term), "Missing '\(term)' in: \(replyText)")
        }
    }

    /// About a minute of alternating Chinese and English speech, for measuring what Live
    /// Captions cost while running (sample the process from outside while it plays).
    @MainActor
    func testLiveCaptionsSoak_aMinuteOfSpeech() async throws {
        let service = try Self.startLiveCaptions(env: "RUN_LIVE_CAPTION_SOAK_TESTS")
        defer { service.stop() }
        try await Self.waitUntil(timeout: 60) { service.viewState.phase != .preparing }

        let script: [(String, String)] = [
            ("Tingting", "今天我们先过一下上周的发布情况，整体比较顺利。"),
            ("Samantha", "The new onboarding flow shipped on Tuesday without any rollbacks."),
            ("Tingting", "不过有两个用户反馈，说长时间不用之后，第一次转写会比较慢。"),
            ("Samantha", "We traced it to the model weights being paged out while the app sat idle."),
            ("Tingting", "所以现在开始录音的时候，会先在后台把模型预热一下。"),
            ("Samantha", "That hides the page-in behind the time you spend speaking."),
            ("Tingting", "接下来我们想做 Live Captions，用 Apple 出草稿，再用 Qwen 逐句替换。"),
            ("Samantha", "Captions should appear within a second, and settle about two seconds later."),
            ("Tingting", "如果大家没有别的问题，我们就按这个计划推进，下周再同步一次进度。"),
            ("Samantha", "Thanks everyone, see you next week."),
        ]
        let started = Date()
        for (voice, text) in script {
            try await Self.say(text, voice: voice)
            try await Task.sleep(for: .seconds(1))
        }
        let spoken = Date().timeIntervalSince(started)
        try await Self.waitUntil(timeout: 30) { !service.viewState.rows.contains(where: \.isDraft) }

        let rows = service.viewState.rows
        Self.printRows(rows, prefix: "LIVE_CAPTION_SOAK")
        print("LIVE_CAPTION_SOAK_SPOKEN_SECONDS=\(spoken) LINES=\(rows.count) REFINED=\(rows.filter(\.isRefined).count)")
        XCTAssertGreaterThanOrEqual(rows.filter(\.isRefined).count, script.count / 2)
    }

    /// Runs Live Captions in silence for 30 s, for measuring their fixed cost from outside
    /// (set LIVE_CAPTION_COST_SPEAKERS=1 to include speaker labels). Plays nothing.
    @MainActor
    func testLiveCaptionsCost_thirtySecondsOfSilence() async throws {
        let speakers = ProcessInfo.processInfo.environment["LIVE_CAPTION_COST_SPEAKERS"] == "1"
        let service = try Self.startLiveCaptions(env: "RUN_LIVE_CAPTION_COST_TESTS", labelSpeakers: speakers)
        defer { service.stop() }
        try await Self.waitUntil(timeout: 120) {
            service.viewState.phase != .preparing && service.viewState.speakers != .preparing
        }
        print("LIVE_CAPTION_COST_READY speakers=\(service.viewState.speakers)")
        try await Task.sleep(for: .seconds(30))
        print("LIVE_CAPTION_COST_DONE")
    }

    /// Starts Live Captions when `env` is set, with the microphone on only when given one.
    /// With `macAudio`, Mac audio is that feed instead of what the Mac plays (silent tests).
    /// Uses its own options (never the saved settings, which the installed app shares) and
    /// saves transcripts to a temporary folder.
    @MainActor
    private static func startLiveCaptions(
        env: String,
        microphone: CaptionSourceFactory? = nil,
        macAudio: MicrophoneFeed? = nil,
        labelSpeakers: Bool = false,
        language: LiveCaptionLanguage = .chinese,
        translateInto target: LiveCaptionLanguage? = nil,
        transcriptFolder: URL = FileManager.default.temporaryDirectory.appending(path: "sayit-live-captions-\(UUID().uuidString)")
    ) throws -> LiveCaptionService {
        guard ProcessInfo.processInfo.environment[env] == "1" else {
            throw XCTSkip("Set \(env)=1 to play speech aloud and caption it.")
        }
        guard LiveCaptionService.isSupported else { throw XCTSkip("Live Captions need macOS 26.") }
        let service = LiveCaptionService.shared
        service.start(options: LiveCaptionOptions(
            language: language,
            translationTarget: target,
            includeMicrophone: microphone != nil,
            labelSpeakers: labelSpeakers,
            makeMicrophone: microphone,
            makeMacAudio: macAudio.map { feed in { FakeMicrophone(feed: feed, onSamples: $0) } },
            transcriptFolder: transcriptFolder
        ))
        return service
    }

    private static func printRows(_ rows: [LiveCaptionViewState.Row], prefix: String) {
        for row in rows {
            print("\(prefix)_LINE source=\(row.source.rawValue) refined=\(row.isRefined) text=\(row.text)")
        }
    }

    private static func say(_ text: String, voice: String) async throws {
        try await self.runSay(["-v", voice, text])
    }

    /// Speech rendered to 16 kHz mono samples instead of played.
    private static func render(_ text: String, voice: String) async throws -> [Float] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sayit-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: url) }
        try await self.runSay(["-v", voice, "-o", url.path, text])
        return try AudioFixtureLoader.load16kMonoFloatSamples(from: url)
    }

    private static func runSay(_ arguments: [String]) async throws {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            process.arguments = arguments
            try process.run()
            process.waitUntilExit()
        }.value
    }

    @MainActor
    private static func waitUntil(timeout: TimeInterval, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("Timed out after \(timeout) s") }
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Two voices take turns; each line should be labeled with the right speaker.
    @MainActor
    func testLiveCaptionsEndToEnd_labelsTwoSpeakers() async throws {
        let service = try Self.startLiveCaptions(env: "RUN_LIVE_CAPTION_E2E_TESTS", labelSpeakers: true)
        defer { service.stop() }
        // The first run downloads the speaker model (about 250 MB).
        try await Self.waitUntil(timeout: 600) {
            service.viewState.phase != .preparing && service.viewState.speakers != .preparing
        }
        XCTAssertEqual(service.viewState.speakers, .on)

        let turns: [(String, String)] = [
            ("Samantha", "Thanks for joining. Let's start with the release status."),
            ("Reed (English (US))", "The build passed this morning, and the installer is signed."),
            ("Samantha", "Great. Did we fix the slow first transcription?"),
            ("Reed (English (US))", "Yes, the model now warms up while you are speaking."),
            ("Samantha", "Perfect, let's ship it on Friday."),
        ]
        for (voice, text) in turns {
            try await Self.say(text, voice: voice)
            try await Task.sleep(for: .seconds(1))
        }
        try await Self.waitUntil(timeout: 30) {
            let rows = service.viewState.rows
            return rows.count >= turns.count && !rows.contains(where: \.isDraft)
        }
        // Diarization settles a moment after the words do.
        try await Task.sleep(for: .seconds(2))

        let rows = service.viewState.rows
        for row in rows {
            print("LIVE_CAPTION_SPEAKERS_LINE speaker=\(row.speaker.map(String.init) ?? "-") text=\(row.text)")
        }
        let speakers = rows.map(\.speaker)
        XCTAssertGreaterThanOrEqual(Set(speakers.compactMap { $0 }).count, 2, "Two voices should get two labels: \(speakers)")
        let changes = zip(speakers, speakers.dropFirst()).filter { $0 != $1 }.count
        XCTAssertGreaterThanOrEqual(changes, 3, "Labels should follow the turns: \(speakers)")
    }

    @MainActor
    func testSpeakerTurns_dominantSpeakerAndNumbering() {
        let turns = SpeakerTurns(turns: [
            .init(speaker: 2, start: 0, end: 3),
            .init(speaker: 0, start: 3.2, end: 6),
            .init(speaker: 2, start: 6.1, end: 6.4),
        ])
        XCTAssertEqual(turns.dominantSpeaker(in: 0.5...2.5), 2)
        XCTAssertEqual(turns.dominantSpeaker(in: 2.5...6.5), 0, "Most of the span is speaker 0")
        XCTAssertNil(turns.dominantSpeaker(in: 7...10), "Nobody was heard")
        XCTAssertNil(turns.dominantSpeaker(in: 6.2...9), "Heard for under a quarter of the span")

        var numbering = SpeakerNumbering()
        XCTAssertEqual(numbering.number(for: 2), 1, "Numbered in order of first appearance")
        XCTAssertEqual(numbering.number(for: 0), 2)
        XCTAssertEqual(numbering.number(for: 2), 1)
        XCTAssertEqual(numbering.count, 2)
    }

    @MainActor
    func testLiveCaptionTurnLabels_onlyWhereTheSpeakerChanges() {
        func row(_ id: String, _ source: LiveCaptionSource, _ speaker: Int?) -> LiveCaptionViewState.Row {
            LiveCaptionViewState.Row(id: id, source: source, text: id, isDraft: false, speaker: speaker)
        }
        let labels = LiveCaptionViewState.turnLabels(for: [
            row("a", .macAudio, 1),
            row("b", .macAudio, 1),
            row("c", .macAudio, 2),
            row("d", .microphone, nil),
            row("e", .macAudio, 2),
            row("f", .macAudio, nil),
        ])
        XCTAssertEqual(labels, ["a": "Speaker 1", "c": "Speaker 2", "e": "Speaker 2"])
    }

    @MainActor
    func testLiveCaptionTranscript_closeOpenLineForAnotherSpeaker() {
        var transcript = LiveCaptionTranscript()
        XCTAssertNil(transcript.openLineSpan)
        _ = transcript.applyFinal("Thanks for joining.", start: 0.4, end: 2)
        XCTAssertEqual(transcript.openLineSpan, 0.4...2)
        XCTAssertEqual(transcript.closeOpenLine(), [0])
        XCTAssertNil(transcript.openLineSpan)
        XCTAssertEqual(transcript.closeOpenLine(), [])
    }

    @MainActor
    func testLiveCaptionEcho_recognizesTheSameWordsHeardTwice() {
        // Two recognitions of the same sound differ in spacing, punctuation and a word or two.
        XCTAssertTrue(LiveCaptionEcho.isEcho("请帮我 review这个 porequest", of: "请帮我 review 这个 pull request，然后 deploy 到 staging。"))
        XCTAssertTrue(LiveCaptionEcho.isEcho("Life captions nor refine every line", of: "Live captions now refine every line on this Mac."))
        XCTAssertFalse(LiveCaptionEcho.isEcho("Sounds good, I will send the draft on Monday.", of: "我们这周先把迁移指南写完。"))
        XCTAssertFalse(LiveCaptionEcho.isEcho("下周一发，我今天先写初稿。", of: "So when does the migration guide go out?"))
        XCTAssertFalse(LiveCaptionEcho.isEcho("Anything", of: ""))
    }

    @MainActor
    func testLiveCaptionTranscript_textOverlappingATimeRange() {
        var transcript = LiveCaptionTranscript()
        _ = transcript.applyFinal("first", start: 0, end: 2)
        _ = transcript.applyFinal("second", start: 4, end: 6)
        _ = transcript.applyVolatile("third", start: 7)
        XCTAssertEqual(transcript.text(overlapping: 3...5), "second")
        XCTAssertEqual(transcript.text(overlapping: 1...8), "first second third")
        transcript.remove(0)
        XCTAssertEqual(transcript.lines.map(\.text), ["second"])
    }

    func testCaptionAudioTimeline_slicesByTimeAndRefusesDiscardedAudio() throws {
        let timeline = CaptionAudioTimeline()
        timeline.append([Float](repeating: 0, count: 16000 * 8))
        XCTAssertFalse(timeline.hasHeardSound)
        timeline.append([Float](repeating: 0.2, count: 16000 * 2))
        XCTAssertTrue(timeline.hasHeardSound)
        XCTAssertEqual(timeline.duration, 10, accuracy: 0.001)

        XCTAssertEqual(timeline.samples(from: 8, to: 9).count, 16000)
        XCTAssertEqual(timeline.samples(from: 9.5, to: 12).count, 8000, "Clamped to what was captured")
        XCTAssertEqual(timeline.level(from: 1, to: 2), 0)
        XCTAssertEqual(timeline.level(from: 8.5, to: 9.5), 0.2, accuracy: 0.001)

        timeline.discard(before: 2)
        XCTAssertFalse(timeline.samples(from: 0, to: 1).isEmpty, "Trims happen in 5 s steps")
        timeline.discard(before: 6)
        XCTAssertTrue(timeline.samples(from: 5, to: 7).isEmpty, "Discarded audio can't be refined")
        XCTAssertEqual(timeline.samples(from: 6, to: 7).count, 16000)

        XCTAssertEqual(timeline.trailingSilence(), 0, "The audio ends loud")
        timeline.append([Float](repeating: 0, count: 16000))
        XCTAssertEqual(timeline.trailingSilence(), 1, accuracy: 0.001)
        let quiet = try XCTUnwrap(timeline.quietestPoint(from: 9, to: 10.5))
        XCTAssertGreaterThanOrEqual(quiet, 10, "The quiet point is in the silence, not the speech")
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

// MARK: - Live Captions test microphones

/// A microphone that hears exactly what the Mac plays, like speakers with no headphones.
@available(macOS 14.2, *)
@MainActor
private final class EchoMicrophone: CaptionAudioSource {
    private let tap: SystemAudioCapture

    init(onSamples: @escaping @Sendable ([Float]) -> Void) {
        self.tap = SystemAudioCapture(onSamples: onSamples)
    }

    func start() throws { try self.tap.start() }
    func stop() { self.tap.stop() }
}

/// Audio queued for `FakeMicrophone` to "hear".
private final class MicrophoneFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [Float] = []

    func play(_ samples: [Float]) {
        self.lock.withLock { self.queued += samples }
    }

    /// The next `count` samples: queued speech, then silence.
    func next(_ count: Int) -> [Float] {
        self.lock.withLock {
            let taken = Array(self.queued.prefix(count))
            self.queued.removeFirst(taken.count)
            return taken + [Float](repeating: 0, count: count - taken.count)
        }
    }
}

/// A microphone that delivers `MicrophoneFeed` audio in real time, 100 ms at a time.
@MainActor
private final class FakeMicrophone: CaptionAudioSource {
    private let feed: MicrophoneFeed
    private let onSamples: @Sendable ([Float]) -> Void
    private var task: Task<Void, Never>?

    init(feed: MicrophoneFeed, onSamples: @escaping @Sendable ([Float]) -> Void) {
        self.feed = feed
        self.onSamples = onSamples
    }

    func start() throws {
        let feed = self.feed
        let onSamples = self.onSamples
        self.task = Task.detached {
            let chunk = 1600
            var next = ContinuousClock.now
            while !Task.isCancelled {
                onSamples(feed.next(chunk))
                next += .milliseconds(100)
                try? await Task.sleep(until: next)
            }
        }
    }

    func stop() {
        self.task?.cancel()
    }
}
