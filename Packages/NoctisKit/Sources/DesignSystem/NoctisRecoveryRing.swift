import SwiftUI

/// One segment's angles on the ring: the arc it covers (degrees, 0 = top,
/// clockwise, with the ring's gaps) and where your usual sits on it.
public nonisolated struct NoctisRingArc: Equatable, Sendable {
    public let startDegrees: Double
    public let endDegrees: Double
    /// The "usual" tick's angle; nil without a baseline.
    public let tickDegrees: Double?

    public init(startDegrees: Double, endDegrees: Double, tickDegrees: Double?) {
        self.startDegrees = startDegrees
        self.endDegrees = endDegrees
        self.tickDegrees = tickDegrees
    }
}

/// One factor's slice of the recovery ring.
public nonisolated struct NoctisRingSegment: Equatable, Sendable {
    public let color: Color
    /// Share of the ring (any positive scale; normalized across segments).
    public let weight: Double
    /// Filled share of the segment, 0...1 (a factor score / 100).
    public let fraction: Double
    /// Where your usual sits on the segment, 0...1 (your usual score /
    /// 100); nil without a baseline. Drawn as a tick when the ring asks.
    public let usual: Double?
    /// Its angles, from Home's render model. Without them the ring lays
    /// the segments out from their weights (previews, one-off rings).
    public let arc: NoctisRingArc?

    public init(color: Color, weight: Double, fraction: Double, usual: Double? = nil, arc: NoctisRingArc? = nil) {
        self.color = color
        self.weight = weight
        self.fraction = fraction
        self.usual = usual
        self.arc = arc
    }
}

/// Angular layout of the recovery ring: segments swept clockwise from the
/// top, 3° visible gaps between them, the rest split by weight.
public nonisolated enum NoctisRecoveryRingLayout {
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

    /// The segments with their angles filled in.
    public static func arranged(_ segments: [NoctisRingSegment]) -> [NoctisRingSegment] {
        guard segments.contains(where: { $0.arc == nil }) else { return segments }
        let weights = segments.map(\.weight)
        let arcs = arcs(weights: weights)
        guard arcs.count == segments.count else { return segments }
        return segments.enumerated().map { index, segment in
            NoctisRingSegment(
                color: segment.color, weight: segment.weight, fraction: segment.fraction, usual: segment.usual,
                arc: NoctisRingArc(
                    startDegrees: arcs[index].start,
                    endDegrees: arcs[index].end,
                    tickDegrees: segment.usual.flatMap { tickAngle(weights: weights, index: index, usual: $0) }
                )
            )
        }
    }
}

/// A ring's paths at one size, built ahead of time: for each segment its
/// track, its fill and its tick.
struct NoctisRingPaths: Equatable {
    struct Piece {
        let path: Path
        /// A dot (a span too short for two caps) is filled; an arc is
        /// stroked with round caps.
        let isDot: Bool
    }

    struct Segment {
        let color: Color
        let track: Piece
        let fill: Piece?
        let tick: Path?
    }

    let key: Key
    let lineWidth: CGFloat
    let segments: [Segment]
    /// With no segments: a plain track circle.
    let dormant: Path?

    struct Key: Equatable {
        let segments: [NoctisRingSegment]
        let side: CGFloat
        let diameter: CGFloat
        let lineWidthAtFullSize: CGFloat
    }

    static func == (lhs: NoctisRingPaths, rhs: NoctisRingPaths) -> Bool { lhs.key == rhs.key }

    static func build(_ key: Key) -> NoctisRingPaths {
        let side = key.side
        let lineWidth = key.lineWidthAtFullSize * side / key.diameter
        let center = CGPoint(x: side / 2, y: side / 2)
        let radius = side / 2 - lineWidth / 2
        guard !key.segments.isEmpty else {
            var track = Path()
            track.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
            return NoctisRingPaths(key: key, lineWidth: lineWidth, segments: [], dormant: track)
        }
        // A round cap bulges `capDegrees` past its arc's end; insetting both
        // ends by exactly that keeps the visible gap at the layout's 3°.
        let capDegrees = radius > 0 ? Double(lineWidth / 2 / radius) * 180 / .pi : 0
        let segments = NoctisRecoveryRingLayout.arranged(key.segments).map { segment -> Segment in
            let arc = segment.arc ?? NoctisRingArc(startDegrees: 0, endDegrees: 0, tickDegrees: nil)
            let fillEnd = arc.startDegrees + (arc.endDegrees - arc.startDegrees) * min(max(segment.fraction, 0), 1)
            var tick: Path?
            if let angle = arc.tickDegrees {
                var path = Path()
                path.move(to: NoctisStageRingLayout.point(at: angle, center: center, radius: radius - lineWidth / 2))
                path.addLine(to: NoctisStageRingLayout.point(at: angle, center: center, radius: radius + lineWidth / 2))
                tick = path
            }
            return Segment(
                color: segment.color,
                track: piece(from: arc.startDegrees, to: arc.endDegrees, capDegrees: capDegrees, lineWidth: lineWidth, center: center, radius: radius),
                fill: segment.fraction > 0
                    ? piece(from: arc.startDegrees, to: fillEnd, capDegrees: capDegrees, lineWidth: lineWidth, center: center, radius: radius)
                    : nil,
                tick: tick
            )
        }
        return NoctisRingPaths(key: key, lineWidth: lineWidth, segments: segments, dormant: nil)
    }

    /// A capped arc whose visible ends sit at `start` and `end`; spans too
    /// short to hold both caps are a single dot at `start`.
    private static func piece(from start: Double, to end: Double, capDegrees: Double, lineWidth: CGFloat, center: CGPoint, radius: CGFloat) -> Piece {
        let insetStart = start + capDegrees
        let insetEnd = end - capDegrees
        if insetEnd - insetStart >= 0.5 {
            var path = Path()
            let span = insetEnd - insetStart
            let steps = max(Int(span / 3), 1)
            for i in 0...steps {
                let point = NoctisStageRingLayout.point(at: insetStart + span * Double(i) / Double(steps), center: center, radius: radius)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            return Piece(path: path, isDot: false)
        }
        let point = NoctisStageRingLayout.point(at: min(insetStart, (start + end) / 2), center: center, radius: radius)
        return Piece(path: Path(ellipseIn: CGRect(x: point.x - lineWidth / 2, y: point.y - lineWidth / 2, width: lineWidth, height: lineWidth)), isDot: true)
    }
}

/// The recovery ring, from the Sample ring's drawing family (`NoctisStageRing`):
/// flat round-capped arcs, fixed 3° visible gaps. Each segment is a track
/// with a filled part, and a tick at your usual when asked. With no
/// segments it's dormant: a plain track circle.
///
/// Two cached layers, both drawing paths that were built ahead of time:
/// the tracks, and the fills with their ticks. The morning reveal never
/// redraws either: it animates one number, the angle of a pie-shaped mask
/// that sweeps the fill layer clockwise from the top. Only `dim` (every
/// segment but `highlight` fading to 40%) animates the ring itself, since
/// that changes what the layers show.
///
/// R21: the ring sizes from the width it's offered, never from a device
/// constant — `diameter` is its largest size, and the stroke scales with
/// it (`lineWidth` at `diameter`).
public struct NoctisRecoveryRing: View, Animatable {
    /// 0...1: how far the reveal's sweep has gone.
    public var reveal: Double
    /// 0...1: how far every segment but `highlight` has faded toward 40%.
    public var dim: Double
    private let segments: [NoctisRingSegment]
    private let showsUsual: Bool
    private let highlight: Int?
    private let diameter: CGFloat
    private let lineWidthAtFullSize: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var side: CGFloat = 0
    @State private var paths: NoctisRingPaths?
    /// While new values replace old ones: the ring that is fading out, and
    /// how far the new one has faded in (0...1).
    @State private var outgoing: NoctisRingPaths?
    @State private var incoming: Double = 1

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
        self.reveal = reveal
        self.highlight = highlight
        self.dim = dim
        self.diameter = diameter
        self.lineWidthAtFullSize = lineWidth
    }

    public var animatableData: Double {
        get { dim }
        set { dim = newValue }
    }

    private var key: NoctisRingPaths.Key {
        NoctisRingPaths.Key(segments: segments, side: side, diameter: diameter, lineWidthAtFullSize: lineWidthAtFullSize)
    }

    public var body: some View {
        ZStack {
            if let outgoing {
                layers(outgoing)
                    .opacity(1 - incoming)
            }
            if let paths {
                layers(paths)
                    .opacity(outgoing == nil ? 1 : incoming)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: diameter, maxHeight: diameter)
        .onGeometryChange(for: CGFloat.self) {
            min($0.size.width, $0.size.height)
        } action: {
            side = $0
        }
        .onChange(of: key, initial: true) { _, key in
            guard key.side > 0 else { return }
            let next = NoctisRingPaths.build(key)
            // New values on a ring that is already showing: the old ring
            // fades out as the new one fades in, a cross-fade that a
            // second change can interrupt (it's a spring on two opacities;
            // nothing is redrawn). A new size just replaces it.
            if let current = paths, current.key.segments != key.segments, current.key.side == key.side {
                outgoing = current
                incoming = 0
                paths = next
                withAnimation(NoctisMotion.adaptive(NoctisMotion.fade, reduceMotion: reduceMotion)) {
                    incoming = 1
                } completion: {
                    outgoing = nil
                }
            } else {
                outgoing = nil
                incoming = 1
                paths = next
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func layers(_ paths: NoctisRingPaths) -> some View {
        if let dormant = paths.dormant {
            NoctisRingDormantLayer(path: dormant, lineWidth: paths.lineWidth)
        } else {
            NoctisRingTrackLayer(paths: paths, dim: dim, highlight: highlight)
                .equatable()
            NoctisRingFillLayer(paths: paths, dim: dim, highlight: highlight, showsUsual: showsUsual)
                .equatable()
                .mask(NoctisRingSweep(progress: reveal))
        }
    }
}

/// The dimming a layer applies to one segment: 1 for the highlighted one
/// (or with no highlight), fading toward `dimmedOpacity` for the rest.
private func ringOpacity(_ index: Int, dim: Double, highlight: Int?) -> Double {
    guard let highlight, highlight != index else { return 1 }
    return 1 - (1 - NoctisRecoveryRing.dimmedOpacity) * min(max(dim, 0), 1)
}

private struct NoctisRingDormantLayer: View {
    let path: Path
    let lineWidth: CGFloat
    @Environment(\.noctisRingTrack) private var trackOverride

    var body: some View {
        let track = trackOverride ?? NoctisAppColor.ringTrack
        Canvas { context, _ in
            context.stroke(path, with: .color(track), style: StrokeStyle(lineWidth: lineWidth))
        }
        .drawingGroup()
    }
}

/// The tracks, one per segment, in one cached layer.
private struct NoctisRingTrackLayer: View, Equatable {
    let paths: NoctisRingPaths
    let dim: Double
    let highlight: Int?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.noctisRingTrack) private var trackOverride

    static func == (lhs: NoctisRingTrackLayer, rhs: NoctisRingTrackLayer) -> Bool {
        lhs.paths == rhs.paths && lhs.dim == rhs.dim && lhs.highlight == rhs.highlight
    }

    var body: some View {
        let _ = colorScheme
        let track = trackOverride ?? NoctisAppColor.ringTrack
        Canvas { context, _ in
            let style = StrokeStyle(lineWidth: paths.lineWidth, lineCap: .round)
            for (index, segment) in paths.segments.enumerated() {
                var layer = context
                layer.opacity = ringOpacity(index, dim: dim, highlight: highlight)
                if segment.track.isDot {
                    layer.fill(segment.track.path, with: .color(track))
                } else {
                    layer.stroke(segment.track.path, with: .color(track), style: style)
                }
            }
        }
        .drawingGroup()
    }
}

/// The fills and the usual ticks, in one cached layer that the reveal's
/// sweep masks.
private struct NoctisRingFillLayer: View, Equatable {
    let paths: NoctisRingPaths
    let dim: Double
    let highlight: Int?
    let showsUsual: Bool
    @Environment(\.colorScheme) private var colorScheme

    static func == (lhs: NoctisRingFillLayer, rhs: NoctisRingFillLayer) -> Bool {
        lhs.paths == rhs.paths && lhs.dim == rhs.dim && lhs.highlight == rhs.highlight && lhs.showsUsual == rhs.showsUsual
    }

    var body: some View {
        let _ = colorScheme
        Canvas { context, _ in
            let style = StrokeStyle(lineWidth: paths.lineWidth, lineCap: .round)
            for (index, segment) in paths.segments.enumerated() {
                var layer = context
                layer.opacity = ringOpacity(index, dim: dim, highlight: highlight)
                if let fill = segment.fill {
                    if fill.isDot {
                        layer.fill(fill.path, with: .color(segment.color))
                    } else {
                        layer.stroke(fill.path, with: .color(segment.color), style: style)
                    }
                }
                // Your usual: a 3pt tick across the segment's track, on top
                // of its fill.
                if showsUsual, let tick = segment.tick {
                    layer.stroke(
                        tick, with: .color(NoctisAppColor.ink.opacity(0.7)), style: StrokeStyle(lineWidth: NoctisRecoveryRing.tickWidth, lineCap: .butt))
                }
            }
        }
        .drawingGroup()
    }
}

/// A pie-shaped mask that sweeps clockwise from the top: the reveal.
private nonisolated struct NoctisRingSweep: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // Reaches the corners at any size.
        let radius = max(rect.width, rect.height)
        let sweep = min(max(progress, 0), 1)
        guard sweep > 0 else { return path }
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * sweep), clockwise: false)
        path.closeSubpath()
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
            let size =
                index == 0
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
