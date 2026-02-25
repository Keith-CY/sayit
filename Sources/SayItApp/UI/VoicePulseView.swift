import SwiftUI

struct VoicePulseView: View {
    let isActive: Bool
    @State private var levels: [CGFloat] = Array(repeating: 0.2, count: 12)

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(isActive ? Color.accentColor : Color.gray.opacity(0.4))
                    .frame(width: 4, height: max(8, 46 * levels[index]))
            }
        }
        .frame(height: 52)
        .onAppear {
            tick()
        }
        .onChange(of: isActive) { _, _ in
            tick()
        }
    }

    private func tick() {
        guard isActive else {
            withAnimation(.easeOut(duration: 0.2)) {
                levels = Array(repeating: 0.2, count: levels.count)
            }
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            levels = levels.map { _ in .random(in: 0.2...1.0) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.19) {
            tick()
        }
    }
}
