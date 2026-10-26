import DesignSystem
import NoctisCore
import RecoveryKit
import SwiftUI

/// A sparkline's paths at one size, built ahead of time.
struct SparklinePaths: Equatable {
    let key: Key
    let band: Path
    let dots: Path
    let line: Path
    let today: Path

    struct Key: Equatable {
        let content: SparklineContent
        let size: CGSize
    }

    static func == (lhs: SparklinePaths, rhs: SparklinePaths) -> Bool { lhs.key == rhs.key }

    static func build(_ key: Key) -> SparklinePaths {
        let content = key.content
        let size = key.size
        let inset: CGFloat = 4
        let plotHeight = size.height - inset * 2
        func y(_ value: Double) -> CGFloat { inset + plotHeight * (1 - CGFloat(value)) }
        // Nights fill the width; today sits one step past the last.
        let steps = CGFloat(content.nights.count)
        let step = (size.width - inset * 2) / max(steps, 1)
        func x(_ index: Int) -> CGFloat { inset + step * CGFloat(index) }

        let bandTop = y(content.band.upperBound)
        let bandBottom = y(content.band.lowerBound)
        let band = Path(roundedRect: CGRect(x: 0, y: bandTop, width: size.width, height: max(bandBottom - bandTop, 1)), cornerRadius: 4)

        var line = Path()
        var dots = Path()
        var drawing = false
        for (index, value) in content.nights.enumerated() {
            guard let value else {
                drawing = false
                continue
            }
            let point = CGPoint(x: x(index), y: y(value))
            if drawing { line.addLine(to: point) } else { line.move(to: point) }
            drawing = true
            dots.addEllipse(in: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3))
        }
        let todayPoint = CGPoint(x: x(content.nights.count), y: y(content.today))
        if drawing { line.addLine(to: todayPoint) }
        return SparklinePaths(
            key: key, band: band, dots: dots, line: line,
            today: Path(ellipseIn: CGRect(x: todayPoint.x - 3, y: todayPoint.y - 3, width: 6, height: 6))
        )
    }
}

/// 14 nights, full row width: your normal range as a band in the factor's
/// color at 16%, a 2.5pt line through the nights in that color's line ink,
/// and today as a 6pt dot in the factor's color. Drawn from paths resolved
/// when the width or the values change.
public struct FactorSparkline: View {
    let content: SparklineContent
    let tint: Color
    let lineTint: Color

    public static let height: CGFloat = 36
    @State private var size: CGSize = .zero
    @State private var paths: SparklinePaths?

    public init(content: SparklineContent, tint: Color, lineTint: Color? = nil) {
        self.content = content
        self.tint = tint
        self.lineTint = lineTint ?? tint
    }

    public var body: some View {
        Group {
            if let paths {
                Canvas { context, _ in
                    context.fill(paths.band, with: .color(tint.opacity(0.16)))
                    context.stroke(paths.line, with: .color(lineTint), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    context.fill(paths.dots, with: .color(lineTint))
                    context.fill(paths.today, with: .color(tint))
                }
            } else {
                Color.clear
            }
        }
        .onGeometryChange(for: CGSize.self) {
            $0.size
        } action: {
            size = $0
        }
        .onChange(of: SparklinePaths.Key(content: content, size: size), initial: true) { _, key in
            guard key.size.width > 0, key.size.height > 0 else { return }
            paths = SparklinePaths.build(key)
        }
        .accessibilityHidden(true)
    }
}
