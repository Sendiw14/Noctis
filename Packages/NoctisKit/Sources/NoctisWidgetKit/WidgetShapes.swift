import DesignSystem
import SwiftUI
import WidgetKit

// The flat shapes widgets draw: the recovery ring's arcs and the stage strip. Shapes and Paths, not Canvas, so they render in a
// widget without a question (APP_RULES.md R44). Colors are the app's own tokens, light and dark; in an accented or vibrant widget
// the system flattens color, so the arcs and the stages are told apart by how strong they are.

/// How the widget is being drawn: its own full color, or the system's accented or vibrant treatment.
public struct WidgetPalette {
    let mode: WidgetRenderingMode

    public init(mode: WidgetRenderingMode) {
        self.mode = mode
    }

    var isFullColor: Bool { mode == .fullColor }

    /// The recovery arcs: sleep sage, HRV lavender, resting heart rate orange, consistency butter.
    func arc(_ kind: WidgetFactorKind) -> Color {
        guard isFullColor else { return .primary.opacity(strength(kind)) }
        switch kind {
        case .sleepDuration: return NoctisAppColor.sage
        case .hrv: return NoctisAppColor.lavender
        case .restingHeartRate: return NoctisAppColor.orange
        case .sleepConsistency: return NoctisAppColor.butter
        }
    }

    /// The factor's color as a dot or a line: deep enough to read on the paper.
    func line(_ kind: WidgetFactorKind) -> Color {
        guard isFullColor else { return .primary.opacity(strength(kind)) }
        switch kind {
        case .sleepDuration: return NoctisAppColor.sectionSage
        case .hrv: return NoctisAppColor.sectionLavender
        case .restingHeartRate: return NoctisAppColor.orangeText
        case .sleepConsistency: return NoctisAppColor.sectionButter
        }
    }

    private func strength(_ kind: WidgetFactorKind) -> Double {
        switch kind {
        case .sleepDuration: 1
        case .hrv: 0.78
        case .restingHeartRate: 0.58
        case .sleepConsistency: 0.42
        }
    }

    var track: Color { isFullColor ? NoctisAppColor.ringTrack : .primary.opacity(0.2) }

    func stage(_ stage: WidgetStageKind) -> Color {
        guard isFullColor else {
            switch stage {
            case .deep: return .primary
            case .core: return .primary.opacity(0.6)
            case .rem: return .primary.opacity(0.35)
            }
        }
        switch stage {
        case .deep: return NoctisAppColor.stageDeep
        case .core: return NoctisAppColor.stageCore
        case .rem: return NoctisAppColor.stageREM
        }
    }
}

public enum WidgetStageKind: CaseIterable, Sendable {
    case deep, core, rem
}

/// An arc of a circle, in degrees from the top, clockwise.
struct WidgetArc: Shape {
    var startDegrees: Double
    var endDegrees: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY), radius: radius, startAngle: .degrees(startDegrees - 90),
            endAngle: .degrees(endDegrees - 90), clockwise: false
        )
        return path
    }
}

/// The four-arc recovery ring: each factor's arc has its share of the circle, filled by how well it went.
public struct WidgetRingView: View {
    let segments: [WidgetRingSegment]
    let lineWidth: CGFloat
    @Environment(\.widgetRenderingMode) private var renderingMode

    public init(segments: [WidgetRingSegment], lineWidth: CGFloat) {
        self.segments = segments
        self.lineWidth = lineWidth
    }

    public var body: some View {
        let palette = WidgetPalette(mode: renderingMode)
        let arcs = NoctisRecoveryRingLayout.arcs(weights: segments.map(\.weight))
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height) - lineWidth
            // Round caps eat into the gap between arcs: pull each end in by the cap's own angle.
            let cap = diameter > 0 ? Double(lineWidth / 2 / (diameter / 2)) * 180 / .pi : 0
            ZStack {
                ForEach(Array(zip(segments.indices, segments)), id: \.0) { index, segment in
                    if arcs.indices.contains(index) {
                        let span = arcs[index].end - arcs[index].start
                        let inset = min(cap, span / 2.2)
                        let start = arcs[index].start + inset
                        let end = arcs[index].end - inset
                        WidgetArc(startDegrees: start, endDegrees: end)
                            .stroke(palette.track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        let filled = start + (end - start) * min(max(segment.fraction, 0), 1)
                        if filled > start + 0.5 {
                            WidgetArc(startDegrees: start, endDegrees: filled)
                                .stroke(palette.arc(segment.kind), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                                .widgetAccentable()
                        }
                    }
                }
            }
            .frame(width: diameter, height: diameter)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

/// The ring with no readings: the track only, for a state that has no score.
public struct WidgetEmptyRing: View {
    let lineWidth: CGFloat
    @Environment(\.widgetRenderingMode) private var renderingMode

    public init(lineWidth: CGFloat) {
        self.lineWidth = lineWidth
    }

    public var body: some View {
        Circle()
            .inset(by: lineWidth / 2)
            .stroke(WidgetPalette(mode: renderingMode).track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .accessibilityHidden(true)
    }
}

/// A flat bar of the night's stages: deep, core and REM minutes side by side, 14pt tall.
public struct WidgetStageStrip: View {
    let stages: WidgetStages
    var height: CGFloat = 14
    @Environment(\.widgetRenderingMode) private var renderingMode

    public init(stages: WidgetStages, height: CGFloat = 14) {
        self.stages = stages
        self.height = height
    }

    public var body: some View {
        let palette = WidgetPalette(mode: renderingMode)
        let parts: [(WidgetStageKind, Int)] = [(.deep, stages.deep), (.core, stages.core), (.rem, stages.rem)].filter { $0.1 > 0 }
        let total = max(parts.reduce(0) { $0 + $1.1 }, 1)
        GeometryReader { proxy in
            let gap: CGFloat = 2
            let room = max(proxy.size.width - gap * CGFloat(max(parts.count - 1, 0)), 0)
            HStack(spacing: gap) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                        .fill(palette.stage(part.0))
                        .frame(width: room * CGFloat(part.1) / CGFloat(total))
                }
            }
        }
        .frame(height: height)
        .widgetAccentable()
        .accessibilityHidden(true)
    }
}
