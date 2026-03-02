import AVFoundation
import Foundation
import Speech

// MARK: - Apple Speech Provider

/// A TranscriptionProvider that uses Apple's native SFSpeechRecognizer.
/// This runs strictly on-device, requires no downloads, and has 0 memory footprint when idle.
final class AppleSpeechProvider: TranscriptionProvider {
    var name: String { "Apple Speech (Legacy)" }

    /// Always available on macOS 10.15+ (Catalina and later)
    var isAvailable: Bool {
        SFSpeechRecognizer.authorizationStatus() != .restricted
    }

    /// Apple Speech is "always ready" (no downloads needed),
    /// but we track if we've checked permissions.
    private(set) var isReady: Bool = false

    /// The recognizer instance. We intentionally re-create it if the locale changes,
    /// but for now we default to the system locale.
    private var recognizer: SFSpeechRecognizer?

    init() {
        // Initialized lazily when first needed to allow locale fallback discovery.
    }

    // MARK: - Lifecycle

    func prepare(progressHandler: ((Double) -> Void)?) async throws {
        // 1. Request Authorization
        let status = await self.requestAuthorization()

        switch status {
        case .authorized:
            self.isReady = true
            DebugLogger.shared.info("AppleSpeechProvider authorized and ready", source: "AppleSpeechProvider")
        case .denied:
            throw NSError(domain: "AppleSpeechProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognition permission denied"])
        case .restricted:
            throw NSError(domain: "AppleSpeechProvider", code: 2, userInfo: [NSLocalizedDescriptionKey: "Speech recognition is restricted on this device"])
        case .notDetermined:
            // Should not happen after requestAuthorization returns, but handled for safety
            self.isReady = false
        @unknown default:
            self.isReady = false
        }
    }

    func clearCache() async throws {
        // No cache to clear for system speech
    }

    func modelsExistOnDisk() -> Bool {
        return true // System models are always "on disk"
    }

    // MARK: - Transcription

    func transcribe(_ samples: [Float]) async throws -> ASRTranscriptionResult {
        guard self.isAvailable else {
            throw NSError(domain: "AppleSpeechProvider", code: 3, userInfo: [NSLocalizedDescriptionKey: "Speech recognition unavailable"])
        }

        // 1. Convert [Float] samples to AVAudioPCMBuffer
        guard let _ = self.createPCMBuffer(from: samples) else {
            throw NSError(domain: "AppleSpeechProvider", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio buffer"])
        }

        let languageMode = SettingsStore.shared.speechLanguageMode
        let smartDetection = SettingsStore.shared.enableSmartLanguageDetection
        let candidateLocales = Self.localeCandidates(
            for: languageMode.isAutomatic ? Locale.current : nil,
            in: languageMode,
            includeSmartFallback: languageMode.isAutomatic && smartDetection
        )
        if candidateLocales.isEmpty {
            throw NSError(
                domain: "AppleSpeechProvider",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "No speech locale candidates found"]
            )
        }

        if languageMode.isAutomatic, smartDetection, candidateLocales.count > 1 {
            return try await self.transcribeWithFallback(samples: samples, locales: candidateLocales)
        }

        return try await self.transcribeWithLocale(samples: samples, locale: candidateLocales.first!)
    }

    private func transcribeWithFallback(samples: [Float], locales: [Locale]) async throws -> ASRTranscriptionResult {
        var lastError: Error?

        for locale in locales {
            do {
                let result = try await self.transcribeWithLocale(samples: samples, locale: locale)
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return result
                }
            } catch {
                lastError = error
                DebugLogger.shared.warning(
                    "AppleSpeechProvider: locale fallback \(locale.identifier(.bcp47)) failed - \(error.localizedDescription)",
                    source: "AppleSpeechProvider"
                )
            }
        }

        if let lastError {
            throw lastError
        }
        return ASRTranscriptionResult(text: "", confidence: 0.0)
    }

    private func transcribeWithLocale(samples: [Float], locale: Locale) async throws -> ASRTranscriptionResult {
        guard let buffer = self.createPCMBuffer(from: samples) else {
            throw NSError(domain: "AppleSpeechProvider", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio buffer"])
        }

        guard let recognizer = Self.resolveRecognizer(for: locale), recognizer.isAvailable else {
            throw NSError(
                domain: "AppleSpeechProvider",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "SFSpeechRecognizer is unavailable for locale \(locale.identifier(.bcp47))"]
            )
        }

        self.recognizer = recognizer

        // 3. Create Request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false // We want the final result for this chunk
        request.requiresOnDeviceRecognition = true // Enforce strict privacy/offline
        request.append(buffer)
        request.endAudio() // Signal that this buffer is the complete utterance for this request

        // 4. Execute Recognition
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            recognizer.recognitionTask(with: request) { result, error in
                // Ensure we only resume once
                guard !hasResumed else { return }

                if let error = error {
                    hasResumed = true
                    // Ignore "No speech detected" errors often returned for silent chunks
                    DebugLogger.shared.warning("Apple transcribed error: \(error.localizedDescription)", source: "AppleSpeechProvider")
                    continuation.resume(returning: ASRTranscriptionResult(text: "", confidence: 0.0))
                    return
                }

                if let result = result, result.isFinal {
                    hasResumed = true
                    let transcription = result.bestTranscription.formattedString
                    DebugLogger.shared.debug("AppleSpeechProvider: Got final result: '\(transcription)'", source: "AppleSpeechProvider")
                    continuation.resume(returning: ASRTranscriptionResult(text: transcription, confidence: 1.0))
                }
                // Partial results ignored as we requested final only
            }
        }
    }

    // MARK: - Helpers

    /// Converts raw [Float] samples (16kHz mono) to AVAudioPCMBuffer
    private func createPCMBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        // Define format: 16kHz, Mono, Float32 (standard for ML/ASR)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false) else {
            return nil
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)

        // Efficient copy
        guard let channelData = buffer.floatChannelData else { return nil }

        // Use withUnsafeBufferPointer for safe memory access
        samples.withUnsafeBufferPointer { samplePtr in
            guard let baseAddress = samplePtr.baseAddress else { return }
            // Copy memory from array to AVAudioPCMBuffer
            // channelData[0] is UnsafeMutablePointer<Float>
            channelData[0].update(from: baseAddress, count: samples.count)
        }

        return buffer
    }

    private static let smartLanguageFallbackLocaleIdentifiers: [String] = [
        "en-US",
        "en-GB",
        "en",
        "zh-Hans",
        "zh-Hans-CN",
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

    private static func resolveRecognizer(for locale: Locale) -> SFSpeechRecognizer? {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            return nil
        }
        DebugLogger.shared.info("AppleSpeechProvider: Using locale \(locale.identifier(.bcp47))", source: "AppleSpeechProvider")
        return recognizer
    }

    private static func localeCandidates(
        for locale: Locale?,
        in languageMode: SettingsStore.SpeechLanguageMode,
        includeSmartFallback: Bool
    ) -> [Locale] {
        var ids: [String] = []
        if languageMode.isAutomatic {
            if let locale {
                ids.append(locale.identifier(.bcp47))
                ids.append(locale.identifier)
                ids.append(contentsOf: Locale.preferredLanguages)

                if let languageCode = languageCode(from: locale.identifier) {
                    ids.append(languageCode)
                }
                if isChineseLocale(locale: locale.identifier) {
                    ids.append("zh-Hans")
                    ids.append("zh-Hans-CN")
                    ids.append("zh-Hant")
                    ids.append("zh-Hant-TW")
                    ids.append("zh")
                }
            }
            if includeSmartFallback {
                ids.append(contentsOf: smartLanguageFallbackLocaleIdentifiers)
            }
        } else {
            ids = languageMode.localeCandidates
        }

        var orderedIDs: [String] = []
        var seen: Set<String> = []
        for raw in ids {
            let normalized = normalizeLocaleID(raw)
            guard !normalized.isEmpty else { continue }
            if !seen.contains(normalized) {
                seen.insert(normalized)
                orderedIDs.append(normalized)
            }
        }

        return orderedIDs.compactMap { Locale(identifier: $0) }
    }

    private static func localeCandidates(for locale: Locale?, in languageMode: SettingsStore.SpeechLanguageMode) -> [Locale] {
        Self.localeCandidates(for: locale, in: languageMode, includeSmartFallback: false)
    }

    private static func normalizeLocaleID(_ rawID: String) -> String {
        rawID.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private static func languageCode(from localeIdentifier: String) -> String? {
        let normalized = normalizeLocaleID(localeIdentifier)
        guard let first = normalized.split(separator: "-").first else {
            return nil
        }
        return String(first)
    }

    private static func isChineseLocale(locale: String) -> Bool {
        let lower = locale.lowercased()
        let chinesePrefixes = ["zh", "zho", "zh-hans", "zh-hant", "zh-cn", "zh-tw"]
        return chinesePrefixes.contains { lower.hasPrefix($0) }
    }

    /// Structured concurrency wrapper for authorization
    private func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
