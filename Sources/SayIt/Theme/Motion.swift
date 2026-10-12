import AppKit
import SwiftUI

/// Motion system. See `docs/design/DESIGN.md` § Motion.
///
/// Rules: every animation has a purpose; one protagonist moves at a time; entrances
/// decelerate (fast → slow), exits accelerate (slow → fast); nothing is linear or
/// uniform except progress that represents real elapsed work. With Reduce Motion on,
/// spatial motion is replaced by short cross-fades and ambient loops stop.
enum Motion {
    // MARK: - Durations (seconds)

    static let quick: Double = 0.16
    static let standard: Double = 0.28
    static let slow: Double = 0.42
    /// Delay between items in a staggered entrance.
    static let stagger: Double = 0.04
    /// How long a finished overlay state (done / failed / cancelled) stays on screen.
    static let outcomeDwell: Double = 1.1
    /// Period for ambient "working" loops (shimmer, pulse).
    static let ambientPeriod: Double = 1.6

    // MARK: - Curves

    /// Entrance: expo-out. Fast start, long soft landing.
    static let enter = Animation.timingCurve(0.16, 1, 0.3, 1, duration: Motion.standard)
    /// Exit: ease-in. Leaves quickly without lingering.
    static let exit = Animation.timingCurve(0.7, 0, 0.84, 0, duration: Motion.quick)
    /// State change of something already on screen (selection, expansion, layout).
    static let state = Animation.spring(response: 0.34, dampingFraction: 0.86)
    /// Direct manipulation feedback (hover, press).
    static let snappy = Animation.spring(response: 0.2, dampingFraction: 0.9)
    /// A single celebratory beat (step completed, dictation succeeded).
    static let emphasis = Animation.spring(response: 0.42, dampingFraction: 0.68)
    /// Cross-fade used in place of spatial motion when Reduce Motion is on.
    static let fade = Animation.timingCurve(0.2, 0, 0, 1, duration: Motion.quick)
    /// Half-cycle of an ambient loop (sine-shaped, autoreversing).
    static let ambient = Animation.timingCurve(0.37, 0, 0.63, 1, duration: Motion.ambientPeriod / 2)

    /// The system-wide Reduce Motion preference, for AppKit and non-View code.
    static var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Returns `animation`, or a short fade when Reduce Motion is on.
    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? self.fade : animation
    }

    /// Entrance transition: rise 6pt and fade in; exit: fade out quickly.
    static func transition(reduceMotion: Bool, edge: Edge = .bottom) -> AnyTransition {
        guard !reduceMotion else { return .opacity.animation(self.fade) }
        let offset: CGFloat = edge == .top ? -6 : 6
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: offset)).animation(self.enter),
            removal: .opacity.animation(self.exit)
        )
    }
}

/// Runs `body` with a motion token, honoring Reduce Motion. Use instead of `withAnimation`.
@discardableResult
func withMotion<Result>(_ animation: Animation = Motion.state, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(Motion.resolved(animation, reduceMotion: Motion.prefersReducedMotion), body)
}

extension View {
    /// `.animation(_:value:)` that honors Reduce Motion.
    func motion<V: Equatable>(_ animation: Animation = Motion.state, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }

    /// Standard entrance/exit transition that honors Reduce Motion.
    func motionTransition(edge: Edge = .bottom) -> some View {
        modifier(MotionTransitionModifier(edge: edge))
    }

    /// Repeating ambient animation (pulse, breathing). Stops entirely with Reduce Motion
    /// and when `isActive` is false.
    func ambientPulse(isActive: Bool, minOpacity: Double = 0.45) -> some View {
        modifier(AmbientPulseModifier(isActive: isActive, minOpacity: minOpacity))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(Motion.resolved(self.animation, reduceMotion: self.reduceMotion), value: self.value)
    }
}

private struct MotionTransitionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let edge: Edge

    func body(content: Content) -> some View {
        content.transition(Motion.transition(reduceMotion: self.reduceMotion, edge: self.edge))
    }
}

private struct AmbientPulseModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isActive: Bool
    let minOpacity: Double
    @State private var isDimmed = false

    func body(content: Content) -> some View {
        let running = self.isActive && !self.reduceMotion
        content
            .opacity(running && self.isDimmed ? self.minOpacity : 1)
            .onAppear { self.update(running: running) }
            .onChange(of: running) { _, newValue in self.update(running: newValue) }
    }

    private func update(running: Bool) {
        if running {
            withAnimation(Motion.ambient.repeatForever(autoreverses: true)) {
                self.isDimmed = true
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { self.isDimmed = false }
        }
    }
}
