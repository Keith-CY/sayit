import AppKit

/// Last-resort menu bar icon when the bundled artwork cannot be loaded.
/// Uses the waveform symbol, which matches the overlay's level meter.
enum MenuBarIconGenerator {
    static func createMenuBarIcon() -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: AppIdentity.displayName)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }
}
