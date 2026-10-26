import DesignSystem
import NightKit
import SwiftUI

/// The wind-down's sky, drawn in one `Canvas` from a single number: progress `p` (0...1). The night
/// color moving toward the deep, ivory stars fading in (12 at the start, 24 by the end), a 64pt ivory
/// crescent travelling along a gentle arc, and two flat hills that sink 24pt. All flat, all static
/// between one second's read of the clock and the next, nothing in a `TimelineView`, so nothing here
/// runs faster than that (APP_RULES.md R32).
struct WindDownScene: View {
    /// The progress to draw (already snapped to a checkpoint under Reduce Motion).
    let progress: Double
    /// Behind something opened over the session (Sounds, Breathing, ...): the same sky color and hills,
    /// the moon at rest in the top corner beside the way back, and stars only in the strip above it, so
    /// nothing is drawn behind the words and controls that fill the rest of the screen.
    var backdrop = false

    /// Where the moon rests in a backdrop: the top corner opposite the back button, level with it (top-right; top-left in a
    /// right-to-left language, where the back button moves to the right and the moon would otherwise sit on its words).
    static func backdropMoon(isRightToLeft: Bool) -> (x: Double, y: Double) {
        (x: isRightToLeft ? 0.14 : 0.86, y: 0.105)
    }
    /// Stars in a backdrop stay above this fraction of the height.
    static let backdropStarLimit = 0.1

    struct Star: Sendable {
        let x: Double
        let y: Double
        let radius: Double
        let alpha: Double
    }

    /// The strips of sky (fractions of the height) that no state's words or controls reach: above the
    /// header, between the header and the first control, and between the controls and the hills. A star
    /// is only ever placed in one, so none sits behind a letter or shows through a chip.
    static let skyBands: [(range: ClosedRange<Double>, weight: Double)] = [
        (0.055...0.092, 0.12),
        (0.19...0.38, 0.60),
        (0.61...0.70, 0.28),
    ]

    /// 24 stars, placed once: the first 12 are there at the start, the rest arrive one by one.
    static let stars: [Star] = {
        var seed: UInt64 = 0x57A2_5EED
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double((seed >> 33) & 0xFFFFFF) / Double(0x1000000)
        }
        return (0..<WindDownVisuals.starsAtEnd).map { _ in
            var pick = next()
            var band = skyBands[skyBands.count - 1]
            for candidate in skyBands {
                if pick < candidate.weight {
                    band = candidate
                    break
                }
                pick -= candidate.weight
            }
            let x = 0.04 + 0.92 * next()
            let y = band.range.lowerBound + (band.range.upperBound - band.range.lowerBound) * next()
            return Star(x: x, y: y, radius: 0.9 + 0.9 * next(), alpha: 0.5 + 0.4 * next())
        }
    }()

    /// At accessibility sizes the words grow into the sky and the moon and stars (placed by fraction of the height, beside no text only at
    /// the default size) would sit behind them: like the tab fields' motifs, they are left out there; the hills and the night colour stay.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        let showsSky = backdrop || !dynamicTypeSize.isAccessibilitySize
        let backdropMoon = Self.backdropMoon(isRightToLeft: layoutDirection == .rightToLeft)
        return Canvas { context, size in
            let p = progress
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(NoctisNight.sky(WindDownVisuals.background(p))))

            // Stars: a star past the twelfth fades in over the 4% of the session before it counts.
            let count = WindDownVisuals.starCount(p)
            for (index, star) in Self.stars.enumerated() where showsSky {
                if backdrop, star.y >= Self.backdropStarLimit { continue }
                var alpha = star.alpha
                if index >= WindDownVisuals.starsAtStart {
                    let arrives = Double(index - WindDownVisuals.starsAtStart + 1) / Double(WindDownVisuals.starsAtEnd - WindDownVisuals.starsAtStart)
                    alpha *= min(max((p - (arrives - 0.04)) / 0.04, 0), 1)
                } else if index >= count {
                    alpha = 0
                }
                guard alpha > 0 else { continue }
                let r = star.radius
                let rect = CGRect(x: star.x * size.width - r, y: star.y * size.height - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(NoctisNight.ivory.opacity(alpha)))
            }

            // The moon: a 64pt ivory crescent along its arc.
            let moon = backdrop ? backdropMoon : WindDownVisuals.moon(p)
            let center = CGPoint(x: moon.x * size.width, y: moon.y * size.height)
            let radius: CGFloat = 32
            let disc = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            let bite = Path(ellipseIn: CGRect(x: center.x - radius * 0.45, y: center.y - radius * 1.1, width: radius * 1.9, height: radius * 1.9))
            if showsSky { context.fill(disc.subtracting(bite), with: .color(NoctisNight.moon)) }

            // The hills: two flat silhouettes that sink as the session goes on.
            let sink = CGFloat(WindDownVisuals.hillSink(p))
            context.fill(Self.hill(size: size, top: size.height * 0.74 + sink, rise: 46, phase: 0.2), with: .color(NoctisNight.hillBack))
            context.fill(Self.hill(size: size, top: size.height * 0.82 + sink, rise: 38, phase: 0.75), with: .color(NoctisNight.hillFront))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// A gentle rolling ridge across the width, filled to below the screen.
    static func hill(size: CGSize, top: CGFloat, rise: CGFloat, phase: Double) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height + 200))
        path.addLine(to: CGPoint(x: 0, y: top))
        let steps = 24
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            let y = top - rise * CGFloat(0.5 + 0.5 * sin((t + phase) * 2 * .pi * 0.9))
            path.addLine(to: CGPoint(x: size.width * CGFloat(t), y: y))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height + 200))
        path.closeSubpath()
        return path
    }
}
