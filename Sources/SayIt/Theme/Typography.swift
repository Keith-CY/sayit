import SwiftUI

/// Type scale. Built on macOS text styles so sizes follow system conventions.
///
/// SayIt's core idea is "voice becomes writing": interface chrome is set in SF Pro,
/// while words the user has spoken (transcripts, previews, history) are set in
/// New York, the system serif, so written output reads as distinct from controls.
/// No information-bearing text goes below 11pt; `micro` is for badges that repeat
/// information already shown elsewhere.
enum AppFont {
    /// Hero line on Home / Welcome.
    static let display = Font.system(size: 26, weight: .semibold, design: .serif)
    /// Page title at the top of each sidebar destination.
    static let pageTitle = Font.system(.title2, design: .default, weight: .semibold)
    /// Card / section header.
    static let sectionTitle = Font.system(.headline)
    /// Row title inside a card.
    static let rowTitle = Font.system(.body, weight: .medium)
    static let body = Font.system(.body)
    static let bodyEmphasis = Font.system(.body, weight: .semibold)
    /// Supporting text under a row title.
    static let callout = Font.system(.callout)
    /// Smallest information text (11pt): metadata, hints, helper copy.
    static let caption = Font.system(.subheadline)
    static let captionEmphasis = Font.system(.subheadline, weight: .semibold)
    /// 10pt badges and key caps only.
    static let micro = Font.system(size: 10, weight: .semibold)
    /// Large numeric values (stats).
    static let metric = Font.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit()
    static let metricSmall = Font.system(.title3, design: .rounded, weight: .semibold).monospacedDigit()
    /// Shortcuts, file paths, model identifiers.
    static let mono = Font.system(.callout, design: .monospaced)
    /// Spoken words rendered as text.
    static let transcript = Font.system(.body, design: .serif)
    static let transcriptLarge = Font.system(.title3, design: .serif)
    /// Glyph sizes for SF Symbols used as icons.
    static let iconSmall = Font.system(size: 12, weight: .regular)
    static let icon = Font.system(size: 14, weight: .regular)
    static let iconLarge = Font.system(size: 20, weight: .regular)

    /// Overlay (HUD) scale. The overlay is a compact, glanceable surface; its minimum
    /// size is still 11pt.
    enum Overlay {
        static let status = Font.system(size: 11, weight: .semibold)
        static let transcript = Font.system(size: 13, weight: .regular, design: .serif)
        static let transcriptCompact = Font.system(size: 12, weight: .regular, design: .serif)
        /// Transcript size for the large bottom overlay.
        static let transcriptLarge = Font.system(size: 15, weight: .regular, design: .serif)
        /// Menu rows in overlay pop-up menus.
        static let menuRow = Font.system(size: 13, weight: .medium)
        static let label = Font.system(size: 11, weight: .medium)
        static let keyCap = Font.system(size: 10, weight: .semibold, design: .rounded)
        static let icon = Font.system(size: 12, weight: .medium)
    }

    /// Live Captions panel: other people's speech, read at a glance while watching.
    enum LiveCaption {
        /// Caption text, sized to read from a normal viewing distance.
        static let text = Font.system(size: 19, weight: .regular, design: .serif)
        /// Empty, preparing and failed states.
        static let message = Font.system(size: 13, weight: .medium)
        static let detail = Font.system(size: 12, weight: .regular)
    }
}
