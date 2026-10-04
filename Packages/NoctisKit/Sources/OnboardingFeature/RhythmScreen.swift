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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                    .noctisFont(compact ? 13 : 14, .medium, relativeTo: .subheadline)
                    .foregroundStyle(NoctisPaper.ink2)
                    .noctisTextBlock()
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(wakeTimeNumeric)
                        .noctisNumeral(heroSize)
                        .foregroundStyle(NoctisPaper.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(wakeTimePeriod)
                        .noctisNumeral(24, .semibold)
                        .foregroundStyle(NoctisPaper.ink2)
                }
                .animation(NoctisMotion.adaptive(.easeInOut(duration: 0.15), reduceMotion: reduceMotion), value: wakeMinutes)
                .accessibilityElement(children: .combine)
                .noctisTextBlock()

                NoctisRulerDial(
                    range: wakeRange,
                    step: wakeStep,
                    value: $wakeMinutes,
                    hourLabel: localizedHourLabel,
                    accessibilityName: "Wake time",
                    accessibilityValue: { noctisFormattedClock(minutesSinceMidnight: $0) },
                    height: compact ? 32 : 52,
                    compact: compact,
                    minorTickMinutes: 15,
                    pxPerMinute: 1.7,
                    tone: .paper
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
                    .noctisFont(compact ? 13 : 14, .medium, relativeTo: .subheadline)
                    .foregroundStyle(NoctisPaper.ink2)
                    .noctisTextBlock()
                Text(noctisFormattedDuration(minutes: needMinutes))
                    .noctisNumeral(heroSize)
                    .foregroundStyle(NoctisPaper.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(NoctisMotion.adaptive(.easeInOut(duration: 0.15), reduceMotion: reduceMotion), value: needMinutes)
                    .noctisTextBlock()

                NoctisRulerDial(
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
                    compact: compact,
                    tone: .paper
                )
                .padding(.top, compact ? 2 : NoctisSpacing.xs)
                .noctisTextBlock()
            }
        }
    }

    private func resultSection(compact: Bool) -> some View {
        VStack(spacing: NoctisScrollEdges.blockGap(compact ? 2 : NoctisSpacing.xs, dynamicTypeSize)) {
            Text("Bedtime around \(noctisFormattedClock(minutesSinceMidnight: bedtimeMinutes))")
                .noctisFont(compact ? 17 : 22, .semibold, relativeTo: .title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(NoctisPaper.ink)
                .contentTransition(.numericText())
                .animation(NoctisMotion.adaptive(.easeInOut(duration: 0.2), reduceMotion: reduceMotion), value: bedtimeMinutes)
                .noctisTextBlock()

            VStack(spacing: NoctisScrollEdges.blockGap(NoctisSpacing.sm, dynamicTypeSize)) {
                NightStrip(bedtimeMinutes: bedtimeMinutes, wakeMinutes: wakeMinutes, compact: compact)
                    .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion), value: bedtimeMinutes)
                    .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion), value: wakeMinutes)
                    .noctisTextBlock()

                Text("A starting point. NOCTIS adapts as it learns your nights.")
                    .noctisFont(12, relativeTo: .caption)
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
    /// R4: axis labels scale on the caption curve; the label row grows too.
    @ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 12
    private var labelHeight: CGFloat { (labelSize * 15 / 12).rounded(.up) }

    private var trackHeight: CGFloat { compact ? 11 : 18 }
    private var dotSize: CGFloat { compact ? 11 : 16 }
    private var rowHeight: CGFloat { max(trackHeight, dotSize) }
    private var labelGap: CGFloat { compact ? 2 : 6 }

    var body: some View {
        Canvas { context, size in
            let resolvedLabels = Self.labels.map { label in
                (label, context.resolve(
                    Text(label.text).font(.system(size: labelSize, design: .rounded)).foregroundStyle(NoctisPaper.ink3)
                ))
            }
            // The track stays flush with the cards above unless the labels
            // centered on its ends (large text) would run off the canvas;
            // then it insets just enough to keep them whole.
            let widestHalf = resolvedLabels.map { $0.1.measure(in: size).width / 2 }.max() ?? 0
            let trackMinX = max(Self.edgeOverhang, widestHalf + 1)
            let trackWidth = size.width - trackMinX * 2
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

            for (label, text) in resolvedLabels {
                context.draw(text, at: CGPoint(x: x(label.minutes), y: size.height), anchor: .bottom)
            }
        }
        .frame(height: rowHeight + labelGap + labelHeight)
        .padding(.horizontal, -Self.edgeOverhang)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Night strip, bedtime \(noctisFormattedClock(minutesSinceMidnight: bedtimeMinutes)) through wake \(noctisFormattedClock(minutesSinceMidnight: wakeMinutes))")
    }
}
