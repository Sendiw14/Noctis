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
        return AnimatableVector(values: (0..<count).map { index in
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
