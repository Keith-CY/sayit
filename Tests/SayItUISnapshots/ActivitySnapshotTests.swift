import SwiftUI
import XCTest

@testable import SayIt

/// Activity & Tools pages: Stats, History, File Transcription, Help & Feedback,
/// Command Mode and Edit Mode. Uses in-memory data only — never the user's history,
/// chats or settings.
@MainActor
final class ActivitySnapshotTests: XCTestCase {
    private static let pageSize = CGSize(width: 760, height: 980)

    // MARK: - Stats

    func testStatsPopulated() throws {
        let store = TranscriptionHistoryStore(inMemoryEntries: SampleData.historyEntries())
        try SnapshotRenderer.snapshot("activity-stats", size: CGSize(width: 760, height: 1180)) {
            StatsView(historyStore: store)
        }
    }

    func testStatsEmpty() throws {
        let store = TranscriptionHistoryStore(inMemoryEntries: [])
        try SnapshotRenderer.snapshot("activity-stats-empty", size: CGSize(width: 760, height: 420)) {
            StatsView(historyStore: store)
        }
    }

    // MARK: - History

    func testHistoryPopulated() throws {
        let store = TranscriptionHistoryStore(inMemoryEntries: SampleData.historyEntries())
        try SnapshotRenderer.snapshot("activity-history", size: CGSize(width: 820, height: 600)) {
            TranscriptionHistoryView(historyStore: store)
        }
    }

    func testHistoryAtMinimumWidth() throws {
        let store = TranscriptionHistoryStore(inMemoryEntries: SampleData.historyEntries())
        try SnapshotRenderer.snapshot("activity-history-narrow", size: CGSize(width: 580, height: 560), appearances: [.dark]) {
            TranscriptionHistoryView(historyStore: store)
        }
    }

    func testHistoryEmpty() throws {
        let store = TranscriptionHistoryStore(inMemoryEntries: [])
        try SnapshotRenderer.snapshot("activity-history-empty", size: CGSize(width: 820, height: 480)) {
            TranscriptionHistoryView(historyStore: store)
        }
    }

    // MARK: - File Transcription

    func testFileTranscriptionEmpty() throws {
        let asr = AppServices.shared.asr
        try SnapshotRenderer.snapshot("activity-file-empty", size: CGSize(width: 760, height: 460)) {
            MeetingTranscriptionView(asrService: asr, service: MeetingTranscriptionService(asrService: asr), selectedFileURL: nil)
        }
    }

    func testFileTranscriptionInProgress() throws {
        let asr = AppServices.shared.asr
        let service = MeetingTranscriptionService(asrService: asr)
        service.isTranscribing = true
        service.progress = 0.42
        service.currentStatus = "Transcribing… 42%"
        try SnapshotRenderer.snapshot("activity-file-progress", size: CGSize(width: 760, height: 380)) {
            MeetingTranscriptionView(asrService: asr, service: service, selectedFileURL: SampleData.audioFileURL)
        }
    }

    func testFileTranscriptionResultAndError() throws {
        let asr = AppServices.shared.asr
        let service = MeetingTranscriptionService(asrService: asr)
        service.result = TranscriptionResult(
            text: SampleData.longTranscript,
            confidence: 0.93,
            duration: 312,
            processingTime: 22,
            fileName: "Design review.m4a"
        )
        try SnapshotRenderer.snapshot("activity-file-result", size: CGSize(width: 760, height: 760)) {
            MeetingTranscriptionView(asrService: asr, service: service, selectedFileURL: SampleData.audioFileURL)
        }

        let failing = MeetingTranscriptionService(asrService: asr)
        failing.error = MeetingTranscriptionService.TranscriptionError
            .fileNotSupported("Use one of: WAV, MP3, M4A, AAC, FLAC, AIFF, CAF, MP4, MOV.")
            .localizedDescription
        try SnapshotRenderer.snapshot("activity-file-error", size: CGSize(width: 760, height: 420), appearances: [.light]) {
            MeetingTranscriptionView(asrService: asr, service: failing, selectedFileURL: SampleData.audioFileURL)
        }
    }

    // MARK: - Help & Feedback

    func testHelpAndFeedback() throws {
        try SnapshotRenderer.snapshot("activity-help", size: CGSize(width: 760, height: 1180)) {
            FeedbackView()
        }
    }

    // MARK: - Command Mode

    func testCommandModeEmpty() throws {
        try SnapshotRenderer.snapshot("activity-command-empty", size: CGSize(width: 760, height: 620)) {
            PageBackground {
                CommandConversationView(
                    messages: [],
                    isProcessing: false,
                    stepLabel: "",
                    streamingText: "",
                    thinkingText: "",
                    showThinking: false,
                    shortcut: "⌃⌥C"
                )
            }
        }
    }

    func testCommandModeConversation() throws {
        try SnapshotRenderer.snapshot("activity-command-chat", size: CGSize(width: 760, height: 860)) {
            PageBackground {
                VStack(spacing: 0) {
                    CommandConversationView(
                        messages: SampleData.commandMessages,
                        isProcessing: true,
                        stepLabel: CommandModeView.stepLabel(for: .executing("du -sh ~/Downloads")),
                        streamingText: "",
                        thinkingText: "The user wants the size of their Downloads folder. du -sh reports a single total.",
                        showThinking: true,
                        shortcut: nil
                    )
                    CommandConfirmationCard(
                        command: "rm -rf ~/Downloads/old-builds",
                        purpose: "Delete the old build folder to free up space",
                        onCancel: {},
                        onRun: {}
                    )
                }
            }
        }
    }
}

// MARK: - Sample Data

@MainActor
private enum SampleData {
    static let longTranscript = """
    Thanks everyone for joining. The goal today is to agree on the onboarding flow. \
    We tested three versions last week, and the one that asks for microphone access first, \
    with a single sentence explaining why, had the fewest drop-offs. 请帮我把这个结论写进 review 文档, \
    then we can deploy the change to staging on Thursday. Next, the overlay: people told us they \
    couldn't tell whether their text had been inserted, so the done state needs to stay on screen \
    for about a second.
    """

    static var audioFileURL: URL {
        Bundle(for: ActivitySnapshotTests.self).url(forResource: "dictation_fixture", withExtension: "wav")
            ?? URL(fileURLWithPath: "/tmp/Design review.m4a")
    }

    private struct Sample {
        let daysAgo: Int
        let hour: Int
        let raw: String
        let final: String
        let app: String
        let window: String
    }

    static func historyEntries() -> [TranscriptionHistoryEntry] {
        let calendar = Calendar.current
        let now = Date()
        let samples = [
            Sample(daysAgo: 0, hour: 10, raw: "请帮我 review 这个 pull request 然后 deploy 到 staging", final: "请帮我 review 这个 pull request，然后 deploy 到 staging。", app: "Slack", window: "#release"),
            Sample(
                daysAgo: 0,
                hour: 9,
                raw: "Morning team quick update the onboarding test results are in and they look good",
                final: "Morning, team — quick update: the onboarding test results are in, and they look good.",
                app: "Mail",
                window: "Onboarding results"
            ),
            Sample(
                daysAgo: 1,
                hour: 16,
                raw: "Let’s move the design review to Thursday afternoon if that works for everyone",
                final: "Let’s move the design review to Thursday afternoon if that works for everyone.",
                app: "Calendar",
                window: "Design review"
            ),
            Sample(daysAgo: 1, hour: 11, raw: "TODO check the notch overlay on external displays", final: "TODO: check the notch overlay on external displays.", app: "Xcode", window: "NotchOverlayManager.swift"),
            Sample(daysAgo: 2, hour: 14, raw: "Summary of the call we agreed to ship the history redesign first", final: "Summary of the call: we agreed to ship the history redesign first.", app: "Notes", window: "Weekly sync"),
            Sample(daysAgo: 3, hour: 15, raw: "Can you send me the deck before tomorrow", final: "Can you send me the deck before tomorrow?", app: "Messages", window: "Alex"),
            Sample(daysAgo: 5, hour: 10, raw: "The build is green on main", final: "The build is green on main.", app: "Slack", window: "#ci"),
            Sample(daysAgo: 6, hour: 17, raw: "Remember to update the README with the new shortcuts", final: "Remember to update the README with the new shortcuts.", app: "Notes", window: "Release checklist"),
        ]
        return samples.map { sample in
            let day = calendar.date(byAdding: .day, value: -sample.daysAgo, to: now) ?? now
            let timestamp = calendar.date(bySettingHour: sample.hour, minute: 12, second: 0, of: day) ?? day
            return TranscriptionHistoryEntry(
                timestamp: timestamp,
                rawText: sample.raw,
                processedText: sample.final,
                appName: sample.app,
                windowTitle: sample.window
            )
        }
        .sorted { $0.timestamp > $1.timestamp }
    }

    static var commandMessages: [CommandModeService.Message] {
        [
            CommandModeService.Message(role: .user, content: "How big is my Downloads folder?"),
            CommandModeService.Message(
                role: .assistant,
                content: "",
                toolCall: .init(id: "1", command: "du -sh ~/Downloads", workingDirectory: nil, purpose: "Measure the Downloads folder")
            ),
            CommandModeService.Message(
                role: .tool,
                content: #"{"success": true, "output": "12G\t/Users/me/Downloads", "exitCode": 0, "executionTimeMs": 840}"#
            ),
            CommandModeService.Message(role: .assistant, content: "Your Downloads folder uses **12 GB**."),
            CommandModeService.Message(role: .user, content: "Open the folder called Archive in it"),
            CommandModeService.Message(
                role: .tool,
                content: #"{"success": false, "output": "", "error": "The file /Users/me/Downloads/Archive does not exist.", "exitCode": 1, "executionTimeMs": 35}"#
            ),
        ]
    }
}

/// Paints the page background that the real container provides around presentational views.
private struct PageBackground<Content: View>: View {
    @Environment(\.theme) private var theme
    @ViewBuilder let content: Content

    var body: some View {
        self.content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(self.theme.palette.contentBackground)
    }
}
