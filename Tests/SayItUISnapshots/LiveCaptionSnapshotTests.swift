import AppKit
import SwiftUI
import XCTest

@testable import SayIt

/// Visual evidence for the Live Captions panel (DESIGN.md §15): every state, rendered from
/// fixtures so no audio, permission or model is involved.
@MainActor
final class LiveCaptionSnapshotTests: XCTestCase {
    private static let size = LiveCaptionLayout.defaultSize
    private static let translatingSize = CGSize(width: LiveCaptionLayout.translatingWidth, height: LiveCaptionLayout.defaultSize.height)
    private static let narrowSize = CGSize(width: LiveCaptionLayout.minimumSize.width, height: LiveCaptionLayout.defaultSize.height)
    private static let tallSize = CGSize(width: LiveCaptionLayout.defaultSize.width, height: 360)

    private static func row(
        _ id: String,
        _ text: String,
        from source: LiveCaptionSource = .macAudio,
        speaker: Int? = nil,
        draft: Bool = false,
        forming: String = "",
        translation: String? = nil
    ) -> LiveCaptionViewState.Row {
        LiveCaptionViewState.Row(
            id: id,
            source: source,
            text: text,
            formingTail: forming,
            isDraft: draft,
            isRefined: !draft,
            speaker: speaker,
            translation: translation
        )
    }

    private static let japaneseConversation: [LiveCaptionViewState.Row] = [
        row("a", "今日はリリースの話をしましょう。", speaker: 1, translation: "今天我们来聊聊发布的事。"),
        row("b", "テストは全部通りましたか？", speaker: 2, translation: "测试全部通过了吗？"),
        row("c", "はい、昨日の夜に全部終わりました。", speaker: 1, translation: "是的，昨天晚上全部完成了。"),
        row("d", "じゃあ、来週の月曜日に出しましょう", speaker: 2, draft: true, forming: "か"),
    ]

    private static let states: [(String, LiveCaptionViewState)] = [
        ("1-preparing", LiveCaptionViewState(phase: .preparing)),
        ("2-listening", LiveCaptionViewState(phase: .listening)),
        ("3-captions", LiveCaptionViewState(
            phase: .listening,
            rows: [
                row("a", "We shipped the new onboarding last week."),
                row("b", "请帮我 review 这个 pull request，然后 deploy 到 staging。"),
                row("c", "Also mention the release notes", draft: true),
                row("d", "for version 2.4", draft: true, forming: " and the migration guide"),
            ]
        )),
        ("4-long-line", LiveCaptionViewState(
            phase: .listening,
            rows: [
                row("a", "这次更新主要解决了两个问题：第一是长时间闲置之后转写变慢，第二是第一次转写需要等待模型编译，现在都会在你开始说话时提前处理好。"),
            ]
        )),
        ("5-silence-hint", LiveCaptionViewState(phase: .listening, showsSilenceHint: true)),
        ("6-cant-hear-mac", LiveCaptionViewState(phase: .failed(.cantHearMac))),
        ("7-speech-unavailable", LiveCaptionViewState(phase: .failed(.speechUnavailable))),
        ("8-microphone-listening", LiveCaptionViewState(phase: .listening, microphone: .on)),
        ("9-microphone-conversation", LiveCaptionViewState(
            phase: .listening,
            rows: [
                row("a", "So when does the migration guide go out?"),
                row("b", "下周一发，我今天先把初稿写好。", from: .microphone),
                row("c", "Great, send it to me when it's ready.", draft: true),
                row("d", "", from: .microphone, draft: true, forming: "好的，没问题"),
            ],
            microphone: .on
        )),
        ("10-microphone-unavailable", LiveCaptionViewState(
            phase: .listening,
            rows: [row("a", "We shipped the new onboarding last week.")],
            microphone: .unavailable
        )),
        ("11-speakers", LiveCaptionViewState(
            phase: .listening,
            rows: [
                row("a", "The build passed this morning.", speaker: 2),
                row("b", "Great. Did we fix the slow first transcription?", speaker: 1),
                row("c", "Yes, the model now warms up while you speak,", speaker: 2),
                row("d", "so the first one is as fast as the rest.", speaker: 2, draft: true),
            ],
            speakers: .on
        )),
        ("12-speakers-and-microphone", LiveCaptionViewState(
            phase: .listening,
            rows: [
                row("a", "Did we fix the slow first transcription?", speaker: 1),
                row("b", "修好了，现在开始说话时就会预热。", from: .microphone),
                row("c", "Nice. Can you share the numbers?", speaker: 2),
                row("d", "", from: .microphone, draft: true, forming: "Sure, I'll post them"),
            ],
            microphone: .on,
            speakers: .on
        )),
        ("13-speakers-preparing", LiveCaptionViewState(
            phase: .listening,
            rows: [row("a", "We shipped the new onboarding last week.")],
            speakers: .preparing
        )),
        ("14-speakers-unavailable", LiveCaptionViewState(
            phase: .listening,
            rows: [row("a", "We shipped the new onboarding last week.")],
            speakers: .unavailable
        )),
        ("19-changing-language", LiveCaptionViewState(
            phase: .listening,
            rows: [row("a", "We shipped the new onboarding last week.")],
            language: .japanese,
            isChangingLanguage: true
        )),
        ("20-transcript-not-saved", LiveCaptionViewState(
            phase: .listening,
            rows: [row("a", "We shipped the new onboarding last week.")],
            transcriptSaveFailed: true
        )),
    ]

    /// States that need a different panel size: translation (wide), a narrow panel, and a
    /// tall one reading back.
    private static let sizedStates: [(String, CGSize, LiveCaptionViewState)] = [
        ("15-translation", translatingSize, LiveCaptionViewState(
            phase: .listening,
            rows: japaneseConversation,
            speakers: .on,
            language: .japanese,
            translation: .init(target: .chinese, status: .ready)
        )),
        ("16-translation-with-microphone", translatingSize, LiveCaptionViewState(
            phase: .listening,
            rows: [
                row("a", "テストは全部通りましたか？", translation: "测试全部通过了吗？"),
                row("b", "全部通りました。", from: .microphone, translation: "全部通过了。"),
                row("c", "じゃあ、来週出しましょう。", translation: nil),
                row("d", "", from: .microphone, draft: true, forming: "そうしましょう"),
            ],
            microphone: .on,
            language: .japanese,
            translation: .init(target: .chinese, status: .ready)
        )),
        ("17-translation-needs-download", size, LiveCaptionViewState(
            phase: .listening,
            rows: [row("a", "今日はリリースの話をしましょう。")],
            language: .japanese,
            translation: .init(target: .chinese, status: .needsDownload)
        )),
        ("18-translation-unsupported", size, LiveCaptionViewState(
            phase: .listening,
            rows: [row("a", "Vamos falar sobre o lançamento.")],
            language: .portuguese,
            translation: .init(target: .korean, status: .unsupported)
        )),
        ("21-narrow", narrowSize, LiveCaptionViewState(
            phase: .listening,
            rows: [
                row("a", "So when does the migration guide go out?"),
                row("b", "下周一发，我今天先把初稿写好。", from: .microphone),
            ],
            microphone: .on,
            speakers: .on,
            language: .english,
            translation: .init(target: .chinese, status: .preparing)
        )),
        ("22-tall-scrollback", tallSize, LiveCaptionViewState(
            phase: .listening,
            rows: (1...14).map { index in
                row("\(index)", "Line \(index): the panel keeps every line, so you can scroll back to read what was said.")
            },
            language: .english
        )),
    ]

    override func setUp() async throws {
        try await super.setUp()
        guard SnapshotRenderer.outputDirectory != nil else {
            throw XCTSkip("Set SAYIT_SNAPSHOT_DIR to write UI snapshots")
        }
    }

    func testLiveCaptionStates() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Live Captions need macOS 26") }
        let all = Self.states.map { ($0.0, Self.size, $0.1) } + Self.sizedStates
        for (name, size, state) in all {
            try SnapshotRenderer.snapshot("live-captions-\(name)", size: size, overlay: true) {
                LiveCaptionContent(state: state)
            }
        }
    }
}
