import AppKit

enum AppWindowHelper {
    static let minimumWindowSize = NSSize(width: 800, height: 500)
    static let defaultWindowSize = NSSize(width: 1000, height: 700)

    static func isPrimaryWindow(_ window: NSWindow) -> Bool {
        guard window.level == .normal else { return false }
        guard window.styleMask.contains(.titled) else { return false }
        guard window.canBecomeKey else { return false }
        return window.title == AppIdentity.displayName || window.title.contains(AppIdentity.displayName)
    }

    static func primaryWindow(in application: NSApplication = NSApp) -> NSWindow? {
        application.windows.first(where: isPrimaryWindow)
    }

    static func defaultWindowFrame() -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: defaultWindowSize.width, height: defaultWindowSize.height)
        let origin = NSPoint(
            x: visibleFrame.midX - defaultWindowSize.width / 2,
            y: visibleFrame.midY - defaultWindowSize.height / 2
        )
        return NSRect(origin: origin, size: defaultWindowSize)
    }

    static func makeUsableMainWindow(_ window: NSWindow) {
        window.minSize = minimumWindowSize
        let frame = window.frame
        if frame.height < minimumWindowSize.height || frame.width < minimumWindowSize.width {
            window.setFrame(defaultWindowFrame(), display: false)
        }
    }

    static func bringToFront(_ window: NSWindow) {
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }
}
