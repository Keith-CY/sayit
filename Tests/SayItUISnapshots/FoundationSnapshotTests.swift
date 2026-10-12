import SwiftUI
import XCTest

@testable import SayIt

/// Design-system specimen: buttons, cards, type scale and palette in both appearances.
@MainActor
final class FoundationSnapshotTests: XCTestCase {
    func testDesignSystemSpecimen() throws {
        try SnapshotRenderer.snapshot("foundation-specimen", size: CGSize(width: 720, height: 560)) {
            DesignSpecimen()
        }
    }
}

private struct DesignSpecimen: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Say it. It's written.")
                    .font(AppFont.display)
                Text("Type scale, buttons and surfaces")
                    .font(AppFont.callout)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }

            HStack(spacing: Space.md) {
                Button("Start Dictating") {}.buttonStyle(.sayItPrimary)
                Button("Download") {}.buttonStyle(.sayItSecondary)
                Button("Learn More") {}.buttonStyle(.sayItQuiet)
                Button("Delete Model") {}.buttonStyle(.sayItDestructive)
                Button("Disabled") {}.buttonStyle(.sayItPrimary).disabled(true)
                IconButton("Copy", systemName: "doc.on.doc") {}
            }

            HStack(alignment: .top, spacing: Space.lg) {
                ThemedCard {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("Standard Card").font(AppFont.sectionTitle)
                        Text("Secondary text on a surface").font(AppFont.callout)
                            .foregroundStyle(self.theme.palette.secondaryText)
                        Text("Tertiary metadata · 2 min ago").font(AppFont.caption)
                            .foregroundStyle(self.theme.palette.tertiaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                ThemedCard(style: .prominent) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("Prominent Card").font(AppFont.sectionTitle)
                        Text("“Please review this pull request, then deploy to staging.”")
                            .font(AppFont.transcript)
                        Text("Accent text").font(AppFont.captionEmphasis)
                            .foregroundStyle(self.theme.palette.accentForeground)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack(spacing: Space.sm) {
                ForEach(Array(self.swatches.enumerated()), id: \.offset) { _, swatch in
                    VStack(spacing: Space.xs) {
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(swatch.1)
                            .frame(width: 56, height: 32)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .strokeBorder(self.theme.palette.hairline)
                            )
                        Text(swatch.0).font(AppFont.micro)
                            .foregroundStyle(self.theme.palette.secondaryText)
                    }
                }
            }
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(self.theme.palette.contentBackground)
    }

    private var swatches: [(String, Color)] {
        let palette = self.theme.palette
        return [
            ("accent", palette.accent),
            ("surface", palette.surface),
            ("raised", palette.surfaceRaised),
            ("sunken", palette.surfaceSunken),
            ("success", palette.success),
            ("warning", palette.warning),
            ("error", palette.error),
            ("info", palette.info),
        ]
    }
}
