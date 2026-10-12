import Foundation
import Translation

/// Translates settled caption lines on this Mac with macOS Translation, one at a time.
@available(macOS 26.0, *)
@MainActor
final class LiveCaptionTranslator {
    enum Readiness: Equatable {
        case ready
        /// macOS can translate this pair once its languages are downloaded.
        case needsDownload
        case unsupported
    }

    let source: LiveCaptionLanguage
    let target: LiveCaptionLanguage
    private let session: TranslationSession
    private var last: Task<Void, Never>?

    init(from source: LiveCaptionLanguage, to target: LiveCaptionLanguage) {
        self.source = source
        self.target = target
        self.session = TranslationSession(installedSource: source.translationLanguage, target: target.translationLanguage)
    }

    static func readiness(from source: LiveCaptionLanguage, to target: LiveCaptionLanguage) async -> Readiness {
        let status = await LanguageAvailability().status(from: source.translationLanguage, to: target.translationLanguage)
        switch status {
        case .installed: return .ready
        case .supported: return .needsDownload
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }

    /// Translates `text` after the lines queued before it; calls back with nil on failure.
    func translate(_ text: String, completion: @escaping (String?) -> Void) {
        let previous = self.last
        let session = self.session
        self.last = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            do {
                let response = try await session.translate(text)
                completion(response.targetText)
            } catch {
                DebugLogger.shared.warning("Live Captions: translation failed: \(error.localizedDescription)", source: "LiveCaptions")
                completion(nil)
            }
        }
    }

    func cancel() {
        self.last?.cancel()
        self.session.cancel()
    }
}
