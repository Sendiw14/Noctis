import DesignSystem
import HomeFeature
import NoctisCore
import SwiftUI

// The small parts the Sleep charts are built from: layouts that place things
// by a share of a chart's height (the width ones live in DesignSystem), the
// shapes that scale unit-space points from the render model into a size, the
// selection pill's row and the scrub gesture. Nothing here computes what a
// chart means; it places and draws what the render model says (R23).

// MARK: - Shapes

/// A smooth line through unit-space points: one per night, centered in its
/// column, `nil` where nothing was recorded (the line breaks there). A lone
/// point is a dot. Catmull-Rom through the points, so it passes through
/// every real value.
nonisolated struct SleepSmoothLine: Shape {
    let points: [Double?]
    /// True when 0 is the bottom (a balance); false when 0 is the top (a
    /// clock axis, earliest first).
    let bottomUp: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var run: [CGPoint] = []
        for (index, value) in points.enumerated() {
            guard let value else {
                Self.add(run, to: &path)
                run = []
                continue
            }
            run.append(Self.point(index: index, count: points.count, value: value, bottomUp: bottomUp, in: rect))
        }
        Self.add(run, to: &path)
        return path
    }

    static func point(index: Int, count: Int, value: Double, bottomUp: Bool, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + rect.width * (Double(index) + 0.5) / Double(max(count, 1)),
            y: rect.minY + rect.height * (bottomUp ? 1 - value : value)
        )
    }

    private static func add(_ run: [CGPoint], to path: inout Path) {
        guard let first = run.first else { return }
        if run.count == 1 {
            path.addEllipse(in: CGRect(x: first.x - 2, y: first.y - 2, width: 4, height: 4))
            return
        }
        path.move(to: first)
        for index in 1..<run.count {
            let p0 = run[max(index - 2, 0)]
            let p1 = run[index - 1]
            let p2 = run[index]
            let p3 = run[min(index + 1, run.count - 1)]
            path.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            )
        }
    }
}

/// A dot on the newest recorded point of a `SleepSmoothLine`.
nonisolated struct SleepLastPoint: Shape {
    let points: [Double?]
    let bottomUp: Bool
    var radius: CGFloat = 4.5

    func path(in rect: CGRect) -> Path {
        guard let index = points.lastIndex(where: { $0 != nil }), let value = points[index] else { return Path() }
        let center = SleepSmoothLine.point(index: index, count: points.count, value: value, bottomUp: bottomUp, in: rect)
        return Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}

/// A horizontal rule across a chart at a share of its height (0 = bottom).
nonisolated struct SleepRule: Shape {
    let fraction: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y = rect.minY + rect.height * (1 - min(max(fraction, 0), 1))
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addLine(to: CGPoint(x: rect.maxX, y: y))
        return path
    }
}

nonisolated struct SleepDashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - Legends

/// A row of keys that drops to a column when they don't fit the width
/// (larger type).
struct SleepLegend<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: NoctisSpacing.md) { content }
            VStack(alignment: .leading, spacing: 6) { content }
        }
    }
}

// MARK: - Selection

/// The selection pill's row above a chart: reserved whether or not
/// anything is selected, so nothing moves and the pill never covers a bar;
/// text too wide for the row (accessibility sizes) wraps and grows upward.
struct SleepPillRow: View {
    let text: String?
    /// Where along the chart the pill centers, 0...1.
    let fraction: Double
    /// What the row says while nothing is selected ("30-night average 78").
    var resting: String?
    @NoctisScaledLength(relativeTo: .footnote) private var height: CGFloat = 28

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            if text == nil, let resting {
                Text(resting)
                    .noctisFont(15, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(NoctisAppColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            if let text {
                NoctisFractionLayout(wraps: true) {
                    HomePill(text: text)
                        .noctisFraction(fraction)
                }
                .transition(.opacity)
            }
        }
        // The resting line is a text: at accessibility sizes it wraps and the row grows with it instead of printing over the caption above (QA part 4, SE AX3).
        .frame(minHeight: height, maxHeight: text == nil && resting != nil ? nil : height, alignment: .bottom)
        .allowsHitTesting(false)
    }
}

extension View {
    /// Picking a night on a chart: a sideways drag follows the finger, a
    /// tap picks (or clears) one, an up-and-down drag is the page scrolling
    /// (Home's `columnScrub`, with the card padding and screen margin as
    /// the outer columns' reach).
    func sleepScrub(count: Int, chartWidth: CGFloat, selected: Binding<Int?>) -> some View {
        columnScrub(count: count, chartWidth: chartWidth, outset: NoctisSpacing.lg + NoctisSpacing.lg, selected: selected)
    }
}
