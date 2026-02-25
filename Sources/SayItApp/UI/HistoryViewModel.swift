import AVFoundation
import Foundation
import SayItCore

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var sessions: [SessionSummary] = []
    @Published var selectedSessionID: UUID?
    @Published var selectedSegments: [TranscriptSegment] = []
    @Published var audioAssets: [AudioAssetRecord] = []
    @Published var selectedAudioAssetID: UUID?
    @Published var isPlayingAudio: Bool = false
    @Published var searchQuery: String = ""
    @Published var searchResults: [TranscriptSegment] = []
    @Published var status: String = ""

    private let runtime: SayItCoreRuntime?
    private var audioPlayer: AVAudioPlayer?
    private var playbackMonitorTask: Task<Void, Never>?

    var selectedAudioAsset: AudioAssetRecord? {
        guard let selectedAudioAssetID else { return nil }
        return audioAssets.first(where: { $0.id == selectedAudioAssetID })
    }

    var hasSelectedAudioAsset: Bool {
        selectedAudioAsset != nil
    }

    var selectedAudioAssetPath: String {
        selectedAudioAsset?.path ?? "-"
    }

    init(runtime: SayItCoreRuntime?) {
        self.runtime = runtime
    }

    func refresh() {
        guard let runtime else {
            status = "History unavailable"
            return
        }

        do {
            sessions = try runtime.historyRepository.listSessionSummaries(limit: 200)
            if selectedSessionID == nil {
                selectedSessionID = sessions.first?.session.id
            }
            if let selectedSessionID {
                selectedSegments = try runtime.historyRepository.listSegments(sessionID: selectedSessionID)
                loadAudioAssets(sessionID: selectedSessionID)
            } else {
                selectedSegments = []
                audioAssets = []
                selectedAudioAssetID = nil
            }
            status = "Loaded \(sessions.count) sessions"
        } catch {
            status = "History error: \(error.localizedDescription)"
        }
    }

    func selectSession(_ id: UUID) {
        selectedSessionID = id
        guard let runtime else { return }
        do {
            selectedSegments = try runtime.historyRepository.listSegments(sessionID: id)
            loadAudioAssets(sessionID: id)
            status = "Loaded \(selectedSegments.count) segments"
        } catch {
            status = "Load error: \(error.localizedDescription)"
        }
    }

    func search() {
        guard let runtime else { return }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        do {
            searchResults = try runtime.historyRepository.searchSegments(query: query, limit: 100)
            status = "Search result: \(searchResults.count)"
        } catch {
            status = "Search error: \(error.localizedDescription)"
        }
    }

    func exportSelected(format: ExportFormat, outputURL: URL?) async {
        guard let runtime, let selectedSessionID else {
            status = "No session selected"
            return
        }

        do {
            let output: URL
            if let outputURL {
                output = outputURL
            } else {
                let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                    ?? FileManager.default.temporaryDirectory
                output = downloads.appendingPathComponent("sayit-\(selectedSessionID.uuidString).\(format.rawValue)")
            }
            let record = try await runtime.exportService.export(sessionID: selectedSessionID, format: format, to: output)
            status = "Exported: \(record.path)"
        } catch {
            status = "Export error: \(error.localizedDescription)"
        }
    }

    func playSelectedAudio() {
        guard let asset = selectedAudioAsset else {
            status = "No audio asset selected"
            return
        }

        let url = URL(fileURLWithPath: asset.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            status = "Audio file missing"
            return
        }

        stopAudioPlayback()

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            guard player.play() else {
                status = "Failed to play audio"
                return
            }
            audioPlayer = player
            isPlayingAudio = true
            status = "Playing \(asset.fileName)"
            monitorAudioPlayback()
        } catch {
            status = "Audio playback error: \(error.localizedDescription)"
        }
    }

    func stopAudioPlayback() {
        playbackMonitorTask?.cancel()
        playbackMonitorTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingAudio = false
    }

    func retranscribeSelectedAudio() async {
        guard let runtime else {
            status = "History unavailable"
            return
        }
        guard let asset = selectedAudioAsset else {
            status = "No audio asset selected"
            return
        }

        let inputURL = URL(fileURLWithPath: asset.path)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            status = "Audio file missing"
            return
        }

        do {
            let config = try runtime.configManager.load()
            let primary = runtime.sttProvider(for: config.stt.primary)
            let fallbackID = config.fallbackPolicy.localFallback.isEmpty ? config.stt.localDefault : config.fallbackPolicy.localFallback
            let localFallback = runtime.sttProvider(for: fallbackID)
            let stateMachine = FallbackStateMachine(policy: config.fallbackPolicy)
            let pipelineExecutor = PipelineExecutor(refineProvider: runtime.refineProvider(for: config.refine.primary))
            let pipeline = resolveDefaultPipeline(runtime: runtime, config: config)

            let session = TranscriptSession(source: "app_retranscribe", locale: config.locale)
            try runtime.historyRepository.createSession(session)
            defer { try? runtime.historyRepository.finishSession(id: session.id) }

            let copiedAsset = try runtime.audioAssetStore.importFile(inputURL, sessionID: session.id)
            try runtime.historyRepository.saveAudioAsset(copiedAsset)
            let workingURL = URL(fileURLWithPath: copiedAsset.path)

            status = "Retranscribing audio"
            let (segments, fallbackEvent) = try await stateMachine.execute(
                primaryProvider: primary.id,
                fallbackProvider: localFallback.id,
                operation: {
                    try await primary.transcribeFile(url: workingURL, config: STTFileConfig(locale: config.locale))
                },
                fallback: {
                    try await localFallback.transcribeFile(url: workingURL, config: STTFileConfig(locale: config.locale))
                }
            )

            if let fallbackEvent {
                try runtime.historyRepository.saveFallbackEvent(fallbackEvent)
            }

            for (index, raw) in segments.enumerated() {
                var segment = raw
                segment.sessionID = session.id
                segment.sequence = index
                var pipelineRuns: [PipelineRunRecord] = []
                if let pipeline {
                    let (text, runs) = try await pipelineExecutor.run(
                        text: segment.finalText,
                        pipeline: pipeline,
                        sessionID: session.id,
                        segmentID: segment.id,
                        locale: config.locale
                    )
                    segment.finalText = text
                    pipelineRuns = runs
                }
                try runtime.historyRepository.addSegment(segment)
                for run in pipelineRuns {
                    do {
                        try runtime.historyRepository.savePipelineRun(run)
                    } catch {
                        status = "Pipeline run skipped: \(error.localizedDescription)"
                    }
                }
            }

            refresh()
            selectedSessionID = session.id
            selectSession(session.id)
            status = "Retranscribe complete"
        } catch {
            status = "Retranscribe error: \(error.localizedDescription)"
        }
    }

    func deleteSelectedAudioAsset() {
        guard let runtime else {
            status = "History unavailable"
            return
        }
        guard let asset = selectedAudioAsset else {
            status = "No audio asset selected"
            return
        }

        stopAudioPlayback()

        do {
            try runtime.historyRepository.deleteAudioAsset(id: asset.id)
            deleteFileIfExists(at: asset.path)
            audioAssets.removeAll { $0.id == asset.id }
            if !audioAssets.contains(where: { $0.id == selectedAudioAssetID }) {
                selectedAudioAssetID = audioAssets.first?.id
            }
            status = "Audio asset deleted"
        } catch {
            status = "Delete audio failed: \(error.localizedDescription)"
        }
    }

    func deleteSelectedSession() {
        guard let runtime else {
            status = "History unavailable"
            return
        }
        guard let sessionID = selectedSessionID else {
            status = "No session selected"
            return
        }

        stopAudioPlayback()

        do {
            let assets = try runtime.historyRepository.listAudioAssets(sessionID: sessionID)
            try runtime.historyRepository.deleteSession(id: sessionID)
            for asset in assets {
                deleteFileIfExists(at: asset.path)
            }

            sessions.removeAll { $0.id == sessionID }
            selectedSessionID = sessions.first?.id
            if let next = selectedSessionID {
                selectedSegments = try runtime.historyRepository.listSegments(sessionID: next)
                loadAudioAssets(sessionID: next)
            } else {
                selectedSegments = []
                audioAssets = []
                selectedAudioAssetID = nil
            }
            status = "Session deleted"
        } catch {
            status = "Delete session failed: \(error.localizedDescription)"
        }
    }

    func durationText(for asset: AudioAssetRecord) -> String {
        guard asset.durationMs > 0 else { return "-" }
        let totalSeconds = asset.durationMs / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func loadAudioAssets(sessionID: UUID) {
        guard let runtime else { return }
        do {
            audioAssets = try runtime.historyRepository.listAudioAssets(sessionID: sessionID)
            if let selectedAudioAssetID, audioAssets.contains(where: { $0.id == selectedAudioAssetID }) {
                // keep current selection
            } else {
                selectedAudioAssetID = audioAssets.first?.id
            }
        } catch {
            audioAssets = []
            selectedAudioAssetID = nil
            status = "Audio asset load error: \(error.localizedDescription)"
        }
    }

    private func resolveDefaultPipeline(runtime: SayItCoreRuntime, config: AppConfig) -> TextPipeline? {
        let pipelines = (try? runtime.pipelineStore.load()) ?? DefaultPipelines.all()
        guard !pipelines.isEmpty else { return nil }
        if let id = config.pipeline.defaultID, let selected = pipelines.first(where: { $0.id == id }) {
            return selected
        }
        return pipelines.first
    }

    private func monitorAudioPlayback() {
        playbackMonitorTask?.cancel()
        playbackMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                await MainActor.run {
                    guard let self else { return }
                    if self.audioPlayer?.isPlaying != true {
                        self.isPlayingAudio = false
                        self.playbackMonitorTask?.cancel()
                        self.playbackMonitorTask = nil
                    }
                }
            }
        }
    }

    private func deleteFileIfExists(at path: String) {
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
