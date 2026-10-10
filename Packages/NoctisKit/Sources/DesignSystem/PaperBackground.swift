import SwiftUI

/// The root of every non-Welcome onboarding screen (R1): flat ivory with a
/// faint 3% grain so the paper doesn't read as a dead, perfectly flat
/// fill. A single seeded `Canvas` pass, not animated — R2 bans glow/blur on
/// content, and grain is texture, not motion.
///
/// Onboarding uses the fixed light paper. The main app passes
/// `adaptive: true` for `NoctisAppColor.bg`, which follows Light/Dark
/// (APP_RULES.md R1, R5).
public struct PaperBackground: View {
    private let adaptive: Bool
    @Environment(\.colorScheme) private var colorScheme

    public init(adaptive: Bool = false) {
        self.adaptive = adaptive
    }

    public var body: some View {
        ZStack {
            adaptive ? NoctisAppColor.bg : NoctisPaper.bg
            grain
        }
        .accessibilityHidden(true)
    }

    private var isDarkPaper: Bool { adaptive && colorScheme == .dark }

    private var grain: some View {
        // Dark specks and light specks: ink and white on light paper,
        // black and ivory ink on dark paper.
        let speckA = isDarkPaper ? Color.black : NoctisPaper.ink
        let speckB = isDarkPaper ? NoctisAppColor.ink : Color.white
        return Canvas { context, size in
            var generator = PaperGrainGenerator(seed: 11)
            let count = Int(size.width * size.height / 900)
            for _ in 0..<count {
                let x = CGFloat.random(in: 0...size.width, using: &generator)
                let y = CGFloat.random(in: 0...size.height, using: &generator)
                let isDark = Bool.random(using: &generator)
                let opacity = Double.random(in: 0.015...0.03, using: &generator)
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color((isDark ? speckA : speckB).opacity(opacity))
                )
            }
        }
        .drawingGroup()
    }
}
