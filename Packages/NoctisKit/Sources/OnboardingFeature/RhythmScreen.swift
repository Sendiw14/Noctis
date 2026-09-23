import DesignSystem
import NoctisCore
import SwiftUI

private let wakeRange = 180...720 // 3:00 AM .. 12:00 PM
private let wakeStep = 5
private let needRange = 300...600 // 5h .. 10h
private let needStep = 15

/// Step 2/6 — replaces the old separate wake-time and sleep-need screens;
/// R rules say never ask for either again, so this one screen carries
/// both. Two ruler-dial cards plus a derived bedtime + night-strip result
/// (no card) directly beneath them.
struct RhythmScreen: View {
    @Binding var wakeMinutes: Int
    @Binding var needMinutes: Int
    let onNext: () -> Void
    let onBack: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The scaffold's own single `ScrollView` now always bounds the hero to
    /// a measured, finite height (never the unbounded height that used to
    /// blow up a direct `GeometryReader` wrap here and swallow the AX
    /// scroll gesture — see `OnboardingScaffold`). This probe just reads
    /// that bounded size via a background, for the `compact`/`heroSize`
    /// decisions below; it's not providing scrolling itself. Defaults
    /// describe a normal (non-SE, non-AX) screen so the very first frame
    /// renders sensibly before the probe reports in.
    @State private var heroWidth: CGFloat = 400
    @State private var heroHeight: CGFloat = 900

    private var bedtimeMinutes: Int {
        noctisBedtimeMinutes(wakeMinutes: wakeMinutes, needMinutes: needMinutes)
    }

    var body: some View {
        OnboardingScaffold(
            step: 1,
            title: "Set your",
            emphasis: "rhythm.",
            onBack: onBack
        ) {
            // R11: must fit iPhone SE without scrolling. Width alone (the
            // existing 390pt hero-size check) isn't the binding constraint
            // here — SE and 17 Pro are close in width but SE is 207pt
            // shorter — so a second, height-driven "compact" mode tightens
            // spacing/padding/ruler height whenever the available height
            // is SE-sized or smaller. At AX sizes `heroHeight` reflects
            // this content's own natural (large) height, so compact is
            // simply false there — correct, since R10's AX scroll already
            // handles that case.
            let heroSize: CGFloat = heroWidth < 390 ? 42 : 64
            let compact = heroHeight < 700
            // R6: top-aligned, starting exactly 24pt under the title (the
            // scaffold's gap) — leftover space collects above the CTA.
            VStack(spacing: 0) {
                // R15: cards are always 20pt padded, 12pt apart.
                VStack(spacing: NoctisSpacing.sm) {
                    wakeCard(heroSize: heroSize, compact: compact)
                        .noctisScrollRow()
                        .noctisRise(index: 0)
                    needCard(heroSize: heroSize, compact: compact)
                        .noctisScrollRow()
                        .noctisRise(index: 1)
                }
                resultSection(compact: compact)
                    .noctisRise(index: 2)
                    .padding(.top, NoctisSpacing.xl)
            }
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            heroWidth = geometry.size.width
                            heroHeight = geometry.size.height
                        }
                        .onChange(of: geometry.size) { _, newSize in
                            heroWidth = newSize.width
                            heroHeight = newSize.height
                        }
                }
            )
        } bottomStack: {
            NoctisCTA("Continue", action: onNext)
        }
    }

    private func wakeCard(heroSize: CGFloat, compact: Bool) -> some View {
        NoctisPaperCard(padding: NoctisSpacing.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text("I usually wake at")
                    .font(.system(size: compact ? 13 : 14, weight: .medium, design: .rounded))
                    .foregroundStyle(NoctisPaper.ink2)
                    .noctisTextBlock()
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(wakeTimeNumeric)
                        .font(.system(size: heroSize, weight: .heavy, design: .rounded))
                        .foregroundStyle(NoctisPaper.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(wakeTimePeriod)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(NoctisPaper.ink2)
                }
                .animation(NoctisMotion.adaptive(.easeInOut(duration: 0.15), reduceMotion: reduceMotion), value: wakeMinutes)
                .accessibilityElement(children: .combine)
                .noctisTextBlock()

                RulerDial(
                    range: wakeRange,
                    step: wakeStep,
                    value: $wakeMinutes,
                    hourLabel: localizedHourLabel,
                    accessibilityName: "Wake time",
                    accessibilityValue: { noctisFormattedClock(minutesSinceMidnight: $0) },
                    height: compact ? 32 : 52,
                    compact: compact,
                    minorTickMinutes: 15,
                    pxPerMinute: 1.7
                )
                .padding(.top, compact ? 2 : NoctisSpacing.xs)
                .noctisTextBlock()
            }
        }
    }

    private func needCard(heroSize: CGFloat, compact: Bool) -> some View {
        NoctisPaperCard(padding: NoctisSpacing.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text("I feel best with")
                    .font(.system(size: compact ? 13 : 14, weight: .medium, design: .rounded))
                    .foregroundStyle(NoctisPaper.ink2)
                    .noctisTextBlock()
                Text(noctisFormattedDuration(minutes: needMinutes))
                    .font(.system(size: heroSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(NoctisPaper.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(NoctisMotion.adaptive(.easeInOut(duration: 0.15), reduceMotion: reduceMotion), value: needMinutes)
                    .noctisTextBlock()

                RulerDial(
                    range: needRange,
                    step: needStep,
                    value: $needMinutes,
                    hourLabel: { "\($0 / 60)h" },
                    accessibilityName: "Sleep need",
                    // Minutes included: the ruler steps by 15, and "8 hours"
                    // for 8h 15m made VoiceOver's increment sound like a no-op.
                    accessibilityValue: { minutes in
                        let hours = minutes / 60, rest = minutes % 60
                        return rest == 0 ? "\(hours) hours" : "\(hours) hours \(rest) minutes"
                    },
                    height: compact ? 32 : 52,
                    compact: compact
                )
                .padding(.top, compact ? 2 : NoctisSpacing.xs)
                .noctisTextBlock()
            }
        }
    }

    private func resultSection(compact: Bool) -> some View {
        VStack(spacing: compact ? 2 : NoctisSpacing.xs) {
            Text("Bedtime around \(noctisFormattedClock(minutesSinceMidnight: bedtimeMinutes))")
                .font(.system(size: compact ? 17 : 22, weight: .semibold, design: .rounded))
                .foregroundStyle(NoctisPaper.ink)
                .contentTransition(.numericText())
                .animation(NoctisMotion.adaptive(.easeInOut(duration: 0.2), reduceMotion: reduceMotion), value: bedtimeMinutes)
                .noctisTextBlock()

            VStack(spacing: NoctisSpacing.sm) {
                NightStrip(bedtimeMinutes: bedtimeMinutes, wakeMinutes: wakeMinutes, compact: compact)
                    .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion), value: bedtimeMinutes)
                    .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion), value: wakeMinutes)
                    .noctisTextBlock()

                Text("A starting point. NOCTIS adapts as it learns your nights.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(NoctisPaper.ink3)
                    .multilineTextAlignment(.center)
                    .noctisTextBlock()
            }
            .padding(.top, 2)
        }
    }

    private var wakeTimeNumeric: String {
        let hour24 = wakeMinutes / 60
        let minute = wakeMinutes % 60
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        return String(format: "%d:%02d", hour12, minute)
    }

    private var wakeTimePeriod: String { (wakeMinutes / 60) < 12 ? "AM" : "PM" }

    /// "6 AM", "7 AM" — the wake ruler's hour ticks in locale format,
    /// distinct from `shortWakeHourLabel`'s old single-letter "6A"/"7P"
    /// (too easy to mistake for truncation at the ruler's edge fade).
    private func localizedHourLabel(_ minutes: Int) -> String {
        let hour24 = (minutes / 60) % 24
        guard let date = Calendar.current.date(bySettingHour: hour24, minute: 0, second: 0, of: .now) else {
            return "\(hour24)"
        }
        return date.formatted(.dateTime.hour())
    }
}

// MARK: - Ruler dial

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
private struct RulerDial: View {
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    var body: some View {
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
        .frame(height: height)
        // VoiceOver sees a plain 15-minute-step slider the size of the
        // visible dial. Marking the dial itself as the element gave it the
        // frame of the whole tick strip, far wider than the screen.
        .accessibilityRepresentation {
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { setValue(min(max(Int(($0 / 15).rounded()) * 15, range.lowerBound), range.upperBound)) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 15
            ) {
                Text(accessibilityName)
            }
            .accessibilityValue(accessibilityValue(value))
        }
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
                .fill(isHour ? NoctisPaper.ink : NoctisPaper.ink3)
                .frame(width: isHour ? 2 : 1, height: isHour ? hourMarkHeight : (compact ? 8 : 14))
            Group {
                if isHour && !hideLabel {
                    // R4 floor: 12pt is the minimum text size, so the hour
                    // label itself never shrinks in compact mode — only
                    // the tick marks and spacing around it do.
                    Text(hourLabel(minute))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(NoctisPaper.ink3)
                        .fixedSize()
                } else {
                    Color.clear
                }
            }
            .frame(height: 14)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Spans only the tick-mark row (never the label row below it) so it
    /// can never sit on top of — and hide — the hour label underneath it.
    private var centerIndicator: some View {
        VStack(spacing: 1) {
            RulerIndicatorCap()
                .fill(NoctisPaper.cocoa)
                .frame(width: 9, height: 5)
            Rectangle()
                .fill(NoctisPaper.cocoa)
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

private struct RulerIndicatorCap: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Night strip

/// A time axis from the strip's window start (6 PM, or earlier for an early
/// bedtime — see `noctisNightStripWindow`) through 12 PM the next day,
/// drawn in one Canvas so every mark comes from the same scale: each label
/// (6P, 12A, 6A, 12P) is centered on its exact time, the moon and sun dots
/// sit exactly at bedtime and wake, and the lavender bar spans exactly the
/// sleep need between them. It animates in absolute minutes (window start,
/// bedtime, wake), so labels and dots stay on one scale mid-animation too.
/// The Canvas extends `edgeOverhang` past the column on each side so the
/// end labels and dots can center on the track's ends without clipping; the
/// track itself stays flush with the cards above.
private struct NightStrip: View, Animatable {
    /// Minutes from the evening's midnight (0 = 12 AM that day).
    var windowStart: Double
    var bedtime: Double
    var wake: Double
    let bedtimeMinutes: Int
    let wakeMinutes: Int
    let compact: Bool

    init(bedtimeMinutes: Int, wakeMinutes: Int, compact: Bool) {
        self.bedtimeMinutes = bedtimeMinutes
        self.wakeMinutes = wakeMinutes
        self.compact = compact
        let window = noctisNightStripWindow(bedtimeMinutes: bedtimeMinutes)
        func absolute(_ minutes: Int) -> Double {
            let fraction = noctisNightStripFraction(minutesSinceMidnight: minutes, startMinutes: window.startMinutes, spanMinutes: window.spanMinutes)
            return Double(window.startMinutes) + fraction * Double(window.spanMinutes)
        }
        windowStart = Double(window.startMinutes)
        bedtime = absolute(bedtimeMinutes)
        wake = absolute(wakeMinutes)
    }

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(windowStart, AnimatablePair(bedtime, wake)) }
        set {
            windowStart = newValue.first
            bedtime = newValue.second.first
            wake = newValue.second.second
        }
    }

    /// Label times in minutes from the evening's midnight.
    private static let labels: [(text: String, minutes: Double)] = [
        ("6P", 18 * 60), ("12A", 24 * 60), ("6A", 30 * 60), ("12P", 36 * 60),
    ]
    private static let edgeOverhang: CGFloat = 12
    private static let labelHeight: CGFloat = 15

    private var trackHeight: CGFloat { compact ? 11 : 18 }
    private var dotSize: CGFloat { compact ? 11 : 16 }
    private var rowHeight: CGFloat { max(trackHeight, dotSize) }
    private var labelGap: CGFloat { compact ? 2 : 6 }

    var body: some View {
        Canvas { context, size in
            let trackMinX = Self.edgeOverhang
            let trackWidth = size.width - Self.edgeOverhang * 2
            let span = Double(noctisNightStripEndMinutes) - windowStart
            func x(_ minutes: Double) -> CGFloat {
                trackMinX + trackWidth * CGFloat(min(max((minutes - windowStart) / span, 0), 1))
            }
            let midY = rowHeight / 2

            let track = CGRect(x: trackMinX, y: midY - trackHeight / 2, width: trackWidth, height: trackHeight)
            context.fill(Capsule().path(in: track), with: .color(NoctisPaper.track))

            let bedX = x(bedtime)
            let wakeX = x(wake)
            let bar = CGRect(x: bedX, y: track.minY, width: max(wakeX - bedX, 4), height: trackHeight)
            context.fill(Capsule().path(in: bar), with: .color(NoctisPaper.lavender))

            for (centerX, symbol) in [(bedX, "moon.fill"), (wakeX, "sun.max.fill")] {
                let dot = CGRect(x: centerX - dotSize / 2, y: midY - dotSize / 2, width: dotSize, height: dotSize)
                context.fill(Circle().path(in: dot), with: .color(NoctisPaper.cocoa))
                let glyph = context.resolve(
                    Text(Image(systemName: symbol)).font(.system(size: compact ? 7 : 8)).foregroundStyle(NoctisPaper.bg)
                )
                context.draw(glyph, at: CGPoint(x: centerX, y: midY), anchor: .center)
            }

            for label in Self.labels {
                let text = context.resolve(
                    Text(label.text).font(.system(size: 12, design: .rounded)).foregroundStyle(NoctisPaper.ink3)
                )
                context.draw(text, at: CGPoint(x: x(label.minutes), y: size.height), anchor: .bottom)
            }
        }
        .frame(height: rowHeight + labelGap + Self.labelHeight)
        .padding(.horizontal, -Self.edgeOverhang)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Night strip, bedtime \(noctisFormattedClock(minutesSinceMidnight: bedtimeMinutes)) through wake \(noctisFormattedClock(minutesSinceMidnight: wakeMinutes))")
    }
}
