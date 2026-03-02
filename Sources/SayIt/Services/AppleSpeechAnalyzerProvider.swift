import AVFoundation
import Combine
import Foundation

#if canImport(Speech)
import Speech
#endif

// MARK: - Apple Speech Analyzer Provider (macOS 26+)

/// A TranscriptionProvider that uses Apple's new SpeechAnalyzer API (macOS 26+).
/// This provides advanced speech-to-text with streaming capabilities.
@available(macOS 26.0, *)
final class AppleSpeechAnalyzerProvider: TranscriptionProvider {
    var name: String { "Apple Speech (macOS 26+)" }

    var isAvailable: Bool {
        // SpeechAnalyzer is always available on macOS 26+
        true
    }

    private(set) var isReady: Bool = false

    /// Buffer converter for audio format conversion
    private var converter: BufferConverter?

    /// The required audio format for the analyzer
    private var analyzerFormat: AVAudioFormat?

    private static let chineseLocalePrefixes: [String] = ["zh", "zho", "zh-hans", "zh-hant", "zh-cn", "zh-tw"]

    /// Thread-safe cache for model installation status.
    /// Protected by `_cacheQueue` for thread-safe access from both sync and async contexts.
    private var _modelsInstalledCache: Bool = false
    private let _cacheQueue = DispatchQueue(label: "com.sayit.speechanalyzer.cache")
    private static let smartLanguageFallbackLocaleIdentifiers: [String] = [
        "en-US",
        "en-GB",
        "en",
        "zh-Hans",
        "zh-Hans-CN",
        "zh-Hans-HK",
        "zh-Hans-TW",
        "zh-Hant",
        "zh-Hant-CN",
        "zh-Hant-TW",
        "zh",
        "ja-JP",
        "ko-KR",
        "fr-FR",
        "de-DE",
        "es-ES",
        "it-IT",
        "pt-BR",
        "ru-RU"
    ]

    init() {}

    // MARK: - Lifecycle

    func prepare(progressHandler: ((Double) -> Void)?) async throws {
        // 1. Resolve a stable locale that is supported by SpeechAnalyzer.
        let resolvedLocale = await self.resolveSupportedLocale()
        let supportedLocales = await SpeechTranscriber.supportedLocales
        let currentLocaleID = Self.normalizedLocaleIdentifier(resolvedLocale)
        let isSupported = supportedLocales
            .map({ Self.normalizedLocaleIdentifier($0) })
            .contains(currentLocaleID)

        guard isSupported else {
            throw NSError(
                domain: "AppleSpeechAnalyzerProvider",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Current locale is not supported by SpeechAnalyzer"]
            )
        }

        // 2. Create a transcriber to check locale support and download if needed
        let transcriber = SpeechTranscriber(
            locale: resolvedLocale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        // 3. Check if model is installed, download if needed
        let installedLocales = await SpeechTranscriber.installedLocales
        let installedSet = Set(installedLocales.map { Self.normalizedLocaleIdentifier($0) })
        let isInstalled = installedSet.contains(currentLocaleID)

        if !isInstalled {
            DebugLogger.shared.info("Downloading speech model for locale: \(currentLocaleID)", source: "AppleSpeechAnalyzerProvider")
            if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                // Report progress periodically during download
                let progress = downloader.progress
                Task {
                    while !progress.isFinished, !progress.isCancelled {
                        progressHandler?(progress.fractionCompleted)
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }
                try await downloader.downloadAndInstall()
            }
        }

        // 4. Get the best available audio format for conversion
        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        self.converter = BufferConverter()

        self.isReady = true

        // Update cache to reflect that model is now installed (thread-safe)
        self._cacheQueue.sync { self._modelsInstalledCache = true }

        DebugLogger.shared.info("AppleSpeechAnalyzerProvider ready", source: "AppleSpeechAnalyzerProvider")
    }

    func clearCache() async throws {
        // Release reserved locales
        let reserved = await AssetInventory.reservedLocales
        for locale in reserved {
            await AssetInventory.release(reservedLocale: locale)
        }

        // Reset cache to reflect models are no longer installed (thread-safe)
        self._cacheQueue.sync { self._modelsInstalledCache = false }

        self.isReady = false
    }

    /// Returns the cached result of whether models are installed (thread-safe).
    ///
    /// **Important**: This method returns a cached value that defaults to `false`.
    /// For an accurate result, call `refreshModelsExistOnDiskAsync()` first.
    ///
    /// The synchronous nature of this protocol method makes it impossible to
    /// perform the actual async `SpeechTranscriber.installedLocales` check inline.
    /// Callers should use `refreshModelsExistOnDiskAsync()` during initialization
    /// to populate the cache before relying on this value.
    func modelsExistOnDisk() -> Bool {
        return self._cacheQueue.sync { self._modelsInstalledCache }
    }

    /// Performs an async check to determine if speech models are installed for the current locale.
    /// Updates the internal cache so that subsequent `modelsExistOnDisk()` calls return accurate results.
    /// Thread-safe: uses dispatch queue to update cache.
    ///
    /// - Returns: `true` if the current locale's speech model is installed on disk, `false` otherwise.
    func refreshModelsExistOnDiskAsync() async -> Bool {
        let installedLocales = await SpeechTranscriber.installedLocales
        let currentLocaleID = Self.normalizedLocaleIdentifier(
            await self.resolveSupportedLocale(preferDownload: false)
        )
        let installedSet = Set(installedLocales.map { Self.normalizedLocaleIdentifier($0) })
        let isInstalled = installedSet.contains(currentLocaleID)

        self._cacheQueue.sync { self._modelsInstalledCache = isInstalled }

        DebugLogger.shared.debug(
            "AppleSpeechAnalyzer: Model installed check - locale: \(currentLocaleID), installed: \(isInstalled)",
            source: "AppleSpeechAnalyzerProvider"
        )

        return isInstalled
    }

    // MARK: - Transcription

    func transcribe(_ samples: [Float]) async throws -> ASRTranscriptionResult {
        guard self.isReady, let analyzerFormat = self.analyzerFormat else {
            throw NSError(
                domain: "AppleSpeechAnalyzerProvider",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Speech Analyzer not ready"]
            )
        }

        DebugLogger.shared.debug("AppleSpeechAnalyzer: Starting transcription with \(samples.count) samples", source: "AppleSpeechAnalyzerProvider")

        // 1. Resolve locale candidates for this transcription.
        let languageMode = SettingsStore.shared.speechLanguageMode
        let smartDetection = SettingsStore.shared.enableSmartLanguageDetection
        let candidateLocales = await Self.localeCandidatesAsync(
            for: languageMode.isAutomatic ? Locale.current : nil,
            in: languageMode,
            includeSmartFallback: languageMode.isAutomatic && smartDetection
        )

        guard let locale = candidateLocales.first else {
            throw NSError(
                domain: "AppleSpeechAnalyzerProvider",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "No locale candidates available"]
            )
        }

        if languageMode.isAutomatic, smartDetection, candidateLocales.count > 1 {
            return try await self.transcribeWithFallback(
                samples: samples,
                locales: candidateLocales,
                analyzerFormat: analyzerFormat
            )
        }

        return try await self.transcribeWithLocale(
            samples: samples,
            locale: locale,
            analyzerFormat: analyzerFormat
        )
    }

    private func transcribeWithFallback(
        samples: [Float],
        locales: [Locale],
        analyzerFormat: AVAudioFormat
    ) async throws -> ASRTranscriptionResult {
        var lastError: Error?

        for locale in locales {
            do {
                let result = try await self.transcribeWithLocale(
                    samples: samples,
                    locale: locale,
                    analyzerFormat: analyzerFormat
                )
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return result
                }
            } catch {
                lastError = error
                DebugLogger.shared.warning(
                    "AppleSpeechAnalyzer: locale fallback \(locale.identifier(.bcp47)) failed - \(error.localizedDescription)",
                    source: "AppleSpeechAnalyzerProvider"
                )
            }
        }

        if let lastError {
            throw lastError
        }
        return ASRTranscriptionResult(text: "", confidence: 0.0)
    }

    private func transcribeWithLocale(
        samples: [Float],
        locale: Locale,
        analyzerFormat: AVAudioFormat
    ) async throws -> ASRTranscriptionResult {
        // 1. Create a FRESH transcriber for this transcription
        let freshTranscriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        // 2. Create input stream
        let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()

        // 3. Create a fresh analyzer with the fresh transcriber
        let analyzer = SpeechAnalyzer(modules: [freshTranscriber])

        // 4. Convert samples to AVAudioPCMBuffer
        guard let buffer = createPCMBuffer(from: samples) else {
            throw NSError(
                domain: "AppleSpeechAnalyzerProvider",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create audio buffer"]
            )
        }

        // 5. Convert to analyzer format if needed
        let convertedBuffer: AVAudioPCMBuffer
        if let converter = self.converter {
            do {
                convertedBuffer = try converter.convertBuffer(buffer, to: analyzerFormat)
            } catch {
                DebugLogger.shared.warning("Buffer conversion failed: \(error)", source: "AppleSpeechAnalyzerProvider")
                convertedBuffer = buffer
            }
        } else {
            convertedBuffer = buffer
        }

        // 6. Set up results collector FIRST (before starting analyzer - per Apple's pattern)
        var finalText = ""
        let resultsTask = Task {
            DebugLogger.shared.debug("AppleSpeechAnalyzer: Results task started, waiting for results...", source: "AppleSpeechAnalyzerProvider")
            for try await case let result in freshTranscriber.results {
                let text = String(result.text.characters)
                DebugLogger.shared.debug("AppleSpeechAnalyzer: Got result - isFinal: \(result.isFinal), text: '\(text)'", source: "AppleSpeechAnalyzerProvider")
                if result.isFinal {
                    // ACCUMULATE results (per Apple's pattern) - don't break!
                    if !finalText.isEmpty && !text.isEmpty {
                        finalText += " "
                    }
                    finalText += text
                }
                // Continue iterating until stream ends (after finalizeAndFinish)
            }
            DebugLogger.shared.debug("AppleSpeechAnalyzer: Results iteration complete, accumulated: '\(finalText)'", source: "AppleSpeechAnalyzerProvider")
        }

        // 7. Start the analyzer (this kicks off processing)
        DebugLogger.shared.debug("AppleSpeechAnalyzer: Starting analyzer...", source: "AppleSpeechAnalyzerProvider")
        try await analyzer.start(inputSequence: inputStream)
        DebugLogger.shared.debug("AppleSpeechAnalyzer: Analyzer started", source: "AppleSpeechAnalyzerProvider")

        // 8. Feed audio and signal end of input
        let input = AnalyzerInput(buffer: convertedBuffer)
        inputContinuation.yield(input)
        inputContinuation.finish()
        DebugLogger.shared.debug("AppleSpeechAnalyzer: Audio fed and input finished", source: "AppleSpeechAnalyzerProvider")

        // 9. Finalize - this tells the analyzer to process remaining audio and complete the results stream
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            DebugLogger.shared.debug("AppleSpeechAnalyzer: Analyzer finalized", source: "AppleSpeechAnalyzerProvider")
        } catch {
            DebugLogger.shared.warning("Analyzer finalize error: \(error.localizedDescription)", source: "AppleSpeechAnalyzerProvider")
        }

        // 10. Now wait for results task to complete (it will finish once stream closes)
        do {
            try await resultsTask.value
        } catch {
            DebugLogger.shared.warning("Speech recognition error: \(error.localizedDescription)", source: "AppleSpeechAnalyzerProvider")
        }

        DebugLogger.shared.debug("AppleSpeechAnalyzer: Transcription complete - result: '\(finalText)'", source: "AppleSpeechAnalyzerProvider")
        return ASRTranscriptionResult(text: finalText, confidence: 1.0)
    }

    private static func localeCandidatesAsync(
        for locale: Locale?,
        in languageMode: SettingsStore.SpeechLanguageMode,
        includeSmartFallback: Bool = false
    ) async -> [Locale] {
        return localeCandidates(for: locale, in: languageMode, includeSmartFallback: includeSmartFallback)
    }

    // MARK: - Helpers

    /// Converts raw [Float] samples (16kHz mono) to AVAudioPCMBuffer
    private func createPCMBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            return nil
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)

        guard let channelData = buffer.floatChannelData else { return nil }

        samples.withUnsafeBufferPointer { samplePtr in
            guard let baseAddress = samplePtr.baseAddress else { return }
            channelData[0].update(from: baseAddress, count: samples.count)
        }

        return buffer
    }

    private func resolveSupportedLocale(preferDownload: Bool = true) async -> Locale {
        let mode = SettingsStore.shared.speechLanguageMode
        let candidateLocales: [Locale]
        if mode.isAutomatic {
            candidateLocales = Self.localeCandidates(for: Locale.current, in: mode)
        } else {
            candidateLocales = Self.localeCandidates(for: nil, in: mode)
        }
        let supportedLocales = await SpeechTranscriber.supportedLocales
        let supportedSet = Set(supportedLocales.map { Self.normalizedLocaleIdentifier($0) })

        for locale in candidateLocales {
            let candidateID = Self.normalizedLocaleIdentifier(locale)
            if supportedSet.contains(candidateID) {
                if preferDownload {
                    DebugLogger.shared.info(
                        "AppleSpeechAnalyzer: Selected supported locale \(candidateID)",
                        source: "AppleSpeechAnalyzerProvider"
                    )
                }
                return locale
            }
        }

        if let fallback = supportedLocales.first {
            let fallbackID = Self.normalizedLocaleIdentifier(fallback)
            DebugLogger.shared.warning(
                "AppleSpeechAnalyzer: Falling back to default supported locale \(fallbackID)",
                source: "AppleSpeechAnalyzerProvider"
            )
            return fallback
        }

        return Locale.current
    }

    private static func localeCandidates(
        for locale: Locale?,
        in mode: SettingsStore.SpeechLanguageMode,
        includeSmartFallback: Bool
    ) -> [Locale] {
        var ids: [String] = []
        if mode.isAutomatic {
            if let locale {
                ids.append(locale.identifier(.bcp47))
                ids.append(locale.identifier)
                ids.append(contentsOf: Locale.preferredLanguages)
                if let languageCode = Self.languageCode(from: locale.identifier) {
                    ids.append(languageCode)
                }

                if isChineseLocale(locale: locale.identifier) {
                    ids.append("zh-Hans")
                    ids.append("zh-Hans-CN")
                    ids.append("zh-Hans-TW")
                    ids.append("zh-Hant")
                    ids.append("zh-Hant-CN")
                    ids.append("zh-Hant-TW")
                    ids.append("zh")
                }
            }
            if includeSmartFallback {
                ids.append(contentsOf: Self.smartLanguageFallbackLocaleIdentifiers)
            }
        } else {
            ids = mode.localeCandidates
        }

        var orderedIDs: [String] = []
        var seen: Set<String> = []
        for raw in ids {
            let normalized = Self.normalizeLocaleID(raw)
            guard !normalized.isEmpty else { continue }
            if !seen.contains(normalized) {
                seen.insert(normalized)
                orderedIDs.append(normalized)
            }
        }

        return orderedIDs.compactMap { Locale(identifier: $0) }
    }

    private static func localeCandidates(
        for locale: Locale?,
        in mode: SettingsStore.SpeechLanguageMode
    ) -> [Locale] {
        return Self.localeCandidates(for: locale, in: mode, includeSmartFallback: false)
    }

    private static func normalizeLocaleID(_ rawID: String) -> String {
        rawID.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private static func normalizedLocaleIdentifier(_ locale: Locale) -> String {
        locale.identifier(.bcp47).lowercased()
    }

    private static func isChineseLocale(locale: String) -> Bool {
        let lower = locale.lowercased()
        return Self.chineseLocalePrefixes.contains { lower.hasPrefix($0) }
    }

    private static func languageCode(from localeIdentifier: String) -> String? {
        let normalized = Self.normalizeLocaleID(localeIdentifier)
        guard let first = normalized.split(separator: "-").first else {
            return nil
        }
        return String(first)
    }
}

// MARK: - Buffer Converter (from Apple's sample)

@available(macOS 26.0, *)
private class BufferConverter {
    enum Error: Swift.Error {
        case failedToCreateConverter
        case failedToCreateConversionBuffer
        case conversionFailed(NSError?)
    }

    private var converter: AVAudioConverter?

    func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat != format else {
            return buffer
        }

        if converter == nil || converter?.outputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
            converter?.primeMethod = .none
        }

        guard let converter else {
            throw Error.failedToCreateConverter
        }

        let sampleRateRatio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let scaledInputFrameLength = Double(buffer.frameLength) * sampleRateRatio
        let frameCapacity = AVAudioFrameCount(scaledInputFrameLength.rounded(.up))

        guard let conversionBuffer = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: frameCapacity
        ) else {
            throw Error.failedToCreateConversionBuffer
        }

        var nsError: NSError?
        var bufferProcessed = false

        let status = converter.convert(to: conversionBuffer, error: &nsError) { _, inputStatusPointer in
            defer { bufferProcessed = true }
            inputStatusPointer.pointee = bufferProcessed ? .noDataNow : .haveData
            return bufferProcessed ? nil : buffer
        }

        guard status != .error else {
            throw Error.conversionFailed(nsError)
        }

        return conversionBuffer
    }
}
