import SwiftUI

enum ThemedCardStyle {
    /// Default grouped section.
    case standard
    /// The one focal card on a page (setup checklist, test area, status hero).
    /// Rendered as a nested tray + core with concentric corners.
    case prominent
    /// Quiet inset group inside another card.
    case subtle
}

struct ThemedCard<Content: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private let style: ThemedCardStyle
    private let hoverEffect: Bool
    private let padding: CGFloat?
    private let content: Content

    init(
        style: ThemedCardStyle = .standard,
        padding: CGFloat? = nil,
        hoverEffect: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.padding = padding
        self.hoverEffect = hoverEffect
        self.content = content()
    }

    var body: some View {
        switch self.style {
        case .standard:
            self.surface(radius: Radius.lg, fill: self.theme.palette.surface, elevated: false)
        case .subtle:
            self.content
                .padding(self.padding ?? Space.md)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(self.theme.palette.surfaceSunken)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(self.theme.palette.hairline, lineWidth: 1)
                )
        case .prominent:
            // Outer tray holds the core with a 4pt gap so the two radii stay concentric.
            let trayInset = Space.xs
            self.surface(
                radius: Radius.concentric(outer: Radius.xl, inset: trayInset),
                fill: self.theme.palette.surfaceRaised,
                elevated: true
            )
            .padding(trayInset)
            .background(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(self.theme.palette.accentSubtle.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(self.theme.palette.hairline, lineWidth: 1)
            )
        }
    }

    private func surface(radius: CGFloat, fill: Color, elevated: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let shadow = elevated ? self.theme.metrics.elevatedCardShadow : self.theme.metrics.cardShadow
        let hovered = self.hoverEffect && self.isHovered

        return self.content
            .padding(self.padding ?? Space.lg)
            .background(
                shape
                    .fill(hovered ? self.theme.palette.surfaceRaised : fill)
                    .shadow(
                        color: shadow.color.opacity(hovered ? shadow.opacity * 1.4 : shadow.opacity),
                        radius: shadow.radius,
                        x: shadow.x,
                        y: shadow.y
                    )
            )
            .overlay(
                shape.strokeBorder(self.theme.palette.hairline, lineWidth: 1)
            )
            .overlay(alignment: .top) {
                // Top-edge highlight: reads as a lit bevel on dark surfaces.
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [self.theme.palette.innerHighlight, .clear],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
            .onHover { hovering in
                guard self.hoverEffect else { return }
                self.isHovered = hovering
            }
            .animation(Motion.resolved(Motion.snappy, reduceMotion: self.reduceMotion), value: hovered)
    }
}
