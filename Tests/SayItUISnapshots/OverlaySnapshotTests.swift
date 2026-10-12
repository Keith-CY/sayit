import AppKit
import SwiftUI
import XCTest

@testable import SayIt

/// Visual evidence for the recording overlay (DESIGN.md §7–§8): every phase in the notch
/// and bottom styles, all bottom sizes, the pop-up menus, the command conversation, and
/// a frame strip of the meter resolving into the outcome mark.
///
/// Only in-memory overlay state is touched (`NotchContentState`, `OverlayAudioMeter`);
/// settings and user data are never written.
@MainActor
final class OverlaySnapshotTests: XCTestCase {
    private var saved: SavedState?

    private static let transcript = "请帮我 review 这个 pull request，然后 deploy 到 staging. Also mention the release notes."

    private static let phases: [(String, OverlayPhase)] = [
        ("1-listening", .listening),
        ("2-transcribing", .transcribing),
        ("3-refining", .refining),
        ("4-inserted", .done(.inserted)),
        ("5-no-speech", .done(.noSpeech)),
        ("6-failed", .failed("Couldn't reach the AI provider. Inserted the original text.")),
        ("7-cancelled", .cancelled),
    ]

    override func setUp() async throws {
        try await super.setUp()
        guard SnapshotRenderer.outputDirectory != nil else {
            throw XCTSkip("Set SAYIT_SNAPSHOT_DIR to write UI snapshots")
        }
        // Let the host app finish its launch-time updates (e.g. an initial empty
        // live-preview emission) before configuring overlay state.
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        self.saved = SavedState.capture()
    }

    override func tearDown() async throws {
        self.saved?.restore()
        try await super.tearDown()
    }

    // MARK: - Phases

    func testBottomOverlayPhases() throws {
        var sheet: [(String, Data)] = []
        for (name, phase) in Self.phases {
            self.configure(phase: phase, mode: .dictation)
            let data = try self.renderOverlay(size: CGSize(width: 460, height: 190)) {
                BottomOverlayContent(sizeOverride: .medium)
            }
            try self.write(data, name: "overlay-bottom-\(name)")
            sheet.append((name, data))
        }
        try self.writeContactSheet(sheet, name: "overlay-bottom-phases")
    }

    func testNotchOverlayPhases() throws {
        var sheet: [(String, Data)] = []
        for (name, phase) in Self.phases {
            self.configure(phase: phase, mode: .dictation)
            let data = try self.renderOverlay(size: CGSize(width: 340, height: 150)) {
                NotchOverlayContent()
            }
            try self.write(data, name: "overlay-notch-\(name)")
            sheet.append((name, data))
        }
        try self.writeContactSheet(sheet, name: "overlay-notch-phases")
    }

    func testBottomOverlaySizesAndModes() throws {
        var sheet: [(String, Data)] = []
        let cases: [(String, SettingsStore.OverlaySize, OverlayMode)] = [
            ("small-dictate", .small, .dictation),
            ("medium-edit", .medium, .edit),
            ("large-command", .large, .command),
            ("large-dictate", .large, .dictation),
        ]
        for (name, size, mode) in cases {
            self.configure(phase: .listening, mode: mode)
            let data = try self.renderOverlay(size: CGSize(width: 680, height: 290)) {
                BottomOverlayContent(sizeOverride: size)
            }
            try self.write(data, name: "overlay-bottom-size-\(name)")
            sheet.append((name, data))
        }
        try self.writeContactSheet(sheet, name: "overlay-bottom-sizes")
    }

    /// Long dictation: newest words stay on the last line, earlier lines leave under the fade.
    func testLongTranscript() throws {
        self.configure(phase: .listening, mode: .dictation)
        NotchContentState.shared.updateTranscription(
            Self.transcript + " Then open a ticket for the flaky login test, assign it to the platform team, and remind me tomorrow at ten."
        )
        var sheet: [(String, Data)] = []
        let bottom = try self.renderOverlay(size: CGSize(width: 460, height: 190)) {
            BottomOverlayContent(sizeOverride: .medium)
        }
        sheet.append(("bottom-medium", bottom))
        let notch = try self.renderOverlay(size: CGSize(width: 460, height: 150)) {
            NotchOverlayContent()
        }
        sheet.append(("notch", notch))
        try self.writeContactSheet(sheet, name: "overlay-long-transcript")
    }

    // MARK: - Menus and Command Conversation

    func testOverlayMenus() throws {
        self.configure(phase: .listening, mode: .dictation)
        let kinds: [(String, OverlayMenuKind)] = [
            ("mode", .mode),
            ("prompt", .prompt(.dictate)),
            ("actions", .actions),
        ]
        var sheet: [(String, Data)] = []
        for (name, kind) in kinds {
            let data = try self.renderOverlay(size: CGSize(width: 360, height: 170)) {
                OverlayMenuView(kind: kind, maxWidth: 320) {}
            }
            try self.write(data, name: "overlay-menu-\(name)")
            sheet.append((name, data))
        }
        try self.writeContactSheet(sheet, name: "overlay-menus")
    }

    func testCommandConversation() throws {
        let state = NotchContentState.shared
        state.mode = .command
        state.commandConversationHistory = [
            .init(role: .user, content: "Find the largest files in Downloads"),
            .init(role: .status, content: "Running du -sh ~/Downloads/* | sort -h"),
            .init(role: .assistant, content: "The three largest items are Xcode_26.xip (9.8 GB), dataset.zip (2.1 GB) and a screen recording (840 MB)."),
        ]
        state.isCommandProcessing = false
        let data = try self.renderOverlay(size: CGSize(width: 440, height: 380)) {
            NotchCommandOutputExpandedView(
                maxHeight: 340,
                onDismiss: {},
                onSubmit: { _ in },
                onNewChat: {},
                onSwitchChat: { _ in },
                onClearChat: {}
            )
        }
        try self.write(data, name: "overlay-command-conversation")
    }

    // MARK: - Motion Evidence

    /// Ten consecutive frames (1/30 s apart) of the indicator resolving from the live
    /// meter into the ✓ mark, stitched into one strip.
    func testMeterResolvesIntoMarkStrip() throws {
        self.configure(phase: .listening, mode: .dictation)
        let size = CGSize(width: 120, height: 64)
        let host = NSHostingView(
            rootView: MotionStage()
                .sayItOverlayTheme()
                .frame(width: size.width, height: size.height)
        )
        let window = SnapshotWindow(view: host, size: size)
        defer { window.close() }

        window.settle(seconds: 0.5)
        NotchOverlayManager.shared.present(.done(.inserted))

        var frames: [Data] = []
        for _ in 0..<10 {
            window.settle(seconds: 1.0 / 30.0)
            frames.append(try window.capture())
        }
        try self.writeStrip(frames, name: "overlay-motion-meter-to-check")
    }

    // MARK: - Helpers

    private func configure(phase: OverlayPhase, mode: OverlayMode) {
        let state = NotchContentState.shared
        state.mode = mode
        state.targetAppIcon = NSWorkspace.shared.icon(forFile: "/System/Applications/Notes.app")
        state.updateTranscription(phase == .done(.noSpeech) ? "" : Self.transcript)
        state.setPhase(phase)
        OverlayAudioMeter.shared.set(phase == .listening ? 0.85 : 0)
    }

    /// Renders over a desktop-like backdrop. The test host is the real app, which can
    /// reset the live preview while it finishes launching; if the configured overlay
    /// state changed during the render, configure and render again.
    private func renderOverlay<V: View>(size: CGSize, @ViewBuilder _ content: () -> V) throws -> Data {
        let state = NotchContentState.shared
        let expected = (state.transcriptionText, state.phase, state.mode)
        var data = Data()
        for _ in 0..<3 {
            let view = ZStack {
                DesktopBackdrop()
                content()
            }
            .sayItOverlayTheme()
            data = try SnapshotRenderer.render(view, size: size, appearance: .dark)
            if (state.transcriptionText, state.phase, state.mode) == expected { break }
            state.mode = expected.2
            state.updateTranscription(expected.0)
            state.setPhase(expected.1)
        }
        return data
    }

    private func write(_ data: Data, name: String) throws {
        guard let directory = SnapshotRenderer.outputDirectory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("\(name).png"))
    }

    private func writeContactSheet(_ items: [(String, Data)], name: String) throws {
        let images = items.compactMap { item in NSBitmapImageRep(data: item.1).map { (item.0, $0) } }
        guard let first = images.first?.1 else { return }
        let labelHeight = 22
        let width = first.pixelsWide
        let height = images.reduce(0) { $0 + $1.1.pixelsHigh + labelHeight }
        let sheet = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
            NSColor(white: 0.12, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
            var y = 0
            for (label, rep) in images {
                (label as NSString).draw(
                    at: NSPoint(x: 8, y: y + 4),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white]
                )
                y += labelHeight
                rep.draw(
                    in: NSRect(x: 0, y: y, width: rep.pixelsWide, height: rep.pixelsHigh),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: nil
                )
                y += rep.pixelsHigh
            }
            return true
        }
        try self.write(try Self.png(sheet), name: name)
    }

    private func writeStrip(_ frames: [Data], name: String) throws {
        let reps = frames.compactMap { NSBitmapImageRep(data: $0) }
        guard let first = reps.first else { return }
        let width = reps.reduce(0) { $0 + $1.pixelsWide }
        let height = first.pixelsHigh
        let strip = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            var x = 0
            for rep in reps {
                rep.draw(in: NSRect(x: x, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh))
                x += rep.pixelsWide
            }
            return true
        }
        try self.write(try Self.png(strip), name: name)
    }

    private static func png(_ image: NSImage) throws -> Data {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:])
        else { throw SnapshotRenderer.SnapshotError.encodingFailed }
        return data
    }
}

// MARK: - Fixtures

/// Stand-in for arbitrary desktop content behind the overlay, to judge legibility.
private struct DesktopBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.36, green: 0.52, blue: 0.74),
                Color(red: 0.86, green: 0.78, blue: 0.62),
                Color(red: 0.95, green: 0.95, blue: 0.93),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Indicator on a black stage, driven by the shared overlay state.
private struct MotionStage: View {
    @ObservedObject private var state = NotchContentState.shared

    var body: some View {
        ZStack {
            Color.black
            OverlayIndicator(phase: self.state.phase, mode: self.state.mode, meterStyle: .medium)
        }
    }
}

/// Offscreen window that keeps a hosting view alive across several captures.
@MainActor
private final class SnapshotWindow {
    private let window: NSWindow
    private let view: NSView

    init(view: NSView, size: CGSize) {
        self.view = view
        view.frame = NSRect(origin: .zero, size: size)
        self.window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        self.window.appearance = NSAppearance(named: .darkAqua)
        self.window.contentView = view
        self.window.isReleasedWhenClosed = false
        self.window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        self.window.orderFrontRegardless()
    }

    func settle(seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            self.view.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: min(end, Date().addingTimeInterval(1.0 / 120.0)))
        }
    }

    func capture() throws -> Data {
        guard let rep = self.view.bitmapImageRepForCachingDisplay(in: self.view.bounds) else {
            throw SnapshotRenderer.SnapshotError.renderFailed
        }
        self.view.cacheDisplay(in: self.view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw SnapshotRenderer.SnapshotError.encodingFailed
        }
        return data
    }

    func close() {
        self.window.orderOut(nil)
    }
}

/// In-memory overlay state captured before a test and restored after it.
@MainActor
private struct SavedState {
    let mode: OverlayMode
    let phase: OverlayPhase
    let transcript: String
    let icon: NSImage?
    let history: [NotchContentState.CommandOutputMessage]
    let commandProcessing: Bool

    static func capture() -> SavedState {
        let state = NotchContentState.shared
        return SavedState(
            mode: state.mode,
            phase: state.phase,
            transcript: state.transcriptionText,
            icon: state.targetAppIcon,
            history: state.commandConversationHistory,
            commandProcessing: state.isCommandProcessing
        )
    }

    func restore() {
        let state = NotchContentState.shared
        state.mode = self.mode
        state.setPhase(self.phase)
        state.updateTranscription(self.transcript)
        state.targetAppIcon = self.icon
        state.commandConversationHistory = self.history
        state.isCommandProcessing = self.commandProcessing
        OverlayAudioMeter.shared.set(0)
    }
}
