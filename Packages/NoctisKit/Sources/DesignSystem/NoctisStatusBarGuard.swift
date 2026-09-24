import SwiftUI

/// Keeps scrolled content from showing behind the status bar (on screens
/// without a navigation bar): a paper scrim, solid under the status bar
/// and fading out over 16pt below it. The one implementation on every
/// supported OS, so the system's own top scroll edge effect is turned off
/// rather than stacked under it.
struct NoctisStatusBarGuard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollEdgeEffectHidden(true, for: .top)
            .overlay(alignment: .top) { NoctisStatusBarScrim() }
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

    var body: some View {
        LinearGradient(colors: [NoctisAppColor.bg, NoctisAppColor.bg.opacity(0)], startPoint: .top, endPoint: .bottom)
            .frame(height: Self.fadeHeight)
            .background(alignment: .top) {
                NoctisAppColor.bg
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
}
