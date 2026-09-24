import DesignSystem
import Foundation
import Testing
@testable import HealthProviding
@testable import HomeFeature
@testable import InsightsKit
@testable import NoctisCore
@testable import RecoveryKit
@testable import SleepKit

/// Every string and number Home shows, from `HomeScreenBuilder`, in
/// en_US on New York time.
struct HomeScreenBuilderTests {
    private let locale = Locale(identifier: "en_US")
    private let calendar = Fixture.calendar()
    private let now = Fixture.date(2026, 9, 24, 10)
    private let lastNightKey = SleepNightKey(year: 2026, month: 9, day: 23)

    /// Formatted clock times use a narrow no-break space before AM/PM.
    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    private func screen(_ scenario: MockScenario, authorized: Bool = true, available: Bool = true, fails: Bool = false) async -> HomeScreen {
        let provider = MockHealthKitProvider(scenario: scenario, referenceDate: now, calendar: calendar,
                                             startAuthorized: authorized, isHealthDataAvailable: available, failsQueries: fails)
        let clock = now
        let snapshot = await HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { clock }).refresh(profile: UserProfileSnapshot())
        return HomeScreenBuilder.build(snapshot, now: now, calendar: calendar, locale: locale)
    }

    /// Last night: awake 11:02–11:05 PM, core to 1:00, deep to 2:00, REM
    /// to 3:00, core to 7:27 AM (502 minutes asleep).
    private var stagedNight: [RawSleepSample] {
        [
            Fixture.sample(Fixture.date(2026, 9, 23, 23, 2), Fixture.date(2026, 9, 23, 23, 5), .awake),
            Fixture.sample(Fixture.date(2026, 9, 23, 23, 5), Fixture.date(2026, 9, 24, 1), .core),
            Fixture.sample(Fixture.date(2026, 9, 24, 1), Fixture.date(2026, 9, 24, 2), .deep),
            Fixture.sample(Fixture.date(2026, 9, 24, 2), Fixture.date(2026, 9, 24, 3), .rem),
            Fixture.sample(Fixture.date(2026, 9, 24, 3), Fixture.date(2026, 9, 24, 7, 27), .core),
        ]
    }

    private func snapshot(sleep: [RawSleepSample], profile: UserProfileSnapshot = UserProfileSnapshot()) -> HomeSnapshot {
        HomeSnapshotBuilder.build(HomeHealthInputs(sleep: sleep, hrv: [], restingHeartRate: [], heartRate: []),
                                  profile: profile, now: now, timeZone: Fixture.newYork)
    }

    // MARK: - Header

    @Test(arguments: [
        (3, 59, "evening"), (4, 0, "morning"), (11, 59, "morning"),
        (12, 0, "afternoon"), (17, 59, "afternoon"), (18, 0, "evening"), (23, 30, "evening"),
    ])
    func greetingFollowsTheTimeOfDay(hour: Int, minute: Int, word: String) {
        let header = HomeScreenBuilder.header(now: Fixture.date(2026, 9, 24, hour, minute), newestSample: nil, calendar: calendar, locale: locale)
        #expect(header.greetingEmphasis == word)
        #expect(header.greeting == "Good \(word).")
    }

    @Test func dateIsLocaleFormatted() {
        let header = HomeScreenBuilder.header(now: now, newestSample: nil, calendar: calendar, locale: locale)
        #expect(header.date == "Thursday, September 24")
    }

    @Test func updatedCaptionOnlyAfterAnHour() {
        #expect(HomeScreenBuilder.updatedCaption(age: 59 * 60) == nil)
        #expect(HomeScreenBuilder.updatedCaption(age: 3600) == nil)
        #expect(HomeScreenBuilder.updatedCaption(age: 2 * 3600 + 5) == "Updated 2h ago")
        #expect(HomeScreenBuilder.updatedCaption(age: 30.4 * 3600) == "Updated 30h ago")
        #expect(HomeScreenBuilder.updatedCaption(age: 75 * 3600) == "Updated 3 days ago")
    }

    // MARK: - States

    @Test func fullStateShowsEveryCard() async throws {
        let screen = await screen(.full)
        guard case .scored(let scored) = screen.recovery else { Issue.record("expected a score"); return }
        #expect(scored.segments.map(\.kind) == [.sleepDuration, .hrv, .restingHeartRate, .sleepConsistency])
        #expect(abs(scored.segments.map(\.weight).reduce(0, +) - 1) < 1e-9)
        #expect(scored.factors.map(\.name) == ["Sleep", "HRV", "Resting HR", "Consistency"])
        #expect(scored.confidence == "High confidence · sleep, HRV, heart rate, consistency")
        #expect(screen.lastNight != nil)
        #expect(screen.insight?.title == "Shorter night than usual")
        #expect(screen.week?.bars.count == 7)
        #expect(screen.detail?.rows.count == 4)
        #expect(screen.header.updated == nil)
    }

    @Test func sleepOnlyStateNamesWhatIsMissing() async {
        let screen = await screen(.sleepOnly)
        guard case .scored(let scored) = screen.recovery else { Issue.record("expected a score"); return }
        #expect(scored.segments.map(\.kind) == [.sleepDuration, .sleepConsistency])
        // The mock's 14-night window makes this moderate (RecoveryModelV1).
        #expect(scored.confidence == "Moderate confidence · sleep only. HRV and heart rate aren't available from your sources.")
    }

    @Test func learningStateCountsNightsTowardFive() async {
        let screen = await screen(.learning)
        #expect(screen.recovery == .learning(nights: 3, required: 5, text: "Learning your baseline · 3 of 5 nights"))
        #expect(screen.lastNight != nil)
        #expect(screen.week != nil)
        #expect(screen.insight == nil)
        #expect(screen.detail == nil)
    }

    @Test func gapStateSaysNoSleepAndWhenTheLastWas() async {
        let screen = await screen(.gap)
        guard case .noSleep(let title, let detail) = screen.recovery else { Issue.record("expected no sleep"); return }
        #expect(title == "No sleep recorded last night.")
        #expect(detail == "Last sleep recorded Wednesday, September 23.")
        #expect(screen.lastNight == nil)
        #expect(screen.week?.bars.last?.fraction == nil)
    }

    @Test func staleStateShowsHowOldTheDataIs() async {
        let screen = await screen(.stale)
        #expect(screen.header.updated == "Updated 30h ago")
        guard case .noSleep = screen.recovery else { Issue.record("expected no sleep"); return }
    }

    @Test func emptyAndNoPermissionOfferToConnect() async {
        for screen in [await screen(.empty), await screen(.full, authorized: false)] {
            #expect(screen.recovery == .connect(title: "Your first night starts here.",
                                                message: "Connect Apple Health so NOCTIS can read your nights.", showsButton: true))
            #expect(screen.lastNight == nil && screen.insight == nil && screen.week == nil)
            #expect(plain(screen.tonight.bedtime) == "Bedtime around 11:00 PM")
        }
    }

    @Test func withoutHealthThereIsNoConnectButton() async {
        let screen = await screen(.full, available: false)
        #expect(screen.recovery == .connect(title: "Your first night starts here.",
                                            message: "Apple Health isn't available on this device.", showsButton: false))
    }

    @Test func aFailedReadIsStatedWithTheTonightCardOnly() async {
        let screen = await screen(.full, fails: true)
        #expect(screen.recovery == .failed(message: "We couldn't read your latest sleep data."))
        #expect(screen.lastNight == nil && screen.week == nil)
    }

    // MARK: - Recovery card

    private func result(score: Int = 82, delta: Int?, confidence: RecoveryConfidence = .moderate) -> RecoveryResult {
        RecoveryResult(
            night: lastNightKey, score: score,
            factors: [
                RecoveryFactor(kind: .sleepDuration, score: 91, weight: 0.35, value: 470, baseline: 450, delta: 20),
                RecoveryFactor(kind: .sleepConsistency, score: 74, weight: 0.2, value: 31, baseline: nil, delta: 25),
                RecoveryFactor(kind: .hrv, score: 78, weight: 0.25, value: 48, baseline: 44, delta: 4),
                RecoveryFactor(kind: .restingHeartRate, score: 85, weight: 0.2, value: 52, baseline: 54, delta: -2),
            ],
            confidence: confidence, baselineNights: 14, modelVersion: "recovery-v1",
            comparison: RecoveryComparison(baseline: delta.map { Double(score - $0) }, nights: 14, delta: delta)
        )
    }

    @Test func ringSummaryReadsLikeASentence() {
        let content = HomeScreenBuilder.scoredContent(result(delta: 6))
        #expect(content.accessibilityLabel == "Recovery 82, 6 above your baseline, moderate confidence. Sleep 91, HRV 78, resting heart rate 85, consistency 74.")
        #expect(HomeScreenBuilder.scoredContent(result(delta: -4)).accessibilityLabel.hasPrefix("Recovery 82, 4 below your baseline,"))
        #expect(HomeScreenBuilder.scoredContent(result(delta: nil)).accessibilityLabel.hasPrefix("Recovery 82, moderate confidence."))
    }

    @Test func deltaChipAlwaysShowsItsSignAndTone() {
        #expect(HomeScreenBuilder.scoredContent(result(delta: 6)).chip == DeltaChip(text: "+6 vs your baseline", tone: .above))
        #expect(HomeScreenBuilder.scoredContent(result(delta: 3)).chip?.tone == .above)
        #expect(HomeScreenBuilder.scoredContent(result(delta: 2)).chip == DeltaChip(text: "+2 vs your baseline", tone: .inLine))
        #expect(HomeScreenBuilder.scoredContent(result(delta: 0)).chip == DeltaChip(text: "±0 vs your baseline", tone: .inLine))
        #expect(HomeScreenBuilder.scoredContent(result(delta: -2)).chip?.tone == .inLine)
        #expect(HomeScreenBuilder.scoredContent(result(delta: -3)).chip == DeltaChip(text: "\u{2212}3 vs your baseline", tone: .below))
        #expect(HomeScreenBuilder.scoredContent(result(delta: nil)).chip == nil)
    }

    @Test func confidenceLineExplainsMissingHeartData() {
        func line(_ gaps: [RecoveryFactorKind: RecoveryFactorGap]) -> String {
            HomeScreenBuilder.confidenceLine(RecoveryResult(
                night: lastNightKey, score: 70,
                factors: [RecoveryFactor(kind: .sleepDuration, score: 70, weight: 1, value: 400, baseline: nil, delta: nil)],
                confidence: .low, baselineNights: 4, modelVersion: "recovery-v1", missingFactors: gaps
            ))
        }
        #expect(line([.hrv: .unavailable, .restingHeartRate: .unavailable])
            == "Low confidence · sleep only. HRV and heart rate aren't available from your sources.")
        #expect(line([.hrv: .notRecorded, .restingHeartRate: .unavailable])
            == "Low confidence · sleep only. Heart rate isn't available from your sources. HRV wasn't recorded last night.")
        #expect(line([.hrv: .buildingBaseline, .restingHeartRate: .buildingBaseline])
            == "Low confidence · sleep only. HRV and heart rate baselines are still forming.")
        #expect(HomeScreenBuilder.confidenceLine(result(delta: 1)) == "Moderate confidence · sleep, HRV, heart rate, consistency")
    }

    // MARK: - Last night

    @Test func lastNightShowsDurationTimesAndStages() throws {
        let card = try #require(HomeScreenBuilder.build(snapshot(sleep: stagedNight), now: now, calendar: calendar, locale: locale).lastNight)
        #expect(card.duration == "8h 22m")
        #expect(plain(card.timeRange) == "11:02 PM – 7:27 AM")
        guard case .stages(let segments, let legend) = card.strip else { Issue.record("expected stages"); return }
        #expect(segments.map(\.stage) == [.awake, .core, .deep, .rem, .core])
        #expect(segments.first?.start == 0)
        #expect(segments.last?.end == 1)
        #expect(abs(segments[1].start - 3.0 / 505.0) < 1e-9)
        #expect(legend == [.deep, .core, .rem, .awake])
        #expect(plain(card.accessibilityLabel) == "Last night, slept 8h 22m, 11:02 PM to 7:27 AM. Deep 1h, Core 6h 22m, REM 1h, Awake 3m.")
    }

    @Test func adjacentSegmentsOfOneStageMerge() throws {
        let samples = [
            Fixture.sample(Fixture.date(2026, 9, 23, 23), Fixture.date(2026, 9, 24, 1), .core),
            Fixture.sample(Fixture.date(2026, 9, 24, 1), Fixture.date(2026, 9, 24, 3), .core),
            Fixture.sample(Fixture.date(2026, 9, 24, 3), Fixture.date(2026, 9, 24, 7), .deep),
        ]
        let card = try #require(HomeScreenBuilder.build(snapshot(sleep: samples), now: now, calendar: calendar, locale: locale).lastNight)
        guard case .stages(let segments, _) = card.strip else { Issue.record("expected stages"); return }
        #expect(segments == [StripSegment(stage: .core, start: 0, end: 0.5), StripSegment(stage: .deep, start: 0.5, end: 1)])
    }

    @Test func withoutStagesTheStripSaysSo() throws {
        let samples = [Fixture.sample(Fixture.date(2026, 9, 23, 23), Fixture.date(2026, 9, 24, 7), .unspecified)]
        let card = try #require(HomeScreenBuilder.build(snapshot(sleep: samples), now: now, calendar: calendar, locale: locale).lastNight)
        #expect(card.strip == .noStages(caption: "Stages aren't available from your current sources."))
    }

    // MARK: - Tonight and This week

    @Test func tonightComesFromWakeTimeAndNeed() {
        var profile = UserProfileSnapshot()
        profile.typicalWakeMinutes = 6 * 60 + 30
        profile.needMinutes = 8 * 60 + 15
        let tonight = HomeScreenBuilder.build(snapshot(sleep: [], profile: profile), now: now, calendar: calendar, locale: locale).tonight
        #expect(plain(tonight.bedtime) == "Bedtime around 10:15 PM")
        #expect(plain(tonight.detail) == "Wake 6:30 AM · 8h 15m need")
    }

    @Test func weekBarsScaleToTheLongestNightOrTheNeed() throws {
        // Sep 21: 6h, Sep 22: none, Sep 23: 8h 22m (last night).
        let samples = Fixture.plainNight(september: 21, hours: 6) + stagedNight
        let week = try #require(HomeScreenBuilder.build(snapshot(sleep: samples), now: now, calendar: calendar, locale: locale).week)
        let top = 502 * HomeScreenBuilder.weekHeadroom
        #expect(week.bars.map(\.label) == ["F", "S", "S", "M", "T", "W", "T"])
        #expect(week.bars.map { $0.fraction == nil } == [true, true, true, true, false, true, false])
        #expect(abs((week.bars[4].fraction ?? 0) - 360 / top) < 1e-9)
        #expect(abs((week.bars[6].fraction ?? 0) - 502 / top) < 1e-9)
        #expect(week.bars.map(\.isLastNight) == [false, false, false, false, false, false, true])
        #expect(abs(week.needFraction - 480 / top) < 1e-9)
        #expect(week.needLabel == "8h need")
        #expect(week.average == "Avg 7h 11m")
        #expect(week.bars[5].accessibilityLabel == "Wednesday, no data")
        #expect(week.bars[6].accessibilityLabel == "Thursday, 8h 22m")
    }

    // MARK: - Recovery detail

    @Test func detailRowsStateValueBaselineAndOneSentence() {
        let result = result(delta: 6)
        let rows = HomeScreenBuilder.factorOrder.compactMap { result.factor($0) }.map {
            HomeScreenBuilder.detailRow($0, result: result, needMinutes: 480, format: HomeFormat(calendar: calendar, locale: locale))
        }
        #expect(rows[0] == FactorDetailRow(kind: .sleepDuration, name: "Sleep", value: "Sleep 7h 50m", baseline: "baseline 7h 30m",
                                           score: 91, sentence: "You slept 7h 50m of your 8h need."))
        #expect(rows[1] == FactorDetailRow(kind: .hrv, name: "HRV", value: "HRV 48 ms", baseline: "baseline 44 ms",
                                           score: 78, sentence: "9% above your baseline."))
        #expect(rows[2] == FactorDetailRow(kind: .restingHeartRate, name: "Resting HR", value: "Resting HR 52 bpm", baseline: "baseline 54 bpm",
                                           score: 85, sentence: "2 bpm below your baseline."))
        #expect(rows[3].value == "Consistency 31 min off")
        #expect(rows[3].sentence == "Bedtime and wake time were 31 min from your usual, on average.")
    }

    @Test func consistencyRowShowsTheUsualTimes() {
        let baselines = Baselines(sleepDuration: nil, bedtime: Baseline(value: 665, nights: 14), wakeTime: Baseline(value: 1142, nights: 14), hrv: nil, restingHeartRate: nil)
        let factor = RecoveryFactor(kind: .sleepConsistency, score: 100, weight: 1, value: 0.2, baseline: nil, delta: 0)
        let result = RecoveryResult(night: lastNightKey, score: 100, factors: [factor], confidence: .low, baselineNights: 14,
                                    modelVersion: "recovery-v1", baselines: baselines)
        let row = HomeScreenBuilder.detailRow(factor, result: result, needMinutes: 480, format: HomeFormat(calendar: calendar, locale: locale))
        #expect(plain(row.baseline) == "usual 11:05 PM – 7:02 AM")
        #expect(row.sentence == "Right on your usual bedtime and wake time.")
    }

    @Test func calculationNamesTheWeightsAndTheModel() async throws {
        let detail = try #require(await screen(.full).detail)
        #expect(detail.modelVersion == "Model recovery-v1")
        #expect(detail.calculation[0].contains("(35%)") && detail.calculation[0].contains("(25%)") && detail.calculation[0].contains("(20%)"))
        #expect(detail.calculation[1] == "Today all four signals count.")

        let sleepOnly = try #require(await screen(.sleepOnly).detail)
        #expect(sleepOnly.calculation[1].hasSuffix("Today: sleep 64%, consistency 36%."))
    }
}

// MARK: - Snapshot additions

struct HomeSnapshotAdditionsTests {
    private let now = Fixture.date(2026, 9, 24, 10)

    @Test func weekAverageUsesOnlyNightsWithData() {
        let nights = [NightDuration(night: SleepNightKey(year: 2026, month: 9, day: 22), asleepMinutes: 420),
                      NightDuration(night: SleepNightKey(year: 2026, month: 9, day: 23), asleepMinutes: nil),
                      NightDuration(night: SleepNightKey(year: 2026, month: 9, day: 24), asleepMinutes: 480)]
        #expect(HomeSnapshotBuilder.averageMinutes(nights) == 450)
        #expect(HomeSnapshotBuilder.averageMinutes([NightDuration(night: SleepNightKey(year: 2026, month: 9, day: 23), asleepMinutes: nil)]) == nil)
    }

    @Test func snapshotKeepsTheNewestSampleAndLatestSleep() {
        let samples = Fixture.plainNight(september: 21)
        let heartRate = [HeartRateSample(date: Fixture.date(2026, 9, 24, 9, 30), bpm: 70, sourceName: "Watch")]
        let snapshot = HomeSnapshotBuilder.build(HomeHealthInputs(sleep: samples, hrv: [], restingHeartRate: [], heartRate: heartRate),
                                                 profile: UserProfileSnapshot(), now: now, timeZone: Fixture.newYork)
        #expect(snapshot.newestSample == Fixture.date(2026, 9, 24, 9, 30))
        #expect(snapshot.latestSleep?.night == SleepNightKey(year: 2026, month: 9, day: 21))
        #expect(snapshot.lastNight == nil)
        #expect(snapshot.weekAverageMinutes == 480)
    }
}

// MARK: - Ring layout

struct RecoveryRingLayoutTests {
    @Test func arcsSplitTheRingByWeightWithThreeDegreeGaps() {
        let arcs = NoctisRecoveryRingLayout.arcs(weights: [35, 25, 20, 20])
        let spans: [Double] = arcs.map { $0.end - $0.start }
        let total: Double = spans.reduce(0, +)
        let expectedTotal: Double = 360 - 4 * 3
        #expect(abs(total - expectedTotal) < 1e-9)
        let ratio: Double = spans[0] / spans[1]
        #expect(abs(ratio - 35.0 / 25.0) < 1e-9)
        for (previous, next) in zip(arcs, arcs.dropFirst()) {
            #expect(abs(next.start - previous.end - 3) < 1e-9)
        }
        // The gap straddles the top: 1.5° either side of 12 o'clock.
        #expect(arcs.first?.start == 1.5)
        #expect(abs((arcs.last?.end ?? 0) - 358.5) < 1e-9)
    }

    @Test func missingFactorsAreSimplyAbsent() {
        #expect(NoctisRecoveryRingLayout.arcs(weights: [35.0 / 55.0, 20.0 / 55.0]).count == 2)
        #expect(NoctisRecoveryRingLayout.arcs(weights: []).isEmpty)
    }

    @Test func segmentsFillOneAfterAnother() {
        let weights = [0.5, 0.5]
        let fractions = [0.8, 0.6]
        #expect(NoctisRecoveryRingLayout.visibleFractions(weights: weights, fractions: fractions, reveal: 0) == [0, 0])
        #expect(NoctisRecoveryRingLayout.visibleFractions(weights: weights, fractions: fractions, reveal: 0.25) == [0.4, 0])
        #expect(NoctisRecoveryRingLayout.visibleFractions(weights: weights, fractions: fractions, reveal: 0.75) == [0.8, 0.3])
        #expect(NoctisRecoveryRingLayout.visibleFractions(weights: weights, fractions: fractions, reveal: 1) == [0.8, 0.6])
    }
}

// MARK: - View model

struct HomeViewModelIntroTests {
    private func defaults() -> UserDefaults {
        let name = "noctis.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    private func viewModel(scenario: MockScenario = .full, at date: Date, defaults: UserDefaults, reduceMotion: Bool = false,
                           connect: @escaping () async -> Void = {}) -> HomeViewModel {
        let provider = MockHealthKitProvider(scenario: scenario, referenceDate: date, calendar: Fixture.calendar(), startAuthorized: true)
        let repository = HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { date })
        return HomeViewModel(repository: repository, profile: { UserProfileSnapshot() }, connectHealth: connect,
                             introGate: HomeIntroGate(defaults: defaults), reduceMotion: { reduceMotion },
                             clock: { date }, calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"))
    }

    @Test func theRingDrawsInOncePerDay() async {
        let store = defaults()
        let morning = viewModel(at: Fixture.date(2026, 9, 24, 10), defaults: store)
        await morning.refresh()
        #expect(morning.introPending)
        #expect(morning.consumeIntro())
        #expect(!morning.consumeIntro())
        await morning.refresh()
        #expect(!morning.introPending)

        let evening = viewModel(at: Fixture.date(2026, 9, 24, 20), defaults: store)
        await evening.refresh()
        #expect(!evening.introPending)

        let tomorrow = viewModel(at: Fixture.date(2026, 9, 25, 10), defaults: store)
        await tomorrow.refresh()
        #expect(tomorrow.introPending)
    }

    @Test func reduceMotionSkipsTheIntroButStillUsesTheDay() async {
        let store = defaults()
        let calm = viewModel(at: Fixture.date(2026, 9, 24, 10), defaults: store, reduceMotion: true)
        await calm.refresh()
        #expect(!calm.introPending)
        let later = viewModel(at: Fixture.date(2026, 9, 24, 11), defaults: store)
        await later.refresh()
        #expect(!later.introPending)
    }

    @Test func noIntroWithoutAScore() async {
        let learning = viewModel(scenario: .learning, at: Fixture.date(2026, 9, 24, 10), defaults: defaults())
        await learning.refresh()
        #expect(!learning.introPending)
    }

    @Test func theHeaderIsReadyBeforeAnyData() {
        let fresh = viewModel(at: Fixture.date(2026, 9, 24, 15), defaults: defaults())
        #expect(fresh.screen == nil)
        #expect(fresh.header.greeting == "Good afternoon.")
    }

    @Test func connectingRunsTheAuthorizationFlowThenRereads() async {
        var asked = 0
        let model = viewModel(scenario: .empty, at: Fixture.date(2026, 9, 24, 10), defaults: defaults()) { asked += 1 }
        await model.connectAppleHealth()
        #expect(asked == 1)
        #expect(model.snapshot?.dataState == .empty)
    }
}
