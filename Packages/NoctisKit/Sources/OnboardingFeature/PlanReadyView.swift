import DesignSystem
import NoctisCore
import NoctisText
import SwiftUI

/// The three days on "Your first two weeks", with the badge's word, what VoiceOver says, and its colour.
enum PlanReadyDay: CaseIterable {
    case today
    case daySeven
    case dayFourteen

    var badge: String {
        switch self {
        case .today: "TODAY"
        case .daySeven: "DAY 7"
        case .dayFourteen: "DAY 14"
        }
    }

    var spoken: String {
        switch self {
        case .today: "Today"
        case .daySeven: "Day 7"
        case .dayFourteen: "Day 14"
        }
    }

    var color: Color {
        switch self {
        case .today: NoctisSection.home.fill
        case .daySeven: NoctisPaper.lavender
        case .dayFourteen: NoctisPaper.sage
        }
    }
}

/// What "Your plan is ready" shows, worked out from the person's choices and apart from the view, so it is a unit test.
enum PlanReadyFacts {
    /// "11:00" and "PM".
    static func clockParts(minutesSinceMidnight: Int) -> (number: String, period: String) {
        let split = NoctisFormat().splitClock(noctisFormattedClock(minutesSinceMidnight: minutesSinceMidnight))
        return (split.time, split.period)
    }

    /// "8" and "h", or "7" "h" and "30" "m": each number with its small unit.
    static func needParts(minutes: Int) -> [(number: String, unit: String)] {
        var parts: [(String, String)] = []
        if minutes >= 60 { parts.append(("\(minutes / 60)", NoctisUnit.hour.symbol)) }
        if minutes % 60 != 0 || minutes < 60 { parts.append(("\(minutes % 60)", NoctisUnit.minute.symbol)) }
        return parts
    }

    /// The three lines under "Your first two weeks": the copy the plan has always had, without its "Today:", "Day 7:" and "Day 14:" (the badge says that now),
    /// and with the first letter up.
    static func timeline(nightCount: Int) -> [(day: PlanReadyDay, text: String)] {
        let first =
            nightCount > 0
            ? "You already have \(nightCount) nights, so NOCTIS starts learning"
            : "Tonight is your first night, read in the morning"
        return [(.today, first), (.daySeven, "Your first weekly review"), (.dayFourteen, "Early patterns appear")]
    }

    /// The same lines as they were written before the badges ("Today: tonight is ..."), for the test that holds the copy.
    static func legacyTimeline(nightCount: Int) -> [String] {
        timeline(nightCount: nightCount).map { item in
            let text = item.text.prefix(1).lowercased() + item.text.dropFirst()
            let prefix = item.day == .today ? "Today: " : item.day == .daySeven ? "Day 7: " : "Day 14: "
            // "NOCTIS" keeps its capitals; only the first word was ever lowered.
            return prefix + (text.hasPrefix("noctis") ? "NOCTIS" + text.dropFirst(6) : text)
        }
    }

    static func tileSpoken(label: String, value: String) -> String { "\(label), \(value)" }
}

/// Step 6/6, in the band style (APP_RULES.md R6, R69): the plan from the person's own choices: bedtime, wake and sleep need as three colour tiles, the
/// goals they picked as chips, and what the first two weeks hold. The values are worked out in `PlanReadyFacts`; this only draws them.
struct PlanReadyView: View {
    let wakeMinutes: Int
    let needMinutes: Int
    let goals: [PrimaryGoal]
    let nightCount: Int
    let onNext: () -> Void
    let onBack: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        OnboardingStepScaffold(
            section: .home, step: 5, title: ["Your", "plan is ready."], bandHeight: 244,
            topTrailingAccessory: AnyView(PlanSparkles(appeared: appeared || reduceMotion, reduceMotion: reduceMotion)),
            titleSize: 40, titleLeading: -6.5, onBack: onBack
        ) {
            PlanReadyContent(
                wakeMinutes: wakeMinutes, needMinutes: needMinutes, goals: goals, nightCount: nightCount, appeared: appeared || reduceMotion
            )
        } actions: {
            OnboardingPrimaryButton("Continue", identifier: "plan.continue", action: onNext)
        }
        .onAppear {
            guard !appeared else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8)) { appeared = true }
        }
    }
}

// MARK: - The content

private struct PlanReadyContent: View {
    let wakeMinutes: Int
    let needMinutes: Int
    let goals: [PrimaryGoal]
    let nightCount: Int
    let appeared: Bool

    @Environment(\.onboardingScale) private var scale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dark: Bool { colorScheme == .dark }
    private var compact: Bool { scale < 0.85 }
    private var ink: Color { dark ? NoctisPaper.ivory : NoctisPaper.ink }
    private var bedtimeMinutes: Int { noctisBedtimeMinutes(wakeMinutes: wakeMinutes, needMinutes: needMinutes) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tiles
            if !goals.isEmpty {
                focusRow.padding(.top, compact ? 10 : 16)
            }
            Text("Your first two weeks")
                .noctisFont(19, .heavy, relativeTo: .title3, maxScale: 1.3)
                .foregroundStyle(ink)
                .padding(.top, compact ? 14 : 24)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: compact ? 6 : 8) {
                ForEach(Array(PlanReadyFacts.timeline(nightCount: nightCount).enumerated()), id: \.offset) { index, item in
                    TimelineRow(day: item.day, text: item.text, compact: compact, dark: dark, stack: dynamicTypeSize.isAccessibilitySize)
                        .slideUp(index: index + 3, appeared: appeared, reduceMotion: reduceMotion, stagger: 0.06)
                }
            }
            .padding(.top, compact ? 8 : 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Tiles

    private var tileItems: [(label: String, icon: String, color: Color, parts: [(number: String, unit: String)], spoken: String)] {
        let bedtime = PlanReadyFacts.clockParts(minutesSinceMidnight: bedtimeMinutes)
        let wake = PlanReadyFacts.clockParts(minutesSinceMidnight: wakeMinutes)
        return [
            ("Bedtime", "moon.fill", NoctisPaper.lavender, [(bedtime.number, bedtime.period)], noctisFormattedClock(minutesSinceMidnight: bedtimeMinutes)),
            ("Wake", "sun.max.fill", NoctisPaper.butter, [(wake.number, wake.period)], noctisFormattedClock(minutesSinceMidnight: wakeMinutes)),
            ("Sleep need", "bed.double.fill", NoctisPaper.sage, PlanReadyFacts.needParts(minutes: needMinutes), NoctisDurationText.spoken(needMinutes)),
        ]
    }

    @ViewBuilder
    private var tiles: some View {
        let items = tileItems
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    StatTile(
                        label: item.label, icon: item.icon, color: item.color, parts: item.parts, spoken: item.spoken, wide: true, compact: compact, dark: dark,
                        index: index, appeared: appeared)
                }
            }
        } else {
            HStack(spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    StatTile(
                        label: item.label, icon: item.icon, color: item.color, parts: item.parts, spoken: item.spoken, wide: false, compact: compact,
                        dark: dark, index: index, appeared: appeared)
                }
            }
        }
    }

    // MARK: Goals

    private var focusRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                focusCaption
                ForEach(goals, id: \.self) { GoalChip(goal: $0, dark: dark, compact: compact) }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                focusCaption
                ForEach(goals, id: \.self) { GoalChip(goal: $0, dark: dark, compact: compact) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 4)
        .slideUp(index: 3, appeared: appeared, reduceMotion: reduceMotion, stagger: 0.06)
    }

    private var focusCaption: some View {
        Text("FOCUS")
            .noctisFont(11, .bold, relativeTo: .caption2, maxScale: 1.3)
            .tracking(1.2)
            .foregroundStyle(ink.opacity(0.65))
            .fixedSize()
            .padding(.trailing, compact ? 0 : 4)
    }
}

// MARK: - A stat tile

private struct StatTile: View {
    let label: String
    let icon: String
    let color: Color
    let parts: [(number: String, unit: String)]
    let spoken: String
    let wide: Bool
    let compact: Bool
    let dark: Bool
    let index: Int
    let appeared: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    var body: some View {
        let layout = wide ? AnyLayout(HStackLayout(alignment: .center, spacing: 14)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
        layout {
            ZStack {
                Circle().fill(NoctisPaper.ivory)
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(NoctisPaper.ink)
            }
            .frame(width: compact ? 32 : 36, height: compact ? 32 : 36)
            if !wide { Spacer(minLength: 6) }
            VStack(alignment: .leading, spacing: 1) {
                // 90%, not the design's 75%: on the lavender 75% is 3.8:1 (BandStyleContrastTests), and this is 11 pt text.
                Text(label.uppercased())
                    .noctisFont(11, .bold, relativeTo: .caption2, maxScale: 1.3)
                    .tracking(0.9)
                    .foregroundStyle(NoctisPaper.ink.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                value
            }
            if wide { Spacer(minLength: 0) }
        }
        .padding(.horizontal, compact ? 12 : 14)
        .padding(.vertical, compact ? 10 : 14)
        .frame(maxWidth: .infinity, minHeight: wide ? 0 : (compact ? 106 : 130), alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(color))
        .shadow(color: dark ? .clear : NoctisPaper.ink.opacity(0.12), radius: 10, x: 0, y: 5)
        .scaleEffect(appeared ? 1 : 0.9)
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.72).delay(Double(index) * 0.06), value: appeared)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PlanReadyFacts.tileSpoken(label: label, value: spoken))
        .accessibilityIdentifier("plan.tile.\(label.lowercased().replacingOccurrences(of: " ", with: ""))")
        .onChange(of: appeared) { _, new in
            guard new, !reduceMotion else { return }
            Task {
                try? await Task.sleep(for: .seconds(0.15 + Double(index) * 0.06))
                withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { settled = true }
            }
        }
        .onAppear { if reduceMotion { settled = true } }
    }

    /// The number and its small unit, one line, shrinking a little (never below 0.7) rather than wrap or clip: the largest that fits wins.
    private var value: some View {
        ViewThatFits(in: .horizontal) {
            valueRow(number: 26, unit: 13)
            valueRow(number: 23, unit: 12)
            valueRow(number: 20, unit: 11)
            valueRow(number: 18, unit: 10)
        }
    }

    /// The digits roll to their value as the tile settles (they start at zero, same length); Reduce Motion shows the value at once.
    private func shown(_ number: String) -> String {
        settled || reduceMotion ? number : String(number.map { $0.isNumber ? "0" : $0 })
    }

    private func valueRow(number size: CGFloat, unit unitSize: CGFloat) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                Text(shown(part.number))
                    .noctisFont(size, .heavy, relativeTo: .largeTitle, maxScale: NoctisTypeScale.maxNumeralScale)
                    .foregroundStyle(NoctisPaper.ink)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .fixedSize()
                Text(part.unit)
                    .noctisFont(unitSize, .heavy, relativeTo: .largeTitle, maxScale: NoctisTypeScale.maxNumeralScale)
                    .foregroundStyle(NoctisPaper.ink.opacity(0.9))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.trailing, 3)
            }
        }
    }
}

// MARK: - A goal chip

private struct GoalChip: View {
    let goal: PrimaryGoal
    let dark: Bool
    /// A short screen (an SE): a little less padding so both chips and the caption stay on one line.
    let compact: Bool

    private var onCocoa: Bool { GoalPresentation.fill(goal) == NoctisPaper.cocoa }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: GoalPresentation.glyph(goal)).font(.system(size: 12, weight: .semibold)).accessibilityHidden(true)
            Text(GoalPresentation.title(goal)).noctisFont(compact ? 12.5 : 13, .semibold, relativeTo: .footnote, maxScale: 1.25)
        }
        .foregroundStyle(onCocoa ? NoctisPaper.ivory : NoctisPaper.ink)
        .padding(.horizontal, compact ? 9 : 12)
        .padding(.vertical, compact ? 7 : 8)
        .background(Capsule(style: .continuous).fill(GoalPresentation.fill(goal)))
        .overlay { if onCocoa && dark { Capsule(style: .continuous).strokeBorder(NoctisPaper.ivory.opacity(0.14), lineWidth: 1) } }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus, \(GoalPresentation.title(goal))")
        .accessibilityIdentifier("plan.chip.\(goal.rawValue)")
    }
}

// MARK: - A timeline row

private struct TimelineRow: View {
    let day: PlanReadyDay
    let text: String
    let compact: Bool
    let dark: Bool
    let stack: Bool

    var body: some View {
        let layout = stack ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Text(day.badge)
                .noctisFont(11, .heavy, relativeTo: .caption2, maxScale: 1.3)
                .tracking(0.8)
                .foregroundStyle(NoctisPaper.ink)
                .padding(.horizontal, 12)
                .frame(minWidth: 72, minHeight: compact ? 30 : 34)
                .background(Capsule(style: .continuous).fill(day.color))
                .fixedSize()
            Text(text)
                .noctisFont(14.5, relativeTo: .subheadline, maxScale: 1.3)
                .foregroundStyle(dark ? NoctisPaper.ivory : NoctisPaper.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !stack { Spacer(minLength: 0) }
        }
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: compact ? 46 : 54, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 27, style: .continuous).fill(dark ? NoctisPaper.ivory.opacity(0.09) : NoctisPaper.surface))
        .shadow(color: dark ? .clear : NoctisPaper.ink.opacity(0.09), radius: 8, x: 0, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.spoken), \(text)")
        .accessibilityIdentifier("plan.day.\(day.badge.lowercased().replacingOccurrences(of: " ", with: ""))")
    }
}

// MARK: - The sparkles

/// One large and two small ivory four-point stars in a 64 pt box; they pop in, and each twinkles once. Hidden from VoiceOver.
private struct PlanSparkles: View {
    let appeared: Bool
    let reduceMotion: Bool

    @State private var twinkle = false

    var body: some View {
        ZStack {
            star(size: 44, x: -8, y: 4, index: 0)
            star(size: 20, x: 20, y: -22, index: 1)
            star(size: 16, x: 22, y: 20, index: 2)
        }
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
        .onChange(of: appeared) { _, new in
            guard new, !reduceMotion else { return }
            Task {
                try? await Task.sleep(for: .seconds(0.9))
                twinkle = true
                try? await Task.sleep(for: .seconds(0.45))
                twinkle = false
            }
        }
    }

    private func star(size: CGFloat, x: CGFloat, y: CGFloat, index: Int) -> some View {
        SparkleShape()
            .fill(NoctisPaper.ivory)
            .frame(width: size, height: size)
            .scaleEffect((appeared ? 1 : 0.2) * (twinkle ? 1.18 : 1))
            .opacity(appeared ? 1 : 0)
            .offset(x: x, y: y)
            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.6).delay(0.1 * Double(index)), value: appeared)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: twinkle)
    }
}
