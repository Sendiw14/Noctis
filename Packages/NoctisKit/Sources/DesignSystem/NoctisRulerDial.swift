import SwiftUI

// The tick ruler onboarding set the wake time and the sleep need with, and Profile edits them with.

/// A horizontally-draggable tick ruler with a fixed center indicator.
///
/// This deliberately does NOT use `ScrollView` + `scrollPosition(id:)` /
/// `ScrollViewReader.scrollTo`. An earlier version did, and empirically
/// (confirmed via debug logging against the running simulator) the
/// framework's own bookkeeping — `scrollPosition` read back exactly the
/// target id — went out of sync with what was actually rendered on
/// screen for the wider (109-tick) wake ruler, while the narrower
/// (21-tick) need ruler happened to render correctly. Since `value`
/// tracked the (correct) reported id rather than the (wrong) rendered
/// pixels, the bug was invisible to state but visible on screen with no
/// self-correction. Driving the offset with plain arithmetic under a
/// `DragGesture` removes the framework scroll machinery from the loop
/// entirely, so there's nothing left to desync.
public struct NoctisRulerDial: View {
    /// Onboarding's dial is always the light paper; the app's own pages follow Light and Dark.
    public enum Tone: Sendable {
        case paper
        case app
        /// On a colour card (onboarding's band style): ink ticks, ink labels, in Light and Dark alike.
        case band

        var ink: Color {
            switch self {
            case .paper, .band: NoctisPaper.ink
            case .app: NoctisAppColor.ink
            }
        }
        var ink3: Color {
            switch self {
            case .paper: NoctisPaper.ink3
            case .band: NoctisPaper.ink.opacity(0.85)
            case .app: NoctisAppColor.ink3
            }
        }
        var cocoa: Color {
            switch self {
            case .paper: NoctisPaper.cocoa
            case .band: NoctisPaper.ink
            case .app: NoctisAppColor.cocoa
            }
        }
    }

    let range: ClosedRange<Int>
    let step: Int
    @Binding var value: Int
    let hourLabel: (Int) -> String
    let accessibilityName: String
    let accessibilityValue: (Int) -> String
    var height: CGFloat = 52
    var compact: Bool = false
    /// Visual spacing between drawn tick marks, in minutes — independent
    /// of `step` (the snap grain). Defaults to `step` (one tick per snap
    /// position, the need ruler's original behavior). The wake ruler
    /// overrides this to 15 so it can draw fewer, more widely-spaced
    /// ticks while still snapping every 5 minutes underneath.
    var minorTickMinutes: Int? = nil
    /// The display scale (points per minute), independent of tick
    /// spacing. Defaults to matching the old fixed-14pt-tick math exactly
    /// (`14 / step`), so the need ruler is pixel-identical to before. The
    /// wake ruler overrides this to a smaller value so ~3 hours fit in
    /// the visible frame instead of one.
    var pxPerMinute: CGFloat? = nil
    var tone: Tone = .paper
    /// What one VoiceOver swipe up or down moves the value by, in the ruler's own units (15 for a time; 30 for the sleep need).
    var accessibilityStep: Int = 15
    var identifier: String?

    public init(
        range: ClosedRange<Int>,
        step: Int,
        value: Binding<Int>,
        hourLabel: @escaping (Int) -> String,
        accessibilityName: String,
        accessibilityValue: @escaping (Int) -> String,
        height: CGFloat = 52,
        compact: Bool = false,
        minorTickMinutes: Int? = nil,
        pxPerMinute: CGFloat? = nil,
        tone: Tone = .paper,
        accessibilityStep: Int = 15,
        identifier: String? = nil
    ) {
        self.range = range
        self.step = step
        self._value = value
        self.hourLabel = hourLabel
        self.accessibilityName = accessibilityName
        self.accessibilityValue = accessibilityValue
        self.height = height
        self.compact = compact
        self.minorTickMinutes = minorTickMinutes
        self.pxPerMinute = pxPerMinute
        self.tone = tone
        self.accessibilityStep = accessibilityStep
        self.identifier = identifier
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// R4: hour labels scale on the caption curve; the label row (and so
    /// the dial) grows with them instead of clipping.
    @ScaledMetric(relativeTo: .caption) private var scaledLabelSize: CGFloat = 12
    /// The label stops growing at 18pt (about the xxLarge caption): the hours are a fixed distance apart, and at AX5 on an SE "9h" and "10h" (or
    /// "6 AM 7 AM 8 AM") printed into each other ("9h10h"). At that size the number is read from the large value above the ruler.
    private var labelSize: CGFloat { min(scaledLabelSize, 18) }
    private var labelRowHeight: CGFloat { (labelSize * 14 / 12).rounded(.up) }
    @State private var frameWidth: CGFloat = 0
    /// The at-rest offset for the current `value` — recomputed whenever
    /// `value` settles (drag end, accessibility action, or first layout).
    @State private var baseOffset: CGFloat = 0
    /// Live finger delta while dragging; 0 at rest.
    @State private var dragTranslation: CGFloat = 0
    @State private var entranceOffset: CGFloat = 0
    @State private var hasAppeared = false

    /// R14: labels within this many points of either visible edge are
    /// dropped entirely rather than left to render partially cut off.
    private let edgeLabelZone: CGFloat = 24

    private var pxPerUnit: CGFloat { pxPerMinute ?? (14 / CGFloat(step)) }
    private var tickIntervalMinutes: Int { minorTickMinutes ?? step }
    private var tickWidth: CGFloat { CGFloat(tickIntervalMinutes) * pxPerUnit }
    private var ticks: [Int] { Array(stride(from: range.lowerBound, through: range.upperBound, by: tickIntervalMinutes)) }

    /// The x-position of `minute`'s tick MARK itself (its visual center),
    /// not the leading edge of its `tickWidth`-wide layout slot — those
    /// differ by `tickWidth / 2`, which without this term put every tick
    /// half a tick-width off from the indicator (~2-7 real minutes,
    /// depending on the ruler's step size).
    private func contentX(_ minute: Int) -> CGFloat {
        CGFloat(minute - range.lowerBound) * pxPerUnit + tickWidth / 2
    }

    /// `minute`'s tick position in the ruler's own *visible* coordinate
    /// space (0...frameWidth) at the current scroll offset — used to hide
    /// labels that fall inside the edge fade zone instead of letting them
    /// render partially cut off.
    private func visibleX(_ minute: Int) -> CGFloat {
        contentX(minute) + liveOffset + entranceOffset
    }

    /// The offset that centers `target`'s tick under the fixed indicator.
    private func settledOffset(for target: Int) -> CGFloat {
        frameWidth / 2 - contentX(target)
    }

    private func nearestValue(atOffset offset: CGFloat) -> Int {
        let rawMinute = Double(range.lowerBound) + Double(frameWidth / 2 - offset) / Double(pxPerUnit)
        let stepsFromStart = ((rawMinute - Double(range.lowerBound)) / Double(step)).rounded()
        let snappedMinute = Double(range.lowerBound) + stepsFromStart * Double(step)
        return min(max(Int(snappedMinute), range.lowerBound), range.upperBound)
    }

    private var minOffset: CGFloat { settledOffset(for: range.upperBound) }
    private var maxOffset: CGFloat { settledOffset(for: range.lowerBound) }

    /// Clamped so dragging past either end hits a firm stop (paired with
    /// `NoctisHaptics.limit()`) instead of revealing blank space beyond
    /// the first/last tick.
    private var liveOffset: CGFloat {
        min(max(baseOffset + dragTranslation, minOffset), maxOffset)
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                HStack(spacing: 0) {
                    ForEach(ticks, id: \.self) { minute in
                        let onScreenX = visibleX(minute)
                        let hideLabel = onScreenX < edgeLabelZone || onScreenX > frameWidth - edgeLabelZone
                        tickView(minute, hideLabel: hideLabel)
                            .frame(width: tickWidth)
                    }
                }
                // `contentX` assumes the HStack's leading edge sits at this
                // ZStack's local x=0. That's only true unconditionally when
                // the HStack is the widest ZStack child (wake: 109 ticks,
                // 1526pt, wider than the ~322pt frame). For need (21 ticks,
                // 294pt — narrower than the frame), the full-frame Color.clear
                // hit-area below makes the ZStack exactly `frameWidth` wide,
                // and ZStack's default `.center` alignment then centers the
                // narrower HStack inside it, silently adding an unaccounted
                // pre-offset that put the indicator ~22 real minutes off
                // target. Anchoring explicitly to `.leading` here makes the
                // HStack's leading edge land at local x=0 in both cases.
                .frame(width: geometry.size.width, alignment: .leading)
                .offset(x: liveOffset + entranceOffset)
                .mask(edgeFadeMask)

                centerIndicator

                // Full-frame hit area so dragging works anywhere on the
                // ruler, not just directly over a 14pt tick.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
            }
            .clipped()
            .onAppear {
                frameWidth = geometry.size.width
                baseOffset = settledOffset(for: value)
                runEntranceIfNeeded()
            }
            .onChange(of: geometry.size.width) { _, newWidth in
                frameWidth = newWidth
                if dragTranslation == 0 {
                    baseOffset = settledOffset(for: value)
                }
            }
        }
        .frame(height: height + labelRowHeight - 14)
        // VoiceOver sees a plain 15-minute-step slider the size of the
        // visible dial. Marking the dial itself as the element gave it the
        // frame of the whole tick strip, far wider than the screen.
        .accessibilityRepresentation {
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { setValue(Self.accessibilitySnap($0, step: accessibilityStep, range: range)) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(accessibilityStep)
            ) {
                Text(accessibilityName)
            }
            .accessibilityValue(accessibilityValue(value))
            .accessibilityIdentifier(identifier ?? "ruler")
        }
    }

    /// Where a VoiceOver adjustment lands: the nearest multiple of `step`, kept inside `range`.
    public static func accessibilitySnap(_ raw: Double, step: Int, range: ClosedRange<Int>) -> Int {
        min(max(Int((raw / Double(step)).rounded()) * step, range.lowerBound), range.upperBound)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { drag in
                dragTranslation = drag.translation.width
                let liveValue = nearestValue(atOffset: liveOffset)
                if liveValue != value {
                    value = liveValue
                    fireHaptic(for: liveValue)
                }
            }
            .onEnded { _ in
                let finalValue = value
                withAnimation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion)) {
                    dragTranslation = 0
                    baseOffset = settledOffset(for: finalValue)
                }
            }
    }

    private var hourMarkHeight: CGFloat { compact ? 14 : 26 }

    private func tickView(_ minute: Int, hideLabel: Bool) -> some View {
        let isHour = minute % 60 == 0
        return VStack(spacing: compact ? 1 : 4) {
            Rectangle()
                .fill(isHour ? tone.ink : tone.ink3)
                .frame(width: isHour ? 2 : 1, height: isHour ? hourMarkHeight : (compact ? 8 : 14))
            Group {
                if isHour && !hideLabel {
                    // R4 floor: 12pt is the minimum text size, so the hour
                    // label itself never shrinks in compact mode — only
                    // the tick marks and spacing around it do.
                    Text(hourLabel(minute))
                        .font(.system(size: labelSize, design: .rounded))
                        .foregroundStyle(tone.ink3)
                        .fixedSize()
                } else {
                    Color.clear
                }
            }
            .frame(height: labelRowHeight)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Spans only the tick-mark row (never the label row below it) so it
    /// can never sit on top of — and hide — the hour label underneath it.
    private var centerIndicator: some View {
        VStack(spacing: 1) {
            NoctisRulerIndicatorCap()
                .fill(tone.cocoa)
                .frame(width: 9, height: 5)
            Rectangle()
                .fill(tone.cocoa)
                .frame(width: 3, height: max(hourMarkHeight - 6, 4))
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    /// A fixed 24pt fade at each visible edge (R14), rather than the old
    /// 10%-of-content fade whose width ballooned with the wake ruler's
    /// 1526pt content — that made the fade zone wide enough to swallow an
    /// entire label, reading as a hard cut once the label itself was cut
    /// off mid-glyph rather than faded.
    private var edgeFadeMask: some View {
        let fadeFraction = frameWidth > 0 ? min(edgeLabelZone / frameWidth, 0.3) : 0.1
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: fadeFraction),
                .init(color: .black, location: 1 - fadeFraction),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func fireHaptic(for newValue: Int) {
        if newValue == range.lowerBound || newValue == range.upperBound {
            NoctisHaptics.limit()
        } else if newValue % 60 == 0 {
            NoctisHaptics.hourTick()
        } else {
            NoctisHaptics.snapLight()
        }
    }

    private func setValue(_ newValue: Int) {
        value = newValue
        withAnimation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion)) {
            baseOffset = settledOffset(for: newValue)
        }
        NoctisHaptics.snapLight()
    }

    /// R9/R11: the ruler visually slides into its resting position on first
    /// appearance — skipped under Reduce Motion, which jumps straight to
    /// rest. `baseOffset` is already set correctly by the time this runs
    /// (see `.onAppear` above); only a cosmetic additive offset animates
    /// here, so the displayed value can never end up stranded mid-entrance.
    private func runEntranceIfNeeded() {
        guard !hasAppeared else { return }
        hasAppeared = true
        guard !reduceMotion else { return }
        let ticksFor30Min = CGFloat(30 / step) * tickWidth
        entranceOffset = ticksFor30Min
        withAnimation(NoctisMotion.settle) {
            entranceOffset = 0
        }
    }
}

private struct NoctisRulerIndicatorCap: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
