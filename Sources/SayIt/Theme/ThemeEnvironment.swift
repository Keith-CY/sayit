import SwiftUI

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .dark
}

extension EnvironmentValues {
    var theme: AppTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension View {
    /// Applies a fixed app theme to the view hierarchy.
    func appTheme(_ theme: AppTheme) -> some View {
        environment(\.theme, theme)
    }

    /// Resolves the theme from the system appearance, the contrast setting and the
    /// user's accent choice, and keeps it in sync when any of them change.
    /// Use once at the root of every window or hosting controller.
    func sayItTheme() -> some View {
        modifier(ThemeRootModifier(forcedScheme: nil))
    }

    /// Theme root for surfaces that are always dark (recording overlays / HUDs).
    func sayItOverlayTheme() -> some View {
        modifier(ThemeRootModifier(forcedScheme: .dark))
    }
}

private struct ThemeRootModifier: ViewModifier {
    let forcedScheme: ColorScheme?

    func body(content: Content) -> some View {
        if let forcedScheme {
            ThemeResolver { content }
                .environment(\.colorScheme, forcedScheme)
        } else {
            ThemeResolver { content }
        }
    }
}

/// Reads the appearance from the environment it is placed in, so a forced scheme
/// applied outside of it is respected.
private struct ThemeResolver<Content: View>: View {
    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let theme = AppTheme.make(
            scheme: self.colorScheme,
            contrast: self.contrast,
            accentHex: self.settings.accentColorOption.hex
        )
        self.content
            .environment(\.theme, theme)
            .tint(theme.palette.accent)
    }
}

// MARK: - Color Hex Initializer

extension Color {
    /// Initialize a Color from a hex string (e.g., "#FF5733" or "FF5733")
    init?(hex: String) {
        guard let rgb = RGBColor(hex: hex) else { return nil }
        self = rgb.color
    }

    @available(*, deprecated, message: "Read the accent from the environment: theme.palette.accent")
    static var fluidGreen: Color {
        SettingsStore.shared.accentColor
    }
}
