import SwiftUI

/// Central theme definition for the SayIt app.
///
/// Every color, spacing, radius, font and motion curve used by the UI comes from here
/// (see `docs/design/DESIGN.md`). Palettes are resolved per appearance (light / dark,
/// standard / increased contrast) and per user-selected accent, so views never need
/// to hard-code values or check the color scheme themselves.
struct AppTheme {
    struct Palette {
        // Surfaces, from deepest to most raised.
        let windowBackground: Color
        let sidebarBackground: Color
        let contentBackground: Color
        /// Default card / grouped-section surface.
        let surface: Color
        /// Raised surface (popovers, prominent cards, selected rows).
        let surfaceRaised: Color
        /// Recessed surface (text fields, wells, code/transcript areas).
        let surfaceSunken: Color
        /// Hover fill for rows and quiet buttons.
        let surfaceHover: Color
        let toolbarBackground: Color

        // Lines.
        /// Card and control outline. Use as-is; do not multiply its opacity.
        let hairline: Color
        let separator: Color
        /// 1pt top highlight that gives raised surfaces their edge in dark mode.
        let innerHighlight: Color

        // Text. All text tokens meet WCAG AA (4.5:1) on every surface token.
        let primaryText: Color
        let secondaryText: Color
        let tertiaryText: Color
        let disabledText: Color

        // Accent.
        /// Accent as a fill (buttons, switches, selection).
        let accent: Color
        /// Accent used as text or a glyph on a surface; contrast-corrected per appearance.
        let accentForeground: Color
        /// Text or glyphs placed on top of an `accent` fill.
        let onAccent: Color
        /// Quiet accent tint for selected rows and badges.
        let accentSubtle: Color

        // Status. Fixed meanings, independent of the user's accent choice.
        let success: Color
        let warning: Color
        let error: Color
        let info: Color
        let recording: Color

        // Shadow used for elevation in light mode (dark mode relies on hairlines).
        let shadow: Color

        // MARK: - Legacy aliases (kept while views migrate to the semantic names)

        var cardBackground: Color { self.surface }
        var elevatedCardBackground: Color { self.surfaceRaised }
        /// Base outline color for call sites that still apply their own opacity.
        let cardBorder: Color

        /// Tinted background for a status color (badges, banners).
        func subtle(_ color: Color) -> Color {
            color.opacity(0.14)
        }
    }

    struct Metrics {
        struct Spacing {
            let xs: CGFloat
            let sm: CGFloat
            let md: CGFloat
            let lg: CGFloat
            let xl: CGFloat
            let xxl: CGFloat
            let xxxl: CGFloat

            static let standard = Spacing(
                xs: Space.xs,
                sm: Space.sm,
                md: Space.md,
                lg: Space.lg,
                xl: Space.xl,
                xxl: Space.xxl,
                xxxl: Space.xxxl
            )
        }

        struct CornerRadius {
            let xs: CGFloat
            let sm: CGFloat
            let md: CGFloat
            let lg: CGFloat
            let xl: CGFloat
            let pill: CGFloat

            static let standard = CornerRadius(
                xs: Radius.xs,
                sm: Radius.sm,
                md: Radius.md,
                lg: Radius.lg,
                xl: Radius.xl,
                pill: Radius.pill
            )
        }

        struct Shadow {
            let color: Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
            let opacity: Double
        }

        let spacing: Spacing
        let corners: CornerRadius
        let cardShadow: Shadow
        let elevatedCardShadow: Shadow
    }

    struct Materials {
        let window: Material
        let sidebar: Material
        let card: Material
        let elevatedCard: Material
        let toolbar: Material
    }

    let colorScheme: ColorScheme
    let palette: Palette
    let metrics: Metrics
    let materials: Materials

    /// Recording-overlay (HUD) palette. Overlays sit next to the hardware notch and over
    /// arbitrary desktop content, so they are always dark regardless of appearance.
    var overlay: OverlayPalette {
        OverlayPalette(accent: self.palette.accent)
    }
}

// MARK: - Overlay (HUD) Palette

struct OverlayPalette {
    let accent: Color

    let surface = Color.black
    let surfaceRaised = Color.white.opacity(0.08)
    let surfaceHover = Color.white.opacity(0.12)
    let hairline = Color.white.opacity(0.14)
    let primaryText = Color.white.opacity(0.94)
    let secondaryText = Color.white.opacity(0.72)
    /// Lowest text level still at 4.5:1 on the black HUD surface.
    let tertiaryText = Color.white.opacity(0.56)

    /// Mode identity colors. Dictation stays neutral (voice becomes plain text);
    /// Edit and Command get distinct hues that never collide with error red.
    let dictation = Color.white.opacity(0.88)
    let edit = Color(red: 0.42, green: 0.62, blue: 1.0)
    let command = Color(red: 0.98, green: 0.72, blue: 0.30)

    /// "You" in Live Captions: microphone lines read apart from Mac audio at a glance
    /// (their source mark says it too). Settled, draft and forming steps all stay above
    /// 4.5:1 on the black surface (12.4, 7.5 and 5.1).
    let you = Color(red: 0.45, green: 0.85, blue: 0.80)
    let youDraft = Color(red: 0.45, green: 0.85, blue: 0.80).opacity(0.78)
    let youForming = Color(red: 0.45, green: 0.85, blue: 0.80).opacity(0.62)

    let success = Color(nsColor: .systemGreen)
    let warning = Color(nsColor: .systemOrange)
    let error = Color(nsColor: .systemRed)
    let recording = Color(nsColor: .systemRed)

    func color(for mode: OverlayMode) -> Color {
        switch mode {
        case .dictation: return self.dictation
        case .edit, .rewrite, .write: return self.edit
        case .command: return self.command
        }
    }
}

// MARK: - Static Scales

/// Spacing scale (4pt base). Use these instead of numeric literals.
enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
    static let xxxl: CGFloat = 40
}

/// Corner radius scale. Nested shapes stay concentric: inner = outer − padding
/// (e.g. an `xl` tray with `xs` padding holds an `lg` core).
enum Radius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let pill: CGFloat = 999

    static func concentric(outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(outer - inset, 0)
    }
}

// MARK: - Palette Construction

extension AppTheme {
    static let defaultAccentHex = SettingsStore.AccentColorOption.cyan.hex

    /// Resolves the theme for an appearance and accent.
    static func make(
        scheme: ColorScheme,
        contrast: ColorSchemeContrast = .standard,
        accentHex: String = AppTheme.defaultAccentHex
    ) -> AppTheme {
        let increased = contrast == .increased
        let accentRGB = RGBColor(hex: accentHex) ?? RGBColor(hex: AppTheme.defaultAccentHex) ?? RGBColor(white: 0.5)

        let palette: Palette
        let cardShadow: Metrics.Shadow
        let elevatedShadow: Metrics.Shadow

        switch scheme {
        case .light:
            let surface = RGBColor(white: 1.0)
            palette = Palette(
                windowBackground: RGBColor(white: 0.955).color,
                sidebarBackground: RGBColor(white: 0.93).color,
                contentBackground: RGBColor(white: 0.965).color,
                surface: surface.color,
                surfaceRaised: surface.color,
                surfaceSunken: RGBColor(white: 0.94).color,
                surfaceHover: Color.black.opacity(0.045),
                toolbarBackground: RGBColor(white: 0.95).color,
                hairline: Color.black.opacity(increased ? 0.28 : 0.10),
                separator: Color.black.opacity(increased ? 0.30 : 0.10),
                innerHighlight: Color.white.opacity(0.0),
                primaryText: Color(nsColor: .labelColor),
                secondaryText: RGBColor(white: increased ? 0.25 : 0.36).color,
                tertiaryText: RGBColor(white: increased ? 0.30 : 0.42).color,
                disabledText: Color.black.opacity(0.32),
                accent: accentRGB.color,
                accentForeground: accentRGB.readable(on: RGBColor(white: 0.94), towards: .black).color,
                onAccent: accentRGB.bestTextColor.color,
                accentSubtle: accentRGB.color.opacity(0.14),
                success: Color(nsColor: .systemGreen),
                warning: Color(nsColor: .systemOrange),
                error: Color(nsColor: .systemRed),
                info: Color(nsColor: .systemBlue),
                recording: Color(nsColor: .systemRed),
                shadow: Color.black.opacity(0.07),
                cardBorder: Color.black.opacity(increased ? 0.9 : 0.35)
            )
            cardShadow = Metrics.Shadow(color: .black, radius: 14, x: 0, y: 4, opacity: 0.06)
            elevatedShadow = Metrics.Shadow(color: .black, radius: 24, x: 0, y: 10, opacity: 0.10)

        default:
            let raised = RGBColor(white: 0.13)
            palette = Palette(
                windowBackground: RGBColor(white: 0.07).color,
                sidebarBackground: RGBColor(white: 0.06).color,
                contentBackground: RGBColor(white: 0.075).color,
                surface: RGBColor(white: 0.10).color,
                surfaceRaised: raised.color,
                surfaceSunken: RGBColor(white: 0.055).color,
                surfaceHover: Color.white.opacity(0.06),
                toolbarBackground: RGBColor(white: 0.06).color,
                hairline: Color.white.opacity(increased ? 0.32 : 0.09),
                separator: Color.white.opacity(increased ? 0.30 : 0.08),
                innerHighlight: Color.white.opacity(increased ? 0.0 : 0.06),
                primaryText: Color(nsColor: .labelColor),
                secondaryText: RGBColor(white: increased ? 0.80 : 0.70).color,
                tertiaryText: RGBColor(white: increased ? 0.70 : 0.58).color,
                disabledText: Color.white.opacity(0.32),
                accent: accentRGB.color,
                accentForeground: accentRGB.readable(on: raised, towards: .white).color,
                onAccent: accentRGB.bestTextColor.color,
                accentSubtle: accentRGB.color.opacity(0.16),
                success: Color(nsColor: .systemGreen),
                warning: Color(nsColor: .systemOrange),
                error: Color(nsColor: .systemRed),
                info: Color(nsColor: .systemBlue),
                recording: Color(nsColor: .systemRed),
                shadow: Color.black.opacity(0.35),
                cardBorder: Color.white.opacity(increased ? 1.0 : 0.36)
            )
            cardShadow = Metrics.Shadow(color: .black, radius: 18, x: 0, y: 8, opacity: 0.18)
            elevatedShadow = Metrics.Shadow(color: .black, radius: 28, x: 0, y: 14, opacity: 0.24)
        }

        return AppTheme(
            colorScheme: scheme,
            palette: palette,
            metrics: Metrics(
                spacing: .standard,
                corners: .standard,
                cardShadow: cardShadow,
                elevatedCardShadow: elevatedShadow
            ),
            materials: Materials(
                window: .thinMaterial,
                sidebar: .ultraThinMaterial,
                card: .thinMaterial,
                elevatedCard: .regularMaterial,
                toolbar: .ultraThinMaterial
            )
        )
    }

    static let dark = AppTheme.make(scheme: .dark)
    static let light = AppTheme.make(scheme: .light)
}

// MARK: - Color Math

/// Minimal sRGB color used to derive contrast-safe variants of the accent.
struct RGBColor: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    static let black = RGBColor(white: 0)
    static let white = RGBColor(white: 1)

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(white: Double) {
        self.init(red: white, green: white, blue: white)
    }

    init?(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.replacingOccurrences(of: "#", with: "")
        guard sanitized.count == 6, let value = UInt64(sanitized, radix: 16) else { return nil }
        self.init(
            red: Double((value & 0xff0000) >> 16) / 255.0,
            green: Double((value & 0x00ff00) >> 8) / 255.0,
            blue: Double(value & 0x0000ff) / 255.0
        )
    }

    var color: Color {
        Color(red: self.red, green: self.green, blue: self.blue)
    }

    /// WCAG relative luminance.
    var relativeLuminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(self.red) + 0.7152 * channel(self.green) + 0.0722 * channel(self.blue)
    }

    func contrastRatio(with other: RGBColor) -> Double {
        let first = self.relativeLuminance
        let second = other.relativeLuminance
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    func mixed(with other: RGBColor, amount: Double) -> RGBColor {
        let amount = min(max(amount, 0), 1)
        return RGBColor(
            red: self.red + (other.red - self.red) * amount,
            green: self.green + (other.green - self.green) * amount,
            blue: self.blue + (other.blue - self.blue) * amount
        )
    }

    /// Near-black or white, whichever reads better on this color as a fill.
    var bestTextColor: RGBColor {
        let dark = RGBColor(white: 0.08)
        return self.contrastRatio(with: dark) >= self.contrastRatio(with: .white) ? dark : .white
    }

    /// Moves this color towards `target` until it reaches `minimum` contrast on `background`.
    func readable(on background: RGBColor, towards target: RGBColor, minimum: Double = 4.5) -> RGBColor {
        var candidate = self
        var step = 0.0
        while candidate.contrastRatio(with: background) < minimum, step < 1 {
            step += 0.05
            candidate = self.mixed(with: target, amount: step)
        }
        return candidate
    }
}
