import AppKit
import SwiftUI
import XCTest

@testable import SayIt

/// Visual evidence for the Live Captions panel (DESIGN.md §15): every state, rendered from
/// fixtures so no audio, permission or model is involved.
@MainActor
final class LiveCaptionSnapshotTests: XCTestCase {
    private static let size = CGSize(width: 660, height: 200)

    private static func line(
        _ id: Int,
        _ text: String,
        _ state: LiveCaptionTranscript.Line.State
    ) -> LiveCaptionTranscript.Line {
        LiveCaptionTranscript.Line(id: id, text: text, start: Double(id) * 4, end: Double(id) * 4 + 3.5, state: state)
    }

    private static let states: [(String, LiveCaptionViewState)] = [
        ("1-preparing", LiveCaptionViewState(phase: .preparing)),
        ("2-listening", LiveCaptionViewState(phase: .listening)),
        ("3-captions", LiveCaptionViewState(
            phase: .listening,
            lines: [
                line(0, "We shipped the new onboarding last week.", .refined),
                line(1, "请帮我 review 这个 pull request，然后 deploy 到 staging。", .refined),
                line(2, "Also mention the release notes", .awaitingRefinement),
                line(3, "for version 2.4", .open),
            ],
            volatileText: "and the migration guide"
        )),
        ("4-long-line", LiveCaptionViewState(
            phase: .listening,
            lines: [
                line(0, "这次更新主要解决了两个问题：第一是长时间闲置之后转写变慢，第二是第一次转写需要等待模型编译，现在都会在你开始说话时提前处理好。", .refined),
            ],
            volatileText: ""
        )),
        ("5-silence-hint", LiveCaptionViewState(phase: .listening, showsSilenceHint: true)),
        ("6-cant-hear-mac", LiveCaptionViewState(phase: .failed(.cantHearMac))),
        ("7-speech-unavailable", LiveCaptionViewState(phase: .failed(.speechUnavailable))),
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
