import DesignSystem
import NoctisCore
import NoctisText
import SwiftUI

/// The rulers' bounds and grain (what is saved is unchanged): wake 3:00 AM to 12:00 PM in 5-minute steps, sleep need 5 h to 10 h in 15-minute steps.
enum RhythmBounds {
    static let wake = 180...720
    static let wakeStep = 5
    static let need = 300...600
    static let needStep = 15
}

/// Step 2/6, in the band style (APP_RULES.md R6, R69): a sage band, two colour cards with rulers (the wake time on butter, the sleep need on lavender),
/// and the bedtime they give on a cocoa card with the night's timeline. R rules say never ask for either again, so this one screen carries both.
struct RhythmScreen: View {
    @Binding var wakeMinutes: Int
    @Binding var needMinutes: Int
    let onNext: () -> Void
    let onBack: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.onboardingScale) private var scale
    @State private var appeared = false

    private var bedtimeMinutes: Int {
        noctisBedtimeMinutes(wakeMinutes: wakeMinutes, needMinutes: needMinutes)
    }

    var body: some View {
        OnboardingStepScaffold(
            section: .sleep, step: 1, title: ["Set your", "rhythm."], bandHeight: 244, bandSymbol: "clock", onBack: onBack
        ) {
            RhythmCards(
                wakeMinutes: $wakeMinutes, needMinutes: $needMinutes, bedtimeMinutes: bedtimeMinutes, dark: colorScheme == .dark,
                appeared: appeared || reduceMotion, reduceMotion: reduceMotion
            )
        } actions: {
            OnboardingPrimaryButton("Continue", identifier: "rhythm.continue", action: onNext)
        }
        .onAppear {
            guard !appeared else { return }
            appeared = true
        }
    }
}

private struct RhythmCards: View {
    @Binding var wakeMinutes: Int
    @Binding var needMinutes: Int
    let bedtimeMinutes: Int
    let dark: Bool
    let appeared: Bool
    let reduceMotion: Bool

    @Environment(\.onboardingScale) private var scale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var s: CGFloat { min(max(scale, 0.72), 1) }
    private var compact: Bool { scale < 0.85 }
    /// The result card: the ink colour in Light, cocoa in Dark.
    private var resultFill: Color { dark ? NoctisPaper.cocoa : NoctisPaper.ink }

    var body: some View {
        VStack(spacing: 10 * s) {
            wakeCard.slideUp(index: 0, appeared: appeared, reduceMotion: reduceMotion, stagger: 0.06)
            needCard.slideUp(index: 1, appeared: appeared, reduceMotion: reduceMotion, stagger: 0.06)
            resultCard.slideUp(index: 2, appeared: appeared, reduceMotion: reduceMotion, stagger: 0.06)
            Text("A starting point. NOCTIS adapts as it learns your nights.")
                .noctisFont(12, relativeTo: .caption)
                .foregroundStyle(dark ? NoctisPaper.ivory.opacity(0.65) : NoctisPaper.ink.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
                .slideUp(index: 3, appeared: appeared, reduceMotion: reduceMotion, stagger: 0.06)
        }
    }

    // MARK: Cards

    private func card<Content: View>(_ fill: Color, minHeight: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(.horizontal, 20)
            .padding(.vertical, compact ? 12 : 16)
            .frame(maxWidth: .infinity, minHeight: minHeight * s, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(fill))
    }

    private var wakeCard: some View {
        card(NoctisPaper.butter, minHeight: 152) {
            Text("I usually wake at")
                .noctisFont(14, .semibold, relativeTo: .subheadline)
                .foregroundStyle(NoctisPaper.ink.opacity(0.7))
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(wakeTimeSplit.time)
                    .noctisNumeral(54 * s, .heavy)
                    .foregroundStyle(NoctisPaper.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(wakeTimeSplit.period)
                    .noctisFont(22 * s, .heavy, relativeTo: .title3)
                    .foregroundStyle(NoctisPaper.ink.opacity(0.7))
            }
            .animation(NoctisMotion.adaptive(.easeInOut(duration: 0.15), reduceMotion: reduceMotion), value: wakeMinutes)
            .accessibilityElement(children: .ignore)
            .accessibilityHidden(true)
            Spacer(minLength: 4)
            NoctisRulerDial(
                range: RhythmBounds.wake, step: RhythmBounds.wakeStep, value: $wakeMinutes, hourLabel: localizedHourLabel,
                accessibilityName: "Wake time", accessibilityValue: { noctisFormattedClock(minutesSinceMidnight: $0) },
                height: compact ? 32 : 46, compact: compact, minorTickMinutes: 15, pxPerMinute: 1.5, tone: .band,
                accessibilityStep: 15, identifier: "rhythm.wake"
            )
        }
    }

    private var needCard: some View {
        card(NoctisPaper.lavender, minHeight: 142) {
            Text("I feel best with")
                .noctisFont(14, .semibold, relativeTo: .subheadline)
                .foregroundStyle(NoctisPaper.ink.opacity(0.7))
            Text(noctisFormattedDuration(minutes: needMinutes))
                .noctisNumeral(50 * s, .heavy)
                .foregroundStyle(NoctisPaper.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(NoctisMotion.adaptive(.easeInOut(duration: 0.15), reduceMotion: reduceMotion), value: needMinutes)
                .accessibilityHidden(true)
            Spacer(minLength: 4)
            NoctisRulerDial(
                range: RhythmBounds.need, step: RhythmBounds.needStep, value: $needMinutes, hourLabel: { "\($0 / 60)h" },
                accessibilityName: "Sleep need",
                // Minutes included: the ruler steps by 15 under a finger, and "8 hours" for 8h 15m made VoiceOver's increment sound like a no-op.
                accessibilityValue: { minutes in
                    let hours = minutes / 60, rest = minutes % 60
                    return rest == 0 ? "\(hours) hours" : "\(hours) hours \(rest) minutes"
                },
                height: compact ? 32 : 46, compact: compact, minorTickMinutes: 30, pxPerMinute: 1.34, tone: .band, accessibilityStep: 30, identifier: "rhythm.need"
            )
        }
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            HStack(alignment: .firstTextBaseline) {
                Text("BEDTIME AROUND")
                    .noctisFont(11, .heavy, relativeTo: .caption2)
                    .tracking(1)
                    .foregroundStyle(NoctisPaper.butter)
                Spacer(minLength: 8)
                Text(noctisFormattedClock(minutesSinceMidnight: bedtimeMinutes))
                    .noctisFont(26 * s, .heavy, relativeTo: .title2)
                    .foregroundStyle(NoctisPaper.ivory)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(NoctisMotion.adaptive(.easeInOut(duration: 0.2), reduceMotion: reduceMotion), value: bedtimeMinutes)
            }
            NightStrip(bedtimeMinutes: bedtimeMinutes, wakeMinutes: wakeMinutes, compact: compact)
                .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82), value: bedtimeMinutes)
                .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82), value: wakeMinutes)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, compact ? 12 : 16)
        .frame(maxWidth: .infinity, minHeight: 100 * s, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(resultFill))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bedtime around \(noctisFormattedClock(minutesSinceMidnight: bedtimeMinutes))")
        .accessibilityIdentifier("rhythm.bedtime")
    }

    private var wakeTimeSplit: (time: String, period: String) { NoctisFormat().splitClock(noctisFormattedClock(minutesSinceMidnight: wakeMinutes)) }
    /// "6 AM", "7 AM": the wake ruler's hour ticks in the locale's format.
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
                    Text(label.text).font(.system(size: labelSize, design: .rounded)).foregroundStyle(NoctisPaper.ivory.opacity(0.65))
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
            context.fill(Capsule().path(in: track), with: .color(NoctisPaper.ivory.opacity(0.16)))

            let bedX = x(bedtime)
            let wakeX = x(wake)
            let bar = CGRect(x: bedX, y: track.minY, width: max(wakeX - bedX, 4), height: trackHeight)
            context.fill(Capsule().path(in: bar), with: .color(NoctisPaper.lavender))

            // Bedtime: an ivory dot; wake: a butter one.
            for (centerX, color) in [(bedX, NoctisPaper.ivory), (wakeX, NoctisPaper.butter)] {
                let dot = CGRect(x: centerX - dotSize / 2, y: midY - dotSize / 2, width: dotSize, height: dotSize)
                context.fill(Circle().path(in: dot), with: .color(color))
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
