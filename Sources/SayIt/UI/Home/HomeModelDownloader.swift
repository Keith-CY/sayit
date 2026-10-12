import Combine
import Foundation

/// Downloads the active speech model from Home with progress, cancel and retry.
///
/// Uses the same `ASRService.downloadModel` path as Voice Engine, then prepares the
/// model if it is the active one.
@MainActor
final class HomeModelDownloader: ObservableObject {
    enum Phase: Equatable {
        case idle
        case downloading(fraction: Double)
        case failed(String)
        case cancelled
    }

    @Published private(set) var phase: Phase = .idle
    private(set) var modelID: String?
    private var task: Task<Void, Never>?

    func start(_ model: SettingsStore.SpeechModel, asr: ASRService) {
        guard self.task == nil, !asr.isRunning else { return }
        self.modelID = model.id
        self.phase = .downloading(fraction: 0)

        let modelID = model.id
        self.task = Task { [weak self] in
            do {
                try await asr.downloadModel(model, progressHandler: { progress in
                    Task { @MainActor in
                        self?.updateProgress(progress, for: modelID)
                    }
                })
                try Task.checkCancellation()
                if SettingsStore.shared.selectedSpeechModel == model {
                    asr.resetTranscriptionProvider()
                    try await asr.ensureAsrReady()
                }
                await asr.checkIfModelsExistAsync()
                self?.finish(.idle)
            } catch is CancellationError {
                self?.finish(.cancelled)
            } catch {
                DebugLogger.shared.error("Home model download failed: \(error.localizedDescription)", source: "HomeModelDownloader")
                if Task.isCancelled {
                    self?.finish(.cancelled)
                } else {
                    self?.finish(.failed(error.localizedDescription))
                }
            }
        }
    }

    func cancel() {
        guard let task else { return }
        task.cancel()
        self.task = nil
        self.phase = .cancelled
    }

    private func updateProgress(_ fraction: Double, for modelID: String) {
        guard self.modelID == modelID, case .downloading = self.phase else { return }
        self.phase = .downloading(fraction: fraction)
    }

    private func finish(_ phase: Phase) {
        // A cancel already moved the UI on; don't overwrite it with a late result.
        guard self.task != nil else { return }
        self.task = nil
        self.phase = phase
    }
}
