import DesignSystem
import NoctisCore
import SwiftUI

private enum PlanBuildLine: Int, CaseIterable, Identifiable {
    case nights
    case bedtime
    case profile

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .nights: "Reading your recent nights"
        case .bedtime: "Finding your typical bedtime"
        case .profile: "Setting your sleep need"
        }
    }
}

private enum PlanPhase: Equatable {
    case building
    case failed
    case ready
}

/// Step 6/6 — replaces the old building/ready pair with one screen, two
/// phases. Phase A runs real work (a HealthKit query, a baseline seed, the
/// profile write) behind a determinate ring + checklist, never faking
/// progress and never flashing past a `noctisPlanBuildFloorDelay` floor.
/// Phase B is a flat, data-aware summary — every number on it traces back
/// to either the Rhythm answers or the real night count Phase A found.
struct PlanScreen: View {
    let goals: [PrimaryGoal]
    let wakeMinutes: Int
    let needMinutes: Int
    let onNext: () -> Void
    let onBack: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var phase: PlanPhase
    @State private var completedLines: Set<PlanBuildLine> = []
    @State private var line1Override: String?
    @State private var nightCount: Int = 0
    @State private var buildGeneration = 0
    @State private var hasStarted = false
    init(
        goals: [PrimaryGoal],
        wakeMinutes: Int,
        needMinutes: Int,
        startBuilt: Bool = false,
        onNext: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        self.goals = goals
        self.wakeMinutes = wakeMinutes
        self.needMinutes = needMinutes
        self.onNext = onNext
        self.onBack = onBack
        self._phase = State(initialValue: startBuilt ? .ready : .building)
        self._completedLines = State(initialValue: startBuilt ? Set(PlanBuildLine.allCases) : [])
    }

    var body: some View {
        Group {
            switch phase {
            case .building, .failed:
                buildingView.transition(.opacity)
            case .ready:
                resultsView.transition(.opacity)
            }
        }
        .onAppear { startIfNeeded() }
    }

    // MARK: - Phase A

    private var buildingView: some View {
        OnboardingScaffold(step: nil, title: "Building your", emphasis: "plan.") {
            // R6: top-aligned, 24pt under the title; leftover space
            // collects above the bottom stack.
            VStack(spacing: NoctisSpacing.xl) {
                buildRing
                checklist
                if phase == .failed {
                    failureNotice
                        .noctisTextBlock()
                }
            }
            .frame(maxWidth: .infinity)
        } bottomStack: {
            if phase == .failed {
                VStack(spacing: NoctisSpacing.sm) {
                    NoctisCTA("Try again", action: retry)
                    NoctisTextButton("Continue anyway", action: continueAnyway)
                }
            } else {
                Color.clear.frame(height: 1)
            }
        }
    }

    private var buildRing: some View {
        ZStack {
            Circle()
                .stroke(NoctisPaper.track, lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(completedLines.count) / CGFloat(PlanBuildLine.allCases.count))
                .stroke(NoctisPaper.cocoa, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : NoctisMotion.settle, value: completedLines.count)
            Image(systemName: "moon.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(NoctisPaper.cocoa)
        }
        .frame(width: 150, height: 150)
        .accessibilityHidden(true)
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: NoctisScrollEdges.blockGap(NoctisSpacing.sm, dynamicTypeSize)) {
            ForEach(PlanBuildLine.allCases) { line in
                checklistRow(line)
                    .noctisTextBlock()
            }
        }
    }

    private func checklistRow(_ line: PlanBuildLine) -> some View {
        let isDone = completedLines.contains(line)
        let text = resolvedText(for: line)
        return HStack(spacing: NoctisSpacing.sm) {
            ChecklistMark(isDone: isDone, reduceMotion: reduceMotion)
            Text(text)
                .noctisFont(15, relativeTo: .subheadline)
                .foregroundStyle(isDone ? NoctisPaper.ink : NoctisPaper.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityValue(isDone ? "Completed" : "In progress")
    }

    private func resolvedText(for line: PlanBuildLine) -> String {
        if line == .nights, let override = line1Override { return override }
        return line.label
    }

    private var failureNotice: some View {
        Text("We couldn't read your latest sleep data.")
            .noctisFont(14, relativeTo: .subheadline)
            .foregroundStyle(NoctisPaper.ink2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, NoctisSpacing.xl)
    }

    // MARK: - Phase A orchestration

    private func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        if phase == .ready {
            refreshNightCountSilently()
        } else {
            runBuild()
        }
    }

    private func runBuild() {
        let generation = buildGeneration
        let startedAt = Date.now
        Task {
            do {
                let count = try await model.fetchRecentNightCount()
                guard generation == buildGeneration else { return }
                nightCount = count
                if count == 0 {
                    line1Override = "Starting fresh. We'll learn your pattern as you sleep."
                }
                await markComplete(.nights)
                guard generation == buildGeneration else { return }

                try await model.seedTypicalBedtimeBaseline()
                guard generation == buildGeneration else { return }
                await markComplete(.bedtime)
                guard generation == buildGeneration else { return }

                persistProfile()
                await markComplete(.profile)
                guard generation == buildGeneration else { return }

                await waitOutFloor(since: startedAt)
                guard generation == buildGeneration else { return }
                completeToPhaseB()
            } catch {
                guard generation == buildGeneration else { return }
                persistProfile()
                await waitOutFloor(since: startedAt)
                guard generation == buildGeneration else { return }
                withAnimation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion)) {
                    phase = .failed
                }
            }
        }
    }

    private func markComplete(_ line: PlanBuildLine) async {
        withAnimation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion)) {
            _ = completedLines.insert(line)
        }
        NoctisHaptics.selectionTick()
        AccessibilityNotification.Announcement(resolvedText(for: line)).post()
        guard !reduceMotion else { return }
        try? await Task.sleep(for: .seconds(0.3))
    }

    private func waitOutFloor(since startedAt: Date) async {
        let elapsed = Date.now.timeIntervalSince(startedAt)
        let remaining = noctisPlanBuildFloorDelay(elapsedSeconds: elapsed)
        guard remaining > 0 else { return }
        try? await Task.sleep(for: .seconds(remaining))
    }

    private func persistProfile() {
        model.updateProfile { profile in
            profile.selectedGoals = goals
            profile.primaryGoal = goals.first ?? .betterSleep
            profile.secondaryGoal = goals.count > 1 ? goals[1] : nil
            profile.typicalWakeMinutes = wakeMinutes
            profile.needMinutes = needMinutes
            profile.sleepGoalHours = Double(needMinutes) / 60
        }
    }

    private func completeToPhaseB() {
        NoctisHaptics.success()
        withAnimation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion)) {
            phase = .ready
        }
        AccessibilityNotification.Announcement("Your plan is ready.").post()
    }

    private func retry() {
        buildGeneration += 1
        completedLines = []
        line1Override = nil
        phase = .building
        runBuild()
    }

    private func continueAnyway() {
        buildGeneration += 1
        nightCount = 0
        persistProfile()
        completeToPhaseB()
    }

    /// Resuming mid-onboarding (`startBuilt`) skips replaying the build
    /// animation, but the real night count from that earlier run isn't
    /// persisted anywhere — re-fetching it quietly rather than guessing
    /// keeps Phase B's timeline honest instead of defaulting to a
    /// possibly-wrong "no history" state.
    private func refreshNightCountSilently() {
        Task {
            if let count = try? await model.fetchRecentNightCount() {
                nightCount = count
            }
        }
    }

    // MARK: - Phase B

    private var resultsView: some View {
        OnboardingScaffold(
            step: 5,
            title: "Your",
            emphasis: "plan is ready.",
            onBack: onBack
        ) {
            VStack(spacing: NoctisScrollEdges.blockGap(NoctisSpacing.lg, dynamicTypeSize)) {
                planCard
                timelineSection
            }
            .padding(.bottom, NoctisSpacing.xs)
        } bottomStack: {
            NoctisCTA("Continue", action: onNext)
        }
    }

    private var bedtimeMinutes: Int {
        noctisBedtimeMinutes(wakeMinutes: wakeMinutes, needMinutes: needMinutes)
    }

    private var planCard: some View {
        NoctisPaperCard {
            VStack(spacing: NoctisSpacing.lg) {
                // Three columns side by side; stacked at accessibility sizes,
                // or whenever large text can't fit three across (the values
                // never shrink, so all three always share one size).
                if dynamicTypeSize.isAccessibilitySize {
                    stackedPlanColumns
                } else {
                    ViewThatFits(in: .horizontal) {
                        planGrid
                        stackedPlanColumns
                    }
                }

                if !goals.isEmpty {
                    Rectangle().fill(NoctisPaper.hairline).frame(height: 1)
                    goalCapsules
                        .noctisTextBlock()
                }
            }
        }
        .noctisScrollRow()
        .noctisRise()
    }

    private var stackedPlanColumns: some View {
        VStack(spacing: NoctisScrollEdges.blockGap(NoctisSpacing.md, dynamicTypeSize)) {
            planColumn(icon: "moon.fill", fill: NoctisPaper.lavender, label: "Bedtime", number: bedtimeParts.number, suffix: bedtimeParts.suffix,
                       spoken: noctisFormattedClock(minutesSinceMidnight: bedtimeMinutes))
            planColumn(icon: "sun.max.fill", fill: NoctisPaper.butter, label: "Wake", number: wakeParts.number, suffix: wakeParts.suffix,
                       spoken: noctisFormattedClock(minutesSinceMidnight: wakeMinutes))
            planColumn(icon: "bed.double.fill", fill: NoctisPaper.sage, label: "Sleep need", number: needParts.number, suffix: needParts.suffix,
                       spoken: spokenDuration(needMinutes))
        }
    }

    // A `Grid` rather than three independent `planColumn` HStack cells: it
    // row-aligns the icons, labels and values across all three columns, so
    // a taller value in one column (the old "8h" vs. "11:00 PM" mismatch)
    // can never shift that column's icon out of line with its neighbors.
    private var planGrid: some View {
        Grid(alignment: .top, horizontalSpacing: NoctisSpacing.md, verticalSpacing: NoctisSpacing.xs) {
            GridRow {
                NoctisIconTile(systemImage: "moon.fill", fill: NoctisPaper.lavender, size: 40).frame(maxWidth: .infinity)
                NoctisIconTile(systemImage: "sun.max.fill", fill: NoctisPaper.butter, size: 40).frame(maxWidth: .infinity)
                NoctisIconTile(systemImage: "bed.double.fill", fill: NoctisPaper.sage, size: 40).frame(maxWidth: .infinity)
            }
            GridRow {
                planLabel("Bedtime")
                planLabel("Wake")
                planLabel("Sleep need")
            }
            GridRow {
                planValue(number: bedtimeParts.number, suffix: bedtimeParts.suffix)
                planValue(number: wakeParts.number, suffix: wakeParts.suffix)
                planValue(number: needParts.number, suffix: needParts.suffix)
            }
        }
        // VoiceOver reads each column as one pair ("Bedtime, 11:00 PM")
        // instead of the grid's row order (all three labels, then the
        // values and suffixes one by one).
        .accessibilityChildren {
            Text("Bedtime, \(noctisFormattedClock(minutesSinceMidnight: bedtimeMinutes))")
            Text("Wake, \(noctisFormattedClock(minutesSinceMidnight: wakeMinutes))")
            Text("Sleep need, \(spokenDuration(needMinutes))")
        }
    }

    /// "11:00" + "PM", "7:00" + "AM", "8" + "h" — one fixed value style
    /// (26pt heavy number, 13pt suffix, same baseline) with no scale factor,
    /// so all three always render at exactly the same size: the widest
    /// ("11:00 PM") fits its column at 26pt, and nothing shrinks alone.
    private var bedtimeParts: (number: String, suffix: String) { clockParts(minutesSinceMidnight: bedtimeMinutes) }
    private var wakeParts: (number: String, suffix: String) { clockParts(minutesSinceMidnight: wakeMinutes) }
    private var needParts: (number: String, suffix: String) { needValueParts(needMinutes) }

    private func clockParts(minutesSinceMidnight: Int) -> (number: String, suffix: String) {
        let normalized = ((minutesSinceMidnight % 1440) + 1440) % 1440
        let hour24 = normalized / 60
        let minute = normalized % 60
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        let period = hour24 < 12 ? "AM" : "PM"
        return (String(format: "%d:%02d", hour12, minute), period)
    }

    private func needValueParts(_ minutes: Int) -> (number: String, suffix: String) {
        let hours = minutes / 60
        let mins = minutes % 60
        return mins == 0 ? ("\(hours)", "h") : ("\(hours)h \(mins)m", "")
    }

    /// "8 hours", "7 hours 30 minutes" — for VoiceOver, where "8h" reads
    /// as "8 h".
    private func spokenDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        let hourText = "\(hours) hour\(hours == 1 ? "" : "s")"
        return mins == 0 ? hourText : "\(hourText) \(mins) minutes"
    }

    private func planLabel(_ text: String) -> some View {
        Text(text)
            .noctisFont(13, relativeTo: .footnote)
            .foregroundStyle(NoctisPaper.ink2)
            .frame(maxWidth: .infinity)
            .noctisTextBlock()
    }

    private func planValue(number: String, suffix: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            // Hero-numeral curve (.largeTitle, capped at 1.6x), never shrunk.
            Text(number)
                .noctisFont(26, .heavy, relativeTo: .largeTitle, maxScale: NoctisTypeScale.maxNumeralScale)
                .foregroundStyle(NoctisPaper.ink)
                .fixedSize()
            if !suffix.isEmpty {
                Text(suffix)
                    .noctisFont(13, .heavy, relativeTo: .largeTitle, maxScale: NoctisTypeScale.maxNumeralScale)
                    .foregroundStyle(NoctisPaper.ink)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity)
        .noctisTextBlock()
    }

    /// `spoken` is what VoiceOver reads for the value ("11:00 PM",
    /// "8 hours") — the combined number and suffix read as "8 , h".
    private func planColumn(icon: String, fill: Color, label: String, number: String, suffix: String, spoken: String) -> some View {
        VStack(spacing: NoctisSpacing.xs) {
            NoctisIconTile(systemImage: icon, fill: fill, size: 40)
            VStack(spacing: NoctisSpacing.xs) {
                planLabel(label)
                planValue(number: number, suffix: suffix)
            }
            .noctisTextBlock()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(spoken)")
    }

    /// GoalScreen caps selection at two: side by side, or stacked when
    /// large text can't fit both on one line.
    private var goalCapsules: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: NoctisSpacing.xs) {
                ForEach(goals, id: \.self) { goalChip($0) }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                ForEach(goals, id: \.self) { goalChip($0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func goalChip(_ goal: PrimaryGoal) -> some View {
        HStack(spacing: 6) {
            Image(systemName: goal.systemImage)
                .noctisIcon(12, relativeTo: .footnote)
                .accessibilityHidden(true)
            Text(goal.displayName)
                .noctisFont(13, .medium, relativeTo: .footnote)
        }
        .foregroundStyle(goalForeground(goal))
        .padding(.horizontal, NoctisSpacing.sm)
        .padding(.vertical, 6)
        .background(Capsule(style: .continuous).fill(goalFill(goal)))
        .fixedSize()
    }

    private func goalFill(_ goal: PrimaryGoal) -> Color {
        switch goal {
        case .betterSleep: NoctisPaper.lavender
        case .moreEnergy: NoctisPaper.orange
        case .betterRecovery: NoctisPaper.sage
        case .betterConsistency: NoctisPaper.butter
        case .betterFocus: NoctisPaper.cocoa
        }
    }

    private func goalForeground(_ goal: PrimaryGoal) -> Color {
        goal == .betterFocus ? NoctisPaper.ivory : NoctisPaper.ink
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: NoctisScrollEdges.blockGap(NoctisSpacing.md, dynamicTypeSize)) {
            Text("Your first two weeks")
                .noctisFont(15, .semibold, relativeTo: .subheadline)
                .foregroundStyle(NoctisPaper.ink)
                .noctisTextBlock()
            PlanTimeline(nodes: timelineNodes, reduceMotion: reduceMotion)
        }
        // A wrapped first row sizes this stack to its longest line; pin it
        // to the column's leading edge so it never drifts off the card's.
        .frame(maxWidth: .infinity, alignment: .leading)
        .noctisRise(index: 1)
    }

    private var timelineNodes: [String] {
        let first = nightCount > 0
            ? "Today: you already have \(nightCount) nights, so NOCTIS starts learning"
            : "Today: tonight is your first night, read in the morning"
        return [first, "Day 7: your first weekly review", "Day 14: early patterns appear"]
    }
}

// MARK: - Checklist mark

/// A 22pt mark: hollow hairline ring while pending, cocoa-filled with an
/// ivory checkmark once done. Normal motion draws the check via a 0.3s
/// path trim; Reduce Motion skips the draw and fades the completed mark in
/// over 0.2s instead (R9).
private struct ChecklistMark: View {
    let isDone: Bool
    let reduceMotion: Bool

    @State private var trimProgress: CGFloat = 0
    @State private var markOpacity: Double = 0
    /// R4: grows with the checklist line beside it.
    @NoctisScaledLength(relativeTo: .subheadline) private var diameter: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .fill(isDone ? NoctisPaper.cocoa : Color.clear)
                .overlay(Circle().stroke(isDone ? Color.clear : NoctisPaper.hairline, lineWidth: 1.5))
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : NoctisMotion.settle, value: isDone)
            PlanCheckmarkShape()
                .trim(from: 0, to: reduceMotion ? 1 : trimProgress)
                .stroke(NoctisPaper.ivory, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: diameter / 2, height: diameter / 2)
                .opacity(reduceMotion ? markOpacity : 1)
        }
        .frame(width: diameter, height: diameter)
        .onChange(of: isDone) { _, newValue in
            guard newValue else {
                trimProgress = 0
                markOpacity = 0
                return
            }
            if reduceMotion {
                withAnimation(.easeInOut(duration: 0.2)) { markOpacity = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.3)) { trimProgress = 1 }
            }
        }
    }
}

private struct PlanCheckmarkShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

// MARK: - Timeline

private struct LastDotCenterKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// The vertical connecting line used to just match whichever sibling in
/// the `ZStack` was tallest (the node text column) — since that column's
/// own bottom padding/line-height runs past the last dot's own center,
/// the line always overshot it. It's now explicitly sized to the last
/// dot's measured center via a preference key, so it starts at the first
/// node and ends exactly at the last, never past it. Reduce Motion skips
/// the growth and shows the full line immediately.
private struct PlanTimeline: View {
    let nodes: [String]
    let reduceMotion: Bool

    @State private var lineProgress: CGFloat = 0
    @State private var lineHeight: CGFloat = 0
    /// R4: rows scale on the subheadline curve; the dots grow with them
    /// and stay centered on each first line, with the rail through them.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var textSize: CGFloat = 14
    @NoctisScaledLength(relativeTo: .subheadline) private var dot: CGFloat = 10
    private var dotTopPadding: CGFloat { max((textSize * 1.19 - dot) / 2, 0) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(NoctisPaper.hairline)
                .frame(width: 2, height: lineHeight)
                .padding(.leading, dot / 2 - 1)
            Rectangle()
                .fill(NoctisPaper.cocoa)
                .frame(width: 2, height: lineHeight)
                .padding(.leading, dot / 2 - 1)
                .scaleEffect(x: 1, y: lineProgress, anchor: .top)

            VStack(alignment: .leading, spacing: NoctisScrollEdges.blockGap(NoctisSpacing.lg, dynamicTypeSize)) {
                ForEach(Array(nodes.enumerated()), id: \.offset) { index, text in
                    HStack(alignment: .top, spacing: NoctisSpacing.md) {
                        Circle()
                            .fill(NoctisPaper.cocoa)
                            .frame(width: dot, height: dot)
                            .padding(.top, dotTopPadding)
                            .background(
                                GeometryReader { dotGeometry in
                                    Color.clear.preference(
                                        key: LastDotCenterKey.self,
                                        value: index == nodes.count - 1
                                            ? dotGeometry.frame(in: .named("planTimeline")).midY
                                            : 0
                                    )
                                }
                            )
                        Text(text)
                            .font(.system(size: textSize, design: .rounded))
                            .foregroundStyle(NoctisPaper.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .noctisTextBlock()
                }
            }
        }
        .coordinateSpace(name: "planTimeline")
        .onPreferenceChange(LastDotCenterKey.self) { newValue in
            if newValue > 0 { lineHeight = newValue }
        }
        .onAppear {
            if reduceMotion {
                lineProgress = 1
            } else {
                withAnimation(NoctisMotion.drawIn) { lineProgress = 1 }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
