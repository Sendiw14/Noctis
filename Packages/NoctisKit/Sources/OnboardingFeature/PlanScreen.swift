import DesignSystem
import NoctisCore
import SwiftUI
import NoctisText

private enum PlanPhase: Equatable {
    case building
    case failed
    case ready
}

/// Step 6/6 — replaces the old building/ready pair with one screen, two
/// phases. Phase A runs real work (a HealthKit query, a baseline seed, the
/// profile write) behind a sunrise of rings and three rows (`PlanBuildingView`),
/// never faking progress: a row is checked when its work is done, and no later
/// than `PlanBuildFacts.minimumGap` after the one before (the work can be done
/// in milliseconds against the mock provider).
/// Phase B is a flat, data-aware summary — every number on it traces back
/// to either the Rhythm answers or the real night count Phase A found.
struct PlanScreen: View {
    let goals: [PrimaryGoal]
    /// The goals the chips show: what the person chose (none: no chips). `goals` is what is saved, and is never empty.
    let shownGoals: [PrimaryGoal]
    let wakeMinutes: Int
    let needMinutes: Int
    let onNext: () -> Void
    let onBack: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: PlanPhase
    @State private var completedLines: Set<PlanBuildLine> = []
    @State private var line1Override: String?
    @State private var nightCount: Int = 0
    @State private var buildGeneration = 0
    @State private var hasStarted = false
    @State private var moonShown = false
    @State private var pulsing = false
    init(
        goals: [PrimaryGoal],
        shownGoals: [PrimaryGoal]? = nil,
        wakeMinutes: Int,
        needMinutes: Int,
        startBuilt: Bool = false,
        onNext: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        self.goals = goals
        self.shownGoals = shownGoals ?? goals
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
        PlanBuildingView(
            rows: PlanBuildLine.allCases.map { PlanBuildRow(line: $0, text: resolvedText(for: $0), isDone: completedLines.contains($0)) },
            isFailed: phase == .failed,
            moonShown: moonShown,
            pulsing: pulsing,
            retry: retry,
            continueAnyway: continueAnyway
        )
    }

    private func resolvedText(for line: PlanBuildLine) -> String {
        if line == .nights, let override = line1Override { return override }
        return line.label
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
            var lastBeat = startedAt
            do {
                let count = try await model.fetchRecentNightCount()
                guard generation == buildGeneration else { return }
                nightCount = count
                if count == 0 {
                    line1Override = PlanBuildFacts.startingFresh
                }
                guard !isHeld(after: 0) else { return }
                await pace(since: lastBeat)
                guard generation == buildGeneration else { return }
                await markComplete(.nights)
                lastBeat = .now

                try await model.seedTypicalBedtimeBaseline()
                guard generation == buildGeneration, !isHeld(after: 1) else { return }
                await pace(since: lastBeat)
                guard generation == buildGeneration else { return }
                await markComplete(.bedtime)
                lastBeat = .now

                persistProfile()
                guard !isHeld(after: 2) else { return }
                await pace(since: lastBeat)
                guard generation == buildGeneration else { return }
                await markComplete(.profile)
                guard generation == buildGeneration else { return }

                await waitOutFloor(since: startedAt)
                guard generation == buildGeneration else { return }
                await finishBuild()
                guard generation == buildGeneration, !isHeld(after: 3) else { return }
                completeToPhaseB(announce: false)
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

    /// A row is shown at least `minimumGap` before the next completes. Reduce Motion jumps: no pacing between rows (the overall floor below still holds).
    private func pace(since last: Date) async {
        guard !reduceMotion else { return }
        let wait = noctisPlanBuildFloorDelay(elapsedSeconds: Date.now.timeIntervalSince(last), floorSeconds: PlanBuildFacts.minimumGap)
        guard wait > 0 else { return }
        try? await Task.sleep(for: .seconds(wait))
    }

    private func markComplete(_ line: PlanBuildLine) async {
        withAnimation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion)) {
            _ = completedLines.insert(line)
        }
        NoctisHaptics.softImpact()
        AccessibilityNotification.Announcement(PlanBuildFacts.announcement(done: resolvedText(for: line))).post()
    }

    /// All three are done: the moon fades in at the core, the rings breathe once (1.0, 1.02, 1.0), "Your plan is ready" is said, and a short hold before
    /// the plan. Reduce Motion: the moon is simply there and nothing pulses.
    private func finishBuild() async {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) { moonShown = true }
        if !reduceMotion {
            try? await Task.sleep(for: .seconds(0.4))
            pulsing = true
            try? await Task.sleep(for: .seconds(0.25))
            pulsing = false
            try? await Task.sleep(for: .seconds(0.25))
        }
        AccessibilityNotification.Announcement("Your plan is ready").post()
        try? await Task.sleep(for: .seconds(PlanBuildFacts.holdSeconds))
    }

    /// `-noctisPlanHold <0...3>` (DEBUG): stay on the building screen after that many rows are done (3: after the moon), for a still of each moment.
    private func isHeld(after done: Int) -> Bool {
        #if DEBUG
        let launch = ProcessInfo.processInfo.arguments
        if let flag = launch.firstIndex(of: "-noctisPlanHold"), launch.indices.contains(flag + 1), let hold = Int(launch[flag + 1]) { return hold <= done }
        #endif
        return false
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

    private func completeToPhaseB(announce: Bool = true) {
        NoctisHaptics.success()
        withAnimation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion)) {
            phase = .ready
        }
        if announce { AccessibilityNotification.Announcement("Your plan is ready").post() }
    }

    private func retry() {
        buildGeneration += 1
        completedLines = []
        line1Override = nil
        moonShown = false
        pulsing = false
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
        PlanReadyView(
            wakeMinutes: wakeMinutes, needMinutes: needMinutes, goals: shownGoals, nightCount: nightCount, onNext: onNext, onBack: onBack
        )
    }
}
