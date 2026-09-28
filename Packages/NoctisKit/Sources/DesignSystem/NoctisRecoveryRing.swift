import SwiftUI

/// One factor's slice of the recovery ring.
public struct NoctisRingSegment: Equatable, Sendable {
    public let color: Color
    /// Share of the ring (any positive scale; normalized across segments).
    public let weight: Double
    /// Filled share of the segment, 0...1 (a factor score / 100).
    public let fraction: Double
    /// Where your usual sits on the segment, 0...1 (your usual score /
    /// 100); nil without a baseline. Drawn as a tick when the ring asks.
    public let usual: Double?

    public init(color: Color, weight: Double, fraction: Double, usual: Double? = nil) {
        self.color = color
        self.weight = weight
        self.fraction = fraction
        self.usual = usual
    }
}

/// Angular layout of the recovery ring: segments swept clockwise from the
/// top, 3° visible gaps between them, the rest split by weight.
public enum NoctisRecoveryRingLayout {
    public static let gapDegrees: Double = 3

    /// (start, end) in degrees, 0 = top, for each weight in order.
    public static func arcs(weights: [Double]) -> [(start: Double, end: Double)] {
        let total = weights.reduce(0) { $0 + max($1, 0) }
        guard total > 0 else { return [] }
        let sweep = 360 - gapDegrees * Double(weights.count)
        var cursor = gapDegrees / 2
        return weights.map { weight in
            let span = max(weight, 0) / total * sweep
            defer { cursor += span + gapDegrees }
            return (cursor, cursor + span)
        }
    }

    /// The angle (degrees, 0 = top, clockwise) of the "usual" tick on the
    /// segment at `index`: `usual` (0...1) of the way along that segment's
    /// arc. Segments are laid out by weight, so a missing factor's
    /// renormalized weights move every tick with its segment.
    public static func tickAngle(weights: [Double], index: Int, usual: Double) -> Double? {
        let arcs = arcs(weights: weights)
        guard arcs.indices.contains(index) else { return nil }
        let arc = arcs[index]
        return arc.start + (arc.end - arc.start) * min(max(usual, 0), 1)
    }

    /// How much of each segment's fill is showing at `reveal` (0...1):
    /// segments fill one after another, each taking its share of the
    /// sweep, so the ring draws around in one continuous pass.
    public static func visibleFractions(weights: [Double], fractions: [Double], reveal: Double) -> [Double] {
        let total = weights.reduce(0) { $0 + max($1, 0) }
        guard total > 0 else { return fractions.map { _ in 0 } }
        var start = 0.0
        return zip(weights, fractions).map { weight, fraction in
            let share = max(weight, 0) / total
            defer { start += share }
            let progress = share > 0 ? min(max((reveal - start) / share, 0), 1) : 0
            return min(max(fraction, 0), 1) * progress
        }
    }
}

/// The recovery ring, from the Sample ring's drawing family (`NoctisStageRing`):
/// flat round-capped arcs on a `Canvas`, fixed 3° visible gaps. Each
/// segment is a track with a filled part. With no segments it's dormant:
/// a plain track circle. `Animatable` over `reveal` (the daily
/// draw-in), `dim` (every segment but `highlight` fading to 40%) and each
/// segment's fill (a live update moves only what changed).
///
/// R21: the ring sizes from the width it's offered, never from a device
/// constant — `diameter` is its largest size, and the stroke scales with
/// it (`lineWidth` at `diameter`).
public struct NoctisRecoveryRing: View, Animatable {
    public var reveal: Double
    /// 0...1: how far every segment but `highlight` has faded toward 40%.
    public var dim: Double
    private var fractions: [Double]
    private let segments: [NoctisRingSegment]
    private let showsUsual: Bool
    private let highlight: Int?
    private let diameter: CGFloat
    private let lineWidthAtFullSize: CGFloat

    /// Dimmed segments settle at this opacity.
    public static let dimmedOpacity = 0.4
    /// The "usual" tick's width.
    public static let tickWidth: CGFloat = 3

    public init(
        segments: [NoctisRingSegment],
        reveal: Double = 1,
        highlight: Int? = nil,
        dim: Double = 0,
        showsUsual: Bool = false,
        diameter: CGFloat = 200,
        lineWidth: CGFloat = 18
    ) {
        self.segments = segments
        self.showsUsual = showsUsual
        self.fractions = segments.map(\.fraction)
        self.reveal = reveal
        self.highlight = highlight
        self.dim = dim
        self.diameter = diameter
        self.lineWidthAtFullSize = lineWidth
    }

    public var animatableData: AnimatablePair<Double, AnimatablePair<Double, NoctisAnimatableVector>> {
        get { AnimatablePair(reveal, AnimatablePair(dim, NoctisAnimatableVector(fractions))) }
        set {
            reveal = newValue.first
            dim = newValue.second.first
            fractions = newValue.second.second.values
        }
    }

    public var body: some View {
        Canvas { context, size in
            draw(context: context, size: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: diameter, maxHeight: diameter)
        // Redrawn every frame of the draw-in, the morph and live updates.
        .drawingGroup()
        .accessibilityHidden(true)
    }

    private func draw(context: GraphicsContext, size: CGSize) {
        let side = min(size.width, size.height)
        let lineWidth = lineWidthAtFullSize * side / diameter
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = side / 2 - lineWidth / 2
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)

        guard !segments.isEmpty else {
            var track = Path()
            track.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
            context.stroke(track, with: .color(NoctisAppColor.ringTrack), style: StrokeStyle(lineWidth: lineWidth))
            return
        }

        // A round cap bulges `capDegrees` past its arc's end; insetting both
        // ends by exactly that keeps the visible gap at the layout's 3°.
        let capDegrees = radius > 0 ? Double(lineWidth / 2 / radius) * 180 / .pi : 0
        let weights = segments.map(\.weight)
        let arcs = NoctisRecoveryRingLayout.arcs(weights: weights)
        // Mid-animation between different segment counts, fall back to the
        // target fills.
        let fills = fractions.count == segments.count ? fractions : segments.map(\.fraction)
        let visible = NoctisRecoveryRingLayout.visibleFractions(weights: weights, fractions: fills, reveal: reveal)
        let dimmed = 1 - (1 - Self.dimmedOpacity) * min(max(dim, 0), 1)

        for (index, arc) in arcs.enumerated() {
            var segmentContext = context
            if let highlight, highlight != index { segmentContext.opacity = dimmed }
            stroke(from: arc.start, to: arc.end, color: NoctisAppColor.ringTrack, capDegrees: capDegrees, context: segmentContext, center: center, radius: radius, style: style)
            let fraction = visible[index]
            guard fraction > 0 else { continue }
            let fillEnd = arc.start + (arc.end - arc.start) * fraction
            stroke(from: arc.start, to: fillEnd, color: segments[index].color, capDegrees: capDegrees, context: segmentContext, center: center, radius: radius, style: style)
        }

        // Your usual: a 3pt tick across each segment's track, on top of
        // its fill, once the ring has drawn in.
        guard showsUsual else { return }
        for (index, segment) in segments.enumerated() {
            guard let usual = segment.usual, let angle = NoctisRecoveryRingLayout.tickAngle(weights: weights, index: index, usual: usual) else { continue }
            var tickContext = context
            if let highlight, highlight != index { tickContext.opacity = dimmed }
            tickContext.opacity *= min(max((reveal - 0.9) / 0.1, 0), 1)
            let inner = NoctisStageRingLayout.point(at: angle, center: center, radius: radius - lineWidth / 2)
            let outer = NoctisStageRingLayout.point(at: angle, center: center, radius: radius + lineWidth / 2)
            var tick = Path()
            tick.move(to: inner)
            tick.addLine(to: outer)
            tickContext.stroke(tick, with: .color(NoctisAppColor.ink.opacity(0.7)), style: StrokeStyle(lineWidth: Self.tickWidth, lineCap: .butt))
        }
    }

    /// A capped arc whose visible ends sit at `start` and `end`; spans too
    /// short to hold both caps draw as a single dot at `start`.
    private func stroke(from start: Double, to end: Double, color: Color, capDegrees: Double, context: GraphicsContext, center: CGPoint, radius: CGFloat, style: StrokeStyle) {
        let lineWidth = style.lineWidth
        let insetStart = start + capDegrees
        let insetEnd = end - capDegrees
        if insetEnd - insetStart >= 0.5 {
            context.stroke(arcPath(from: insetStart, to: insetEnd, center: center, radius: radius), with: .color(color), style: style)
        } else {
            let point = NoctisStageRingLayout.point(at: min(insetStart, (start + end) / 2), center: center, radius: radius)
            let dot = Path(ellipseIn: CGRect(x: point.x - lineWidth / 2, y: point.y - lineWidth / 2, width: lineWidth, height: lineWidth))
            context.fill(dot, with: .color(color))
        }
    }

    private func arcPath(from startDegrees: Double, to endDegrees: Double, center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        let span = endDegrees - startDegrees
        let steps = max(Int(span / 3), 1)
        for i in 0...steps {
            let point = NoctisStageRingLayout.point(at: startDegrees + span * Double(i) / Double(steps), center: center, radius: radius)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// A ring with something in its middle (a score, a glyph), sized from the
/// width offered up to `maxDiameter` (R21). The first subview is the
/// ring, drawn square; every other subview is offered the box inside the
/// ring (`centerWidth` × `centerHeight` of the diameter), so text in it
/// shrinks with the ring.
public struct NoctisRingLayout: Layout {
    public var maxDiameter: CGFloat
    public var centerWidth: CGFloat
    public var centerHeight: CGFloat
    /// A smaller size for narrow spaces: offered less than
    /// `narrowBelowWidth`, the ring is at most `narrowDiameter`.
    public var narrowDiameter: CGFloat?
    public var narrowBelowWidth: CGFloat

    public init(
        maxDiameter: CGFloat,
        centerWidth: CGFloat = 0.7,
        centerHeight: CGFloat = 0.52,
        narrowDiameter: CGFloat? = nil,
        narrowBelowWidth: CGFloat = 0
    ) {
        self.maxDiameter = maxDiameter
        self.centerWidth = centerWidth
        self.centerHeight = centerHeight
        self.narrowDiameter = narrowDiameter
        self.narrowBelowWidth = narrowBelowWidth
    }

    /// The ring's diameter for an offered width: the width, capped at
    /// `maxDiameter` (nil or infinite offers get the full size).
    public static func diameter(forWidth width: CGFloat?, maxDiameter: CGFloat, narrowDiameter: CGFloat? = nil, narrowBelowWidth: CGFloat = 0) -> CGFloat {
        guard let width, width.isFinite else { return maxDiameter }
        let cap = width < narrowBelowWidth ? (narrowDiameter ?? maxDiameter) : maxDiameter
        return max(min(width, cap), 0)
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let side = Self.diameter(forWidth: proposal.width, maxDiameter: maxDiameter, narrowDiameter: narrowDiameter, narrowBelowWidth: narrowBelowWidth)
        return CGSize(width: side, height: side)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let side = min(bounds.width, bounds.height)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        for (index, subview) in subviews.enumerated() {
            let size = index == 0
                ? CGSize(width: side, height: side)
                : CGSize(width: side * centerWidth, height: side * centerHeight)
            subview.place(at: center, anchor: .center, proposal: ProposedViewSize(size))
        }
    }
}

#Preview("Recovery ring") {
    VStack(spacing: 24) {
        NoctisRecoveryRing(segments: [
            NoctisRingSegment(color: NoctisAppColor.sage, weight: 35, fraction: 0.91),
            NoctisRingSegment(color: NoctisAppColor.lavender, weight: 25, fraction: 0.78),
            NoctisRingSegment(color: NoctisAppColor.orange, weight: 20, fraction: 0.85),
            NoctisRingSegment(color: NoctisAppColor.butter, weight: 20, fraction: 0.74),
        ])
        NoctisRecoveryRing(segments: [], diameter: 120)
    }
    .padding()
}
