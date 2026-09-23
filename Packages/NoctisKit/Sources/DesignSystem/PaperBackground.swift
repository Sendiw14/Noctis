import SwiftUI

/// The root of every non-Welcome onboarding screen (R1): flat ivory with a
/// faint 3% grain so the paper doesn't read as a dead, perfectly flat
/// fill. A single seeded `Canvas` pass, not animated — R2 bans glow/blur on
/// content, and grain is texture, not motion.
public struct PaperBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            NoctisPaper.bg
            grain
        }
        .accessibilityHidden(true)
    }

    private var grain: some View {
        Canvas { context, size in
            var generator = SeededGenerator(seed: 11)
            let count = Int(size.width * size.height / 900)
            for _ in 0..<count {
                let x = CGFloat.random(in: 0...size.width, using: &generator)
                let y = CGFloat.random(in: 0...size.height, using: &generator)
                let isDark = Bool.random(using: &generator)
                let opacity = Double.random(in: 0.015...0.03, using: &generator)
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color((isDark ? NoctisPaper.ink : Color.white).opacity(opacity))
                )
            }
        }
        .drawingGroup()
    }
}
