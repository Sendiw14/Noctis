import SwiftUI

/// Keeps scrolled content from showing behind the status bar (on screens
/// without a navigation bar): a paper scrim, solid under the status bar
/// and fading out over 16pt below it. The one implementation on every
/// supported OS, so the system's own top scroll edge effect is turned off
/// rather than stacked under it.
struct NoctisStatusBarGuard: ViewModifier {
    var washes: [NoctisWash] = []

    func body(content: Content) -> some View {
        content
            .scrollEdgeEffectHidden(true, for: .top)
            .overlay(alignment: .top) { NoctisStatusBarScrim(washes: washes) }
    }
}

/// A flat color laid over the paper at some opacity (Home's evening paper
/// and the morning reveal's dusk), which the scrim must wear too.
public struct NoctisWash: Equatable, Sendable {
    public let color: Color
    public let opacity: Double

    public init(_ color: Color, opacity: Double) {
        self.color = color
        self.opacity = opacity
    }
}

/// Paper under the status bar, then a 16pt fade. The scroll view's own
/// frame stops at the safe area (its content draws above it because
/// clipping is off), so the fade sits at the top of that frame — the
/// safe-area line — and a solid paper block extends straight up from it,
/// taller than any status bar.
struct NoctisStatusBarScrim: View {
    static let fadeHeight: CGFloat = 16
    static let coverHeight: CGFloat = 200
    /// Flat colors laid over the paper, bottom first, while the background
    /// behind the content wears them too.
    var washes: [NoctisWash] = []
    /// The scrim's color: the paper, or a section field's color while the
    /// field is what shows under the status bar.
    var fill: Color = NoctisAppColor.bg

    var body: some View {
        ZStack {
            LinearGradient(colors: [fill, fill.opacity(0)], startPoint: .top, endPoint: .bottom)
            ForEach(Array(washes.enumerated()), id: \.offset) { _, wash in
                LinearGradient(colors: [wash.color, wash.color.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .opacity(wash.opacity)
            }
        }
        .frame(height: Self.fadeHeight)
        .background(alignment: .top) {
            ZStack {
                fill
                ForEach(Array(washes.enumerated()), id: \.offset) { _, wash in
                    wash.color.opacity(wash.opacity)
                }
            }
            .frame(height: Self.coverHeight)
            .offset(y: -Self.coverHeight)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Nothing renders behind the status bar (R14).
    public func noctisStatusBarGuard() -> some View {
        modifier(NoctisStatusBarGuard())
    }

    /// The same, with flat `washes` over the scrim's paper, matching a
    /// background that wears them.
    public func noctisStatusBarGuard(washes: [NoctisWash]) -> some View {
        modifier(NoctisStatusBarGuard(washes: washes))
    }
}
