import DesignSystem
import HomeFeature
import NoctisCore
import SwiftUI

// The small parts Recovery's charts are built from: a vector that shapes
// can animate, the curve shape that morphs between ranges, dot shapes, and
// the selection pill's row. Nothing here computes what a chart means; it
// scales and draws what the render model says (R23).

/// A run of numbers a `Shape` can animate: each value moves toward its
/// counterpart (a shorter side counts as zeros).
nonisolated struct AnimatableVector: VectorArithmetic, Equatable {
    var values: [Double]

    static let zero = AnimatableVector(values: [])

    static func + (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        combine(lhs, rhs, +)
    }

    static func - (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        combine(lhs, rhs, -)
    }

    private static func combine(_ lhs: AnimatableVector, _ rhs: AnimatableVector, _ operation: (Double, Double) -> Double) -> AnimatableVector {
        let count = max(lhs.values.count, rhs.values.count)
        return AnimatableVector(
            values: (0..<count).map { index in
                operation(index < lhs.values.count ? lhs.values[index] : 0, index < rhs.values.count ? rhs.values[index] : 0)
            })
    }

    mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }
}

/// A factor's line: `samples` (0...1 up, evenly spaced along the run) then
/// the number of nights the run covers. A night sits in the middle of its
/// column, so the curve starts and ends half a column in. Both change
/// together when the range does, and the line morphs.
nonisolated struct FactorCurve: Shape {
    var vector: AnimatableVector

    init(samples: [Double], nights: Int) {
        vector = AnimatableVector(values: samples + [Double(nights)])
    }

    var animatableData: AnimatableVector {
        get { vector }
        set { vector = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard vector.values.count > 2 else { return path }
        let samples = vector.values.dropLast()
        let nights = max(vector.values[vector.values.count - 1], 1)
        let first = 0.5 / nights
        let span = (nights - 1) / nights
        let count = Double(samples.count - 1)
        for (index, value) in samples.enumerated() {
            let x = rect.minX + rect.width * (first + span * Double(index) / count)
            let y = rect.minY + rect.height * (1 - min(max(value, 0), 1))
            index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}

/// A dot at each recorded night (0...1 up), one column each.
nonisolated struct FactorDots: Shape {
    let values: [Double?]
    var radius: CGFloat = 2.5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = Double(max(values.count, 1))
        for (index, value) in values.enumerated() {
            guard let value else { continue }
            let x = rect.minX + rect.width * (Double(index) + 0.5) / count
            let y = rect.minY + rect.height * (1 - min(max(value, 0), 1))
            path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }
        return path
    }
}

/// One dot, at a night's column and value.
nonisolated struct FactorMarker: Shape {
    let values: [Double?]
    let index: Int?
    var radius: CGFloat = 5.5

    func path(in rect: CGRect) -> Path {
        guard let index, values.indices.contains(index), let value = values[index] else { return Path() }
        let count = Double(max(values.count, 1))
        let x = rect.minX + rect.width * (Double(index) + 0.5) / count
        let y = rect.minY + rect.height * (1 - min(max(value, 0), 1))
        return Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    }
}

/// A short vertical stub at a night's column between two values: today's dot
/// joined to the smoothed line it sits against.
nonisolated struct ColumnSpan: Shape {
    let count: Int
    let index: Int?
    let from: Double?
    let to: Double?

    func path(in rect: CGRect) -> Path {
        guard let index, let from, let to else { return Path() }
        let x = rect.minX + rect.width * (Double(index) + 0.5) / Double(max(count, 1))
        func y(_ value: Double) -> Double { rect.minY + rect.height * (1 - min(max(value, 0), 1)) }
        var path = Path()
        path.move(to: CGPoint(x: x, y: y(from)))
        path.addLine(to: CGPoint(x: x, y: y(to)))
        return path
    }
}

/// A vertical hairline at a night's column.
nonisolated struct ColumnRule: Shape {
    let count: Int
    let index: Int?

    func path(in rect: CGRect) -> Path {
        guard let index else { return Path() }
        let x = rect.minX + rect.width * (Double(index) + 0.5) / Double(max(count, 1))
        var path = Path()
        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x, y: rect.maxY))
        return path
    }
}

/// The selection pill's row above a chart: reserved whether or not
/// anything is selected, so nothing moves and the pill never covers the
/// line; text too wide for the row (accessibility sizes) wraps and grows
/// upward.
struct RecoveryPillRow: View {
    let text: String?
    /// Where along the chart the pill centers, 0...1.
    let fraction: Double
    /// What the row says while nothing is selected.
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
        .frame(height: height, alignment: .bottom)
        .allowsHitTesting(false)
    }
}

/// A row of keys that drops to a column when they don't fit the width
/// (larger type).
struct RecoveryLegend<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: NoctisSpacing.md) { content }
            VStack(alignment: .leading, spacing: 6) { content }
        }
    }
}

// MARK: - The recovery line

/// The recovery line through a window's days (0...1 up, `nil` where a day
/// has no score, so the line breaks there): a Catmull-Rom curve through
/// every real value, a night in the middle of its column. A lone day is a
/// dot.
nonisolated struct SeriesLine: Shape {
    let values: [Double?]
    /// Close each run down to the bottom instead: the flat area under the line.
    var area = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var run: [CGPoint] = []
        let count = Double(max(values.count, 1))
        func flush() {
            Self.add(run, area: area, bottom: rect.maxY, to: &path)
            run = []
        }
        for (index, value) in values.enumerated() {
            guard let value else {
                flush()
                continue
            }
            run.append(
                CGPoint(
                    x: rect.minX + rect.width * (Double(index) + 0.5) / count,
                    y: rect.minY + rect.height * (1 - min(max(value, 0), 1))
                ))
        }
        flush()
        return path
    }

    private static func add(_ run: [CGPoint], area: Bool, bottom: CGFloat, to path: inout Path) {
        guard let first = run.first, let last = run.last else { return }
        if run.count == 1 {
            if !area { path.addEllipse(in: CGRect(x: first.x - 2, y: first.y - 2, width: 4, height: 4)) }
            return
        }
        path.move(to: area ? CGPoint(x: first.x, y: bottom) : first)
        if area { path.addLine(to: first) }
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
        if area {
            path.addLine(to: CGPoint(x: last.x, y: bottom))
            path.closeSubpath()
        }
    }
}

nonisolated struct RecoveryDashedRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
