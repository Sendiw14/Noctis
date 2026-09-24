import SwiftUI

/// Keeps scrolled content from showing behind the status bar (on screens
/// without a navigation bar). iOS 26 and later: the system's soft scroll
/// edge effect. iOS 18: a paper-colored scrim, solid under the status bar
/// and fading out over 16pt below it.
struct NoctisStatusBarGuard: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if Self.forceScrim {
                // Simulating iOS 18 on a newer OS: no system edge effect.
                content
                    .scrollEdgeEffectHidden(true, for: .top)
                    .overlay(alignment: .top) { NoctisStatusBarScrim() }
            } else {
                content.scrollEdgeEffectStyle(.soft, for: .top)
            }
        } else {
            content.overlay(alignment: .top) { NoctisStatusBarScrim() }
        }
    }

    #if DEBUG
    /// `-noctisStatusBarScrim`: the iOS 18 scrim on a newer simulator.
    static let forceScrim = ProcessInfo.processInfo.arguments.contains("-noctisStatusBarScrim")
    #else
    static let forceScrim = false
    #endif
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
    /// Nothing renders behind the status bar (R2, iOS 18 and 26+).
    public func noctisStatusBarGuard() -> some View {
        modifier(NoctisStatusBarGuard())
    }
}
