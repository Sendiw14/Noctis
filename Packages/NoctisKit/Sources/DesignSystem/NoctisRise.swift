import SwiftUI

/// R9's standard entrance for everything that isn't a screen's one hero
/// animation: a 12pt rise with a 60ms stagger per index, `.settle`-sprung.
/// Reduce Motion collapses every index to the same plain 0.2s fade — no
/// stagger, no offset — via `NoctisMotion.adaptive`.
private struct NoctisRiseModifier: ViewModifier {
    let index: Int
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 12)
            .onAppear {
                withAnimation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion).delay(reduceMotion ? 0 : Double(index) * 0.06)) {
                    appeared = true
                }
            }
    }
}

extension View {
    /// Applies the R9 staggered-rise entrance. `index` is the item's
    /// position among its siblings (0-based) — pass 0 for a standalone
    /// element.
    public func noctisRise(index: Int = 0) -> some View {
        modifier(NoctisRiseModifier(index: index))
    }
}
