import DesignSystem
import HealthProviding
import NoctisCore
import SleepKit
import SwiftUI

/// Signature interaction: drag anywhere across the night and the readout
/// above follows your finger 1:1 — time, stage, duration, and the nearest
/// heart-rate reading, with a light haptic tick each time the stage under
/// your finger changes.
struct SleepTimelineView: View {
    let session: SleepSession
    let heartRateSamples: [HeartRateSample]
    let respiratoryRate: Double?

    @State private var dragProgress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            readout
            GeometryReader { geometry in
                Canvas { context, size in
                    drawLandscape(context: context, size: size)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in update(x: value.location.x, width: geometry.size.width) }
                        .onEnded { _ in
                            NoctisHaptics.light()
                            withAnimation(NoctisMotion.snap) { dragProgress = nil }
                        }
                )
            }
            .frame(height: 132)

            HStack {
                NoctisText(session.bedtime.formatted(date: .omitted, time: .shortened), style: .caption, color: NoctisColor.textTertiary)
                Spacer()
                NoctisText(session.wakeTime.formatted(date: .omitted, time: .shortened), style: .caption, color: NoctisColor.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var readout: some View {
        HStack(alignment: .firstTextBaseline, spacing: NoctisSpacing.md) {
            if let date = currentDate, let segment = currentSegment {
                NoctisText(date.formatted(date: .omitted, time: .standard), style: .bodyEmphasized)
                NoctisText(segment.stage.displayName, style: .caption, color: segment.stage.tint)
                NoctisText(formatSegmentDuration(segment.interval.duration), style: .caption, color: NoctisColor.textSecondary)
                if let bpm = currentHeartRate {
                    Spacer()
                    NoctisText("\(Int(bpm)) bpm", style: .caption, color: NoctisColor.textSecondary)
                }
            } else {
                NoctisText("Drag to explore your night", style: .caption, color: NoctisColor.textTertiary)
                Spacer()
                if let respiratoryRate {
                    NoctisText("\(String(format: "%.1f", respiratoryRate))/min respiration", style: .caption, color: NoctisColor.textTertiary)
                }
            }
        }
        .frame(height: 20)
    }

    /// Renders the night as one continuous, flowing landform instead of
    /// discrete rectangles: each stage pulls the shape to its own depth
    /// (awake near the surface, deep sleep at the bottom — see
    /// `SleepStageValue.landscapeDepth`), smoothed into gentle curves at
    /// every transition, with color flowing between each stage's own tint
    /// along the way.
    private func drawLandscape(context: GraphicsContext, size: CGSize) {
        guard session.timeInBed > 0, !session.segments.isEmpty else { return }
        let segments = session.segments.sorted { $0.interval.start < $1.interval.start }

        let points = landscapePoints(segments: segments, size: size)
        var landscapeFill = smoothPath(through: points)
        landscapeFill.addLine(to: CGPoint(x: size.width, y: size.height))
        landscapeFill.addLine(to: CGPoint(x: 0, y: size.height))
        landscapeFill.closeSubpath()

        context.fill(
            landscapeFill,
            with: .linearGradient(
                gradient(for: segments),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: size.width, y: 0)
            )
        )

        if let progress = dragProgress {
            let x = progress * size.width
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(line, with: .color(NoctisColor.textPrimary), lineWidth: 2)
        }
    }

    private func landscapePoints(segments: [SleepStageSegment], size: CGSize) -> [CGPoint] {
        guard let first = segments.first, let last = segments.last else { return [] }
        var points: [CGPoint] = [CGPoint(x: 0, y: first.stage.landscapeDepth * size.height)]
        for segment in segments {
            points.append(CGPoint(x: midXFraction(segment) * size.width, y: segment.stage.landscapeDepth * size.height))
        }
        points.append(CGPoint(x: size.width, y: last.stage.landscapeDepth * size.height))
        return points
    }

    /// Turns a polyline into a smoothed, flowing curve: each leg leaves and
    /// arrives horizontally, so flat plateaus stay flat and only genuine
    /// transitions curve.
    private func smoothPath(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { return path }
        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            let midX = (start.x + end.x) / 2
            path.addCurve(
                to: end,
                control1: CGPoint(x: midX, y: start.y),
                control2: CGPoint(x: midX, y: end.y)
            )
        }
        return path
    }

    private func gradient(for segments: [SleepStageSegment]) -> Gradient {
        var stops: [Gradient.Stop] = []
        var lastLocation: CGFloat = -1
        for segment in segments {
            let location = min(max(midXFraction(segment), 0), 1)
            let clamped = min(max(location, lastLocation + 0.001), 1)
            stops.append(Gradient.Stop(color: segment.stage.tint, location: clamped))
            lastLocation = clamped
        }
        return stops.isEmpty ? Gradient(colors: [NoctisColor.stageCore]) : Gradient(stops: stops)
    }

    private func midXFraction(_ segment: SleepStageSegment) -> CGFloat {
        xFraction(segment.interval.start) + (xFraction(segment.interval.end) - xFraction(segment.interval.start)) / 2
    }

    private func xFraction(_ date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(session.bedtime) / session.timeInBed)
    }

    private func update(x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let clamped = Double(min(max(x / width, 0), 1))
        let previousStage = currentSegment?.stage
        dragProgress = clamped
        if currentSegment?.stage != previousStage {
            NoctisHaptics.selection()
        }
    }

    private var currentDate: Date? {
        guard let progress = dragProgress else { return nil }
        return session.bedtime.addingTimeInterval(progress * session.timeInBed)
    }

    private var currentSegment: SleepStageSegment? {
        guard let date = currentDate else { return nil }
        return session.segments.first { $0.interval.start <= date && date < $0.interval.end }
    }

    private var currentHeartRate: Double? {
        guard let date = currentDate, !heartRateSamples.isEmpty else { return nil }
        return heartRateSamples.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }?.bpm
    }

    private func formatSegmentDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }

    private var accessibilitySummary: String {
        let hours = Int(session.totalAsleep / 3600)
        let minutes = Int(session.totalAsleep / 60) % 60
        return "Sleep timeline. \(hours) hours \(minutes) minutes total, from \(session.bedtime.formatted(date: .omitted, time: .shortened)) to \(session.wakeTime.formatted(date: .omitted, time: .shortened))."
    }
}
