import AppKit
import SwiftUI
import XCTest

@testable import SayIt

/// Renders SwiftUI views offscreen (inside an NSWindow, so AppKit-backed controls draw
/// correctly) and writes PNGs used as visual evidence for design review.
///
/// Snapshots are written only when `SAYIT_SNAPSHOT_DIR` is set. With xcodebuild, pass it
/// as `TEST_RUNNER_SAYIT_SNAPSHOT_DIR=/path` so it reaches the test process:
///
///     TEST_RUNNER_SAYIT_SNAPSHOT_DIR=/tmp/shots xcodebuild test -scheme SayIt \
///       -only-testing:SayItDictationIntegrationTests/UISnapshotTests
@MainActor
enum SnapshotRenderer {
    enum Appearance: String, CaseIterable {
        case dark
        case light

        var nsAppearance: NSAppearance? {
            switch self {
            case .dark: return NSAppearance(named: .darkAqua)
            case .light: return NSAppearance(named: .aqua)
            }
        }
    }

    static var outputDirectory: URL? {
        guard let path = ProcessInfo.processInfo.environment["SAYIT_SNAPSHOT_DIR"], !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Renders `view` at `size` in each appearance. Skips the test when no output
    /// directory is configured.
    static func snapshot<V: View>(
        _ name: String,
        size: CGSize,
        appearances: [Appearance] = Appearance.allCases,
        overlay: Bool = false,
        @ViewBuilder _ view: () -> V
    ) throws {
        guard let directory = self.outputDirectory else {
            throw XCTSkip("Set SAYIT_SNAPSHOT_DIR to write UI snapshots")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for appearance in appearances {
            let themed: AnyView = overlay
                ? AnyView(view().sayItOverlayTheme())
                : AnyView(view().sayItTheme())
            let image = try self.render(themed, size: size, appearance: appearance)
            let suffix = overlay ? "" : "-\(appearance.rawValue)"
            let url = directory.appendingPathComponent("\(name)\(suffix).png")
            try image.write(to: url)
            if overlay { break }
        }
    }

    static func render<V: View>(_ view: V, size: CGSize, appearance: Appearance) throws -> Data {
        let hostingView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hostingView.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance.nsAppearance
        hostingView.appearance = appearance.nsAppearance
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFrontRegardless()

        // Let SwiftUI complete layout, onAppear work and the first animation frames.
        for _ in 0..<6 {
            hostingView.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw SnapshotError.renderFailed
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
        window.orderOut(nil)

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw SnapshotError.encodingFailed
        }
        return data
    }

    enum SnapshotError: Error {
        case renderFailed
        case encodingFailed
    }
}
