import AppKit
import SwiftUI
import XCTest

@testable import SayIt

/// Visual evidence for the Live Captions panel (DESIGN.md §15): every state, rendered from
/// fixtures so no audio, permission or model is involved.
@MainActor
final class LiveCaptionSnapshotTests: XCTestCase {
    private static let size = CGSize(width: 660, height: 200)

    private static func row(
        _ id: String,
        _ text: String,
        from source: LiveCaptionSource = .macAudio,
        draft: Bool = false,
        forming: String = ""
    ) -> LiveCaptionViewState.Row {
        LiveCaptionViewState.Row(id: id, source: source, text: text, formingTail: forming, isDraft: draft, isRefined: !draft)
    }

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
    ]

    override func setUp() async throws {
        try await super.setUp()
        guard SnapshotRenderer.outputDirectory != nil else {
            throw XCTSkip("Set SAYIT_SNAPSHOT_DIR to write UI snapshots")
        }
    }

    func testLiveCaptionStates() throws {
        for (name, state) in Self.states {
            try SnapshotRenderer.snapshot("live-captions-\(name)", size: Self.size, overlay: true) {
                LiveCaptionContent(state: state)
            }
        }
    }
}
