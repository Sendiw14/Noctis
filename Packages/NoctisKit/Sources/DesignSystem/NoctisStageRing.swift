import SwiftUI

/// Angular layout of the `SampleNight` hypnogram ring, shared by drawing
/// (`NoctisStageRing`), and by Sample's tap hit-testing, drag scrubbing and
/// accessibility adjustable action: 14 hypnogram segments swept clockwise
/// from the top, 4° gaps between adjacent segments, the remaining 360°
/// split proportionally by each segment's share of the night.
public enum NoctisStageRingLayout {
    public static let gapDegrees: Double = 4
    public static let totalGapDegrees = gapDegrees * Double(SampleNight.segments.count - 1)
    public static let sweepDegrees = 360 - totalGapDegrees

    public struct Slot: Sendable {
        public let index: Int
        public let stage: SampleSleepStage
        public let minutes: Int
        public let minutesBeforeInNight: Int
        public let startDegrees: Double
        public let endDegrees: Double
    }

    public static let slots: [Slot] = {
        var result: [Slot] = []
        var elapsedMinutes = 0
        var cursor: Double = 0
        for (index, segment) in SampleNight.segments.enumerated() {
            let span = Double(segment.minutes) / Double(SampleNight.totalMinutes) * sweepDegrees
            result.append(
                Slot(
                    index: index,
                    stage: segment.stage,
                    minutes: segment.minutes,
                    minutesBeforeInNight: elapsedMinutes,
                    startDegrees: cursor,
                    endDegrees: cursor + span
                )
            )
            cursor += span + gapDegrees
            elapsedMinutes += segment.minutes
        }
        return result
    }()

    /// The point on the ring at `nightDegrees` (0 = top, clockwise).
    public static func point(at nightDegrees: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let cgAngle = (nightDegrees - 90) * .pi / 180
        return CGPoint(x: center.x + radius * cos(cgAngle), y: center.y + radius * sin(cgAngle))
    }

    /// The night-angle (0-360, clockwise from top) of a screen point
    /// relative to `center` — the inverse of `point(at:center:radius:)`.
    public static func degrees(of point: CGPoint, center: CGPoint) -> Double {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let cgAngle = atan2(dy, dx) * 180 / .pi
        let nightAngle = cgAngle + 90
        return nightAngle < 0 ? nightAngle + 360 : nightAngle
    }

    /// The slot whose swept span contains `nightDegrees`, or the nearest
    /// one if it falls inside a gap.
    public static func slot(atDegrees nightDegrees: Double) -> Slot {
        for slot in slots where nightDegrees >= slot.startDegrees && nightDegrees <= slot.endDegrees {
            return slot
        }
        return slots.min { abs(midpointDistance($0, nightDegrees)) < abs(midpointDistance($1, nightDegrees)) } ?? slots[0]
    }

    private static func midpointDistance(_ slot: Slot, _ degrees: Double) -> Double {
        let mid = (slot.startDegrees + slot.endDegrees) / 2
        let diff = abs(mid - degrees)
        return min(diff, 360 - diff)
    }

    public static func percent(of minutes: Int) -> Int {
        Int((Double(minutes) / Double(SampleNight.totalMinutes) * 100).rounded())
    }
}

/// The segmented Sleep Ring drawn from `SampleNight` (R2: solid arcs, no
/// gradients) — the one ring implementation shared by Sample (with its own
/// center number, scrub dot and entrance moon layered on top) and the
/// Paywall hero (bare, center hidden). Conforms to `Animatable` so a caller
/// can sweep it in with a plain `withAnimation { progress = 1 }`.
public struct NoctisStageRing: View, Animatable {
    public var progress: Double
    private let diameter: CGFloat
    private let lineWidth: CGFloat
    private let highlightedStage: SampleSleepStage?

    public init(progress: Double = 1, diameter: CGFloat, lineWidth: CGFloat, highlightedStage: SampleSleepStage? = nil) {
        self.progress = progress
        self.diameter = diameter
        self.lineWidth = lineWidth
        self.highlightedStage = highlightedStage
    }

    public var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    public var body: some View {
        Canvas { context, size in
            draw(context: context, size: size)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    private func draw(context: GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = size.width / 2 - lineWidth / 2

        var trackPath = Path()
        trackPath.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        context.stroke(trackPath, with: .color(NoctisPaper.track), style: StrokeStyle(lineWidth: lineWidth))

        let revealedDegrees = min(max(progress, 0), 1) * 360

        // Target a 3° VISIBLE gap, measured on the outer edge after the
        // round cap's own bulge. Two adjacent slots are `gapDegrees` (4°)
        // apart; insetting each drawn end by `x` moves its visible edge by
        // `x - capDegrees`, so `4 + 2x - 2·capDegrees = 3` gives
        // `x = capDegrees - 0.5`.
        let capDegrees = radius > 0 ? (lineWidth / 2 / radius) * (180 / .pi) : 0
        let insetDegrees = max(capDegrees - 0.5, 0)

        // Same-stage slots under 6° apart merge into one span before any
        // inset — including across the 0°/360° wrap, where the slot math
        // leaves ~0° between the night's first and last segments.
        var mergedSpans: [(stage: SampleSleepStage, start: Double, end: Double)] = []
        for slot in NoctisStageRingLayout.slots {
            let visibleEnd = min(slot.endDegrees, revealedDegrees)
            guard visibleEnd > slot.startDegrees else { continue }
            if let last = mergedSpans.last, last.stage == slot.stage, slot.startDegrees - last.end < 6 {
                mergedSpans[mergedSpans.count - 1].end = visibleEnd
            } else {
                mergedSpans.append((slot.stage, slot.startDegrees, visibleEnd))
            }
        }
        if mergedSpans.count > 1, revealedDegrees >= 360,
           let first = mergedSpans.first, let last = mergedSpans.last, first.stage == last.stage,
           (360 - last.end) + first.start < 6 {
            let wrapped = (stage: first.stage, start: last.start, end: first.end + 360)
            mergedSpans.removeFirst()
            mergedSpans.removeLast()
            mergedSpans.append(wrapped)
        }

        for span in mergedSpans {
            let dimmed = highlightedStage != nil && highlightedStage != span.stage
            let color = span.stage.color.opacity(dimmed ? 0.25 : 1)
            let insetStart = span.start + insetDegrees
            let insetEnd = span.end - insetDegrees
            // Never a stubby capsule: under 8° after inset draws as a dot.
            if insetEnd - insetStart >= 8 {
                let path = arcPath(from: insetStart, to: insetEnd, center: center, radius: radius)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            } else {
                let mid = (span.start + span.end) / 2
                let dotPoint = NoctisStageRingLayout.point(at: mid, center: center, radius: radius)
                let dotRadius = lineWidth / 2
                let dotPath = Path(ellipseIn: CGRect(x: dotPoint.x - dotRadius, y: dotPoint.y - dotRadius, width: lineWidth, height: lineWidth))
                context.fill(dotPath, with: .color(color))
            }
        }
    }

    private func arcPath(from startDegrees: Double, to endDegrees: Double, center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        let span = endDegrees - startDegrees
        let steps = max(Int(span / 3), 1)
        for i in 0...steps {
            let t = startDegrees + span * Double(i) / Double(steps)
            let point = NoctisStageRingLayout.point(at: t, center: center, radius: radius)
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}
