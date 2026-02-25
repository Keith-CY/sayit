import SwiftUI

enum LiquidGlassTheme {
    static let ink = Color(red: 0.17, green: 0.15, blue: 0.24)
    static let slate = Color(red: 0.53, green: 0.56, blue: 0.69)
    static let hairline = Color(red: 0.97, green: 0.95, blue: 1.00)
    static let hotPink = Color(red: 0.95, green: 0.52, blue: 0.79)
    static let roseQuartz = Color(red: 0.86, green: 0.78, blue: 0.92)
    static let chromeWhite = Color(red: 0.98, green: 0.98, blue: 1.00)
    static let chromeSilver = Color(red: 0.88, green: 0.90, blue: 0.95)
    static let silkBase = Color(red: 0.96, green: 0.94, blue: 0.98)
    static let silkShadow = Color(red: 0.78, green: 0.73, blue: 0.84)
    static let neonCyan = chromeSilver
    static let neonPink = hotPink
    static let glowViolet = roseQuartz

    static let accentGradient = LinearGradient(
        colors: [
            hotPink,
            roseQuartz,
            chromeWhite,
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let chromeGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.95),
            Color(red: 0.92, green: 0.94, blue: 1.00),
            Color.white.opacity(0.88),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct LiquidGlassCanvas: View {
    var body: some View {
        ZStack {
            LiquidGlassTheme.silkBase

            SilkRippleField()
        }
        .ignoresSafeArea()
    }
}

private struct SilkRippleField: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                drawHorizontalFolds(context: &context, size: size, time: t)
                drawVerticalFolds(context: &context, size: size, time: t)
                drawSpecularRipples(context: &context, size: size, time: t)
            }
            .blur(radius: 0.28)
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    private func drawHorizontalFolds(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let layers = 20
        for layer in 0..<layers {
            let p = CGFloat(layer) / CGFloat(max(layers - 1, 1))
            let centerWeight = 1 - abs(p - 0.5) * 1.28
            let amplitude = 5 + max(centerWeight, 0) * 15
            let speed = 0.45 + CGFloat(layer % 4) * 0.08
            let phase = CGFloat(time) * speed + CGFloat(layer) * 0.58
            let yBase = size.height * p
            let foldPath = makeHorizontalFoldPath(size: size, yBase: yBase, amplitude: amplitude, phase: phase)
            let tint = foldColor(index: layer)
            let highlightPath = foldPath.applying(CGAffineTransform(translationX: 0, y: -0.9))
            let shadowPath = foldPath.applying(CGAffineTransform(translationX: 0, y: 1.2))

            context.stroke(
                highlightPath,
                with: .color(LiquidGlassTheme.chromeWhite.opacity(0.17)),
                style: StrokeStyle(lineWidth: 0.95, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                foldPath,
                with: .color(tint.opacity(0.19)),
                style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                shadowPath,
                with: .color(LiquidGlassTheme.silkShadow.opacity(0.14)),
                style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func drawVerticalFolds(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let columns = 7
        for index in 0..<columns {
            let p = CGFloat(index) / CGFloat(max(columns - 1, 1))
            let xBase = size.width * (0.08 + p * 0.86)
            let amplitude = 6 + CGFloat(index % 3) * 4
            let phase = CGFloat(time) * 0.27 + CGFloat(index) * 1.17
            let foldPath = makeVerticalFoldPath(size: size, xBase: xBase, amplitude: amplitude, phase: phase)

            context.stroke(
                foldPath,
                with: .color(LiquidGlassTheme.roseQuartz.opacity(0.10)),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                foldPath.applying(CGAffineTransform(translationX: 1.3, y: 0)),
                with: .color(LiquidGlassTheme.chromeWhite.opacity(0.08)),
                style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func drawSpecularRipples(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let ringCount = 3
        for index in 0..<ringCount {
            let p = CGFloat(index) / CGFloat(max(ringCount - 1, 1))
            let drift = CGFloat(sin(time * 0.16 + Double(index) * 0.93))
            let rect = CGRect(
                x: size.width * (0.04 + p * 0.27 + drift * 0.018),
                y: size.height * (0.12 + p * 0.23),
                width: size.width * (0.56 + p * 0.16),
                height: size.height * (0.20 + p * 0.08)
            )
            let ringPath = Path(ellipseIn: rect)
            context.stroke(
                ringPath,
                with: .color(LiquidGlassTheme.chromeWhite.opacity(0.09)),
                style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                ringPath.applying(CGAffineTransform(translationX: 0, y: 1.4)),
                with: .color(LiquidGlassTheme.silkShadow.opacity(0.08)),
                style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func makeHorizontalFoldPath(size: CGSize, yBase: CGFloat, amplitude: CGFloat, phase: CGFloat) -> Path {
        var path = Path()
        let step = max(size.width / 56.0, 16)
        path.move(to: CGPoint(x: -step, y: yBase))

        var x: CGFloat = -step
        while x <= size.width + step {
            let nx = x / max(size.width, 1)
            let waveA = sin(nx * 8.2 + phase)
            let waveB = cos(nx * 4.9 - phase * 0.9)
            let waveC = sin(nx * 1.7 + phase * 0.28)
            let y = yBase + waveA * amplitude + waveB * amplitude * 0.42 + waveC * amplitude * 0.25
            path.addLine(to: CGPoint(x: x, y: y))
            x += step
        }
        return path
    }

    private func makeVerticalFoldPath(size: CGSize, xBase: CGFloat, amplitude: CGFloat, phase: CGFloat) -> Path {
        var path = Path()
        let step = max(size.height / 44.0, 16)
        path.move(to: CGPoint(x: xBase, y: -step))

        var y: CGFloat = -step
        while y <= size.height + step {
            let ny = y / max(size.height, 1)
            let swayA = sin(ny * 7.6 + phase) * amplitude
            let swayB = cos(ny * 3.1 - phase * 0.73) * amplitude * 0.54
            path.addLine(to: CGPoint(x: xBase + swayA + swayB, y: y))
            y += step
        }
        return path
    }

    private func foldColor(index: Int) -> Color {
        switch index % 4 {
        case 0:
            return LiquidGlassTheme.chromeWhite
        case 1:
            return LiquidGlassTheme.hotPink
        case 2:
            return LiquidGlassTheme.roseQuartz
        default:
            return LiquidGlassTheme.chromeSilver
        }
    }
}

struct LiquidGlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder var content: Content

    init(cornerRadius: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.90))
            )
            .overlay(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(LiquidGlassTheme.hairline.opacity(0.92), lineWidth: 1)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .inset(by: 1)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.75), Color.white.opacity(0.25)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: LiquidGlassTheme.glowViolet.opacity(0.22), radius: 28, x: 0, y: 14)
            .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 8)
    }
}

struct GlassPillButtonStyle: ButtonStyle {
    var isSelected: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(isSelected ? Color.white : LiquidGlassTheme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial.opacity(isSelected ? 0.0 : 0.94))
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(LiquidGlassTheme.accentGradient)
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.48), Color.white.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                }
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(LiquidGlassTheme.hairline.opacity(isSelected ? 0.0 : 0.95), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}
