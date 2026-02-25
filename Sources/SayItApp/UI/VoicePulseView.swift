import SwiftUI

struct VoicePulseView: View {
    let isActive: Bool
    let level: CGFloat
    let bands: [CGFloat]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = CGFloat(t * 2.6)
            let normalizedLevel = min(max(level, 0), 1)
            let drive = isActive ? max(normalizedLevel, 0.03) : 0.01

            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LiquidGlassTheme.accentGradient.opacity(isActive ? 0.22 : 0.08))
                        .frame(width: 68 + drive * 34, height: 68 + drive * 34)
                        .blur(radius: 18)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(isActive ? 0.94 : 0.75),
                                    LiquidGlassTheme.roseQuartz.opacity(isActive ? 0.62 : 0.35),
                                ],
                                center: .center,
                                startRadius: 5,
                                endRadius: 56
                            )
                        )
                        .frame(width: 56 + drive * 24, height: 56 + drive * 24)

                    Circle()
                        .stroke(LiquidGlassTheme.hairline.opacity(0.9), lineWidth: 1)
                        .frame(width: 76 + drive * 30, height: 76 + drive * 30)
                        .blur(radius: 0.2)

                    Image(systemName: isActive ? "mic.fill" : "mic.slash")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(LiquidGlassTheme.hotPink.opacity(0.90))
                }

                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<18, id: \.self) { index in
                        let x = CGFloat(index) / 17.0
                        let envelope = exp(-pow((x - 0.5) * 2.1, 2))
                        let ripple = (sin(phase + x * 14.0) + 1) * 0.5
                        let inputBand = bands.isEmpty ? 0 : bands[min(index, bands.count - 1)]
                        let bandDrive = isActive ? max(min(inputBand, 1), 0) : 0.02
                        let amplitude = (0.12 + bandDrive * 0.95 * ripple) * envelope
                        let height = 6 + amplitude * 58

                        Capsule()
                            .fill(
                                isActive
                                ? LinearGradient(
                                    colors: [
                                        LiquidGlassTheme.hotPink.opacity(0.94),
                                        LiquidGlassTheme.roseQuartz.opacity(0.85),
                                        LiquidGlassTheme.chromeWhite.opacity(0.96),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                : LinearGradient(
                                    colors: [
                                        LiquidGlassTheme.chromeSilver.opacity(0.38),
                                        LiquidGlassTheme.slate.opacity(0.24),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 4, height: height)
                            .animation(.easeOut(duration: 0.08), value: bandDrive)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(LiquidGlassTheme.hairline.opacity(0.9), lineWidth: 1)
        )
        .frame(height: 148)
    }
}
