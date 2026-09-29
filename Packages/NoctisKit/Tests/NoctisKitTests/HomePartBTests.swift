import Foundation
import SwiftUI
import Testing
@testable import HealthProviding
@testable import HomeFeature
@testable import InsightsKit
@testable import NoctisCore
@testable import RecoveryKit
@testable import SleepKit

/// Clock times use a narrow no-break space before AM/PM.
private func plain(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
}

// MARK: - Scroll collapse

/// The hero shrinks 1.0 → 0.85 and fades as it scrolls away; the compact
/// bar shows from 70% scrolled past and hides again below 65%.
struct HomeCollapseTests {
    private let heroTop = 150.0
    private let heroHeight = 500.0

    private func state(_ visibleTop: Double, after previous: HomeCollapse = .expanded) -> HomeCollapse {
        HomeCollapse.state(visibleTop: visibleTop, heroTop: heroTop, heroHeight: heroHeight, previous: previous)
    }

    @Test func atRestTheHeroIsWhole() {
        let rest = state(0)
        #expect(rest == .expanded)
        #expect(rest.heroScale == 1)
        #expect(rest.heroOpacity == 1)
        // Scrolling until the hero's top meets the top edge changes nothing.
        #expect(state(heroTop) == .expanded)
    }

    @Test func halfwayTheHeroIsSmallerAndFainter() {
        let half = state(heroTop + heroHeight / 2)
        #expect(half.progress == 0.5)
        #expect(abs(half.heroScale - 0.925) < 1e-9)
        #expect(half.heroOpacity == 0.5)
        #expect(!half.showsBar)
    }

    @Test func fullyScrolledAwayItStopsAtPoint85() {
        let gone = state(5000)
        #expect(gone.progress == 1)
        #expect(abs(gone.heroScale - HomeCollapse.minimumScale) < 1e-9)
        #expect(gone.heroOpacity == 0)
        #expect(gone.showsBar)
    }

    @Test func theBarShowsAtSeventyPercent() {
        #expect(!state(heroTop + heroHeight * 0.69).showsBar)
        #expect(state(heroTop + heroHeight * 0.70).showsBar)
    }

    @Test func theBarHidesOnlyBelowSixtyFivePercent() {
        let shown = state(heroTop + heroHeight * 0.8)
        #expect(shown.showsBar)
        #expect(state(heroTop + heroHeight * 0.66, after: shown).showsBar)
        #expect(state(heroTop + heroHeight * 0.65, after: shown).showsBar)
        #expect(!state(heroTop + heroHeight * 0.64, after: shown).showsBar)
        // Coming back up from below the line, it takes 70% again.
        #expect(!state(heroTop + heroHeight * 0.68, after: .expanded).showsBar)
    }

    @Test func progressMovesInWholePercents() {
        #expect(state(heroTop + 1.2).progress == 0)
        #expect(state(heroTop + 2.6).progress == 0.01)
    }

    @Test func anUnmeasuredHeroNeverCollapses() {
        #expect(HomeCollapse.state(visibleTop: 900, heroTop: 0, heroHeight: 0, previous: .expanded) == .expanded)
    }

    @Test func theViewModelTracksTheCollapse() {
        let model = HomeViewModel(repository: HomeRepository(provider: ControlledHealthProvider()), profile: { UserProfileSnapshot() })
        model.scrolled(visibleTop: heroTop + heroHeight * 0.75, heroTop: heroTop, heroHeight: heroHeight)
        #expect(model.collapse.showsBar)
        #expect(model.collapse.progress == 0.75)
        model.scrolled(visibleTop: 0, heroTop: heroTop, heroHeight: heroHeight)
        #expect(model.collapse == .expanded)
    }
}

// MARK: - Insight fatigue

/// Hidden kinds never show, the same kind never shows two nights in a
/// row, and a dismissed night shows nothing more.
struct InsightFatigueTests {
    private let tonight = SleepNightKey(year: 2026, month: 9, day: 23)

    private func insight(_ kind: InsightKind, night: SleepNightKey? = nil) -> Insight {
        Insight(kind: kind, evidence: InsightEvidence(night: night ?? tonight, value: 0, baseline: 0, delta: 0, baselineNights: 14))
    }

    private var candidates: [Insight] {
        [insight(.sleepDurationShift), insight(.bedtimeShift), insight(.consistentBedtime)]
    }

    @Test func withNoHistoryTheBestCandidateShows() {
        #expect(InsightHistory().pick(from: candidates)?.kind == .sleepDurationShift)
        #expect(InsightHistory().pick(from: []) == nil)
    }

    @Test func aHiddenKindNeverShows() {
        var history = InsightHistory()
        history.hide(.sleepDurationShift)
        #expect(history.pick(from: candidates)?.kind == .bedtimeShift)
        history.hide(.bedtimeShift)
        history.hide(.consistentBedtime)
        #expect(history.pick(from: candidates) == nil)
    }

    @Test func theSameInsightNeverShowsTwoNightsInARow() {
        var history = InsightHistory()
        history.recordShown(insight(.sleepDurationShift, night: tonight.adding(days: -1)))
        #expect(history.pick(from: candidates)?.kind == .bedtimeShift)
        // Only one candidate, and it showed yesterday: nothing today.
        #expect(history.pick(from: [insight(.sleepDurationShift)]) == nil)
    }

    @Test func theSameNightKeepsItsInsight() {
        var history = InsightHistory()
        history.recordShown(insight(.sleepDurationShift))
        #expect(history.pick(from: candidates)?.kind == .sleepDurationShift)
    }

    @Test func twoNightsLaterItMayShowAgain() {
        var history = InsightHistory()
        history.recordShown(insight(.sleepDurationShift, night: tonight.adding(days: -2)))
        #expect(history.pick(from: candidates)?.kind == .sleepDurationShift)
    }

    @Test func aDismissedNightShowsNothingMore() {
        var history = InsightHistory()
        history.recordDismissal(insight(.sleepDurationShift))
        #expect(history.pick(from: candidates) == nil)
        // The next night starts fresh.
        let tomorrow = tonight.adding(days: 1)
        #expect(history.pick(from: [insight(.bedtimeShift, night: tomorrow)])?.kind == .bedtimeShift)
    }

    @Test func dismissalsKeepOnlyTheRecentOnes() {
        var history = InsightHistory()
        for day in 0..<40 {
            history.recordDismissal(insight(.bedtimeShift, night: tonight.adding(days: -day)))
        }
        #expect(history.dismissals.count == InsightHistory.maxDismissals)
    }

    @Test func theEngineSkipsHiddenKinds() {
        // 45 minutes short and 55 minutes late: both shifts fire, the later
        // bedtime ranks first.
        let history = Fixture.metrics(count: 15) { index in
            (asleep: index == 14 ? 375 : 420, bedtime: index == 14 ? 715 : 660, wake: 1140, hrv: nil, resting: nil)
        }
        let ranked = InsightEngine.candidates(history: history, asOf: Fixture.morningAfter)
        #expect(ranked.map(\.kind) == [.bedtimeShift, .sleepDurationShift])
        var fatigue = InsightHistory()
        fatigue.hide(.bedtimeShift)
        #expect(InsightEngine.topInsight(history: history, asOf: Fixture.morningAfter, fatigue: fatigue)?.kind == .sleepDurationShift)
    }

    @Test func theStoreKeepsHistoryAcrossLaunches() throws {
        let suite = "noctis.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = InsightHistoryStore(defaults: defaults)
        store.update {
            $0.recordShown(insight(.bedtimeShift))
            $0.hide(.consistentBedtime)
        }
        let reopened = InsightHistoryStore(defaults: defaults)
        #expect(reopened.history == store.history)
        #expect(reopened.history.hiddenKinds == [.consistentBedtime])
        #expect(reopened.history.lastShown?.kind == .bedtimeShift)
        // In memory only, nothing is written.
        #expect(InsightHistoryStore().history == InsightHistory())
    }

    @Test func hidingThroughTheRepositorySticks() async throws {
        let now = Fixture.date(2026, 9, 24, 10)
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let store = InsightHistoryStore()
        let repository = HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { now }, insightHistory: store)
        let first = try #require(await repository.refresh(profile: UserProfileSnapshot()).topInsight)
        #expect(store.history.lastShown?.kind == first.kind)

        let hidden = await repository.hide(first)
        #expect(hidden?.topInsight == nil)
        #expect(store.history.hiddenKinds == [first.kind])
        let after = await repository.refresh(profile: UserProfileSnapshot())
        #expect(after.topInsight?.kind != first.kind)
    }

    @Test func dismissingThroughTheViewModelCollapsesAtOnce() async throws {
        let now = Fixture.date(2026, 9, 24, 10)
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let repository = HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { now })
        let model = HomeViewModel(repository: repository, profile: { UserProfileSnapshot() }, clock: { now },
                                  calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"))
        await model.refresh()
        #expect(model.screen?.insight != nil)
        model.dismissInsight()
        #expect(model.screen?.insight == nil)
        try await Task.sleep(for: .milliseconds(50))
        await model.refresh()
        #expect(model.screen?.insight == nil)
    }
}

// MARK: - Night panel scrub

/// Last night: awake 11:02–11:05 PM, core to 1:00, deep to 2:00, REM to
/// 3:00, core to 7:27 AM.
struct NightScrubTests {
    private let now = Fixture.date(2026, 9, 24, 10)

    private var chart: NightChartContent {
        get throws {
            let samples = [
                Fixture.sample(Fixture.date(2026, 9, 23, 23, 2), Fixture.date(2026, 9, 23, 23, 5), .awake),
                Fixture.sample(Fixture.date(2026, 9, 23, 23, 5), Fixture.date(2026, 9, 24, 1), .core),
                Fixture.sample(Fixture.date(2026, 9, 24, 1), Fixture.date(2026, 9, 24, 2), .deep),
                Fixture.sample(Fixture.date(2026, 9, 24, 2), Fixture.date(2026, 9, 24, 3), .rem),
                Fixture.sample(Fixture.date(2026, 9, 24, 3), Fixture.date(2026, 9, 24, 7, 27), .core),
            ]
            let snapshot = HomeSnapshotBuilder.build(HomeHealthInputs(sleep: samples, hrv: [], restingHeartRate: [], heartRate: []),
                                                     profile: UserProfileSnapshot(), now: now, timeZone: Fixture.newYork)
            let screen = HomeScreenBuilder.build(snapshot, now: now, calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"))
            return try #require(screen.lastNight?.chart)
        }
    }

    @Test func thePillSaysTheTimeTheStageAndItsLength() throws {
        let chart = try chart
        #expect(chart.reading(at: 0).map { plain($0.text) } == "11:02 PM · Awake · 3 min")
        // 252.5 minutes in, inside the last Core segment (3:00–7:27 AM).
        let middle = try #require(chart.reading(at: 0.5))
        #expect(plain(middle.text) == "3:14 AM · Core · 4h 27m")
        #expect(middle.lane == .core)
        #expect(middle.segment == 4)
        #expect(middle.position == 0.5)
    }

    @Test func theEndsClampToTheChart() throws {
        let chart = try chart
        #expect(chart.reading(at: -0.3).map { plain($0.text) } == "11:02 PM · Awake · 3 min")
        #expect(chart.reading(at: 1).map { plain($0.text) } == "7:27 AM · Core · 4h 27m")
        #expect(chart.reading(at: 1.4)?.position == 1)
    }

    @Test func steppingReadsEachSegmentFromItsStart() throws {
        let chart = try chart
        let texts = chart.spans.indices.compactMap { chart.reading(segment: $0).map { plain($0.text) } }
        #expect(texts == [
            "11:02 PM · Awake · 3 min",
            "11:05 PM · Core · 1h 55m",
            "1:00 AM · Deep · 1h",
            "2:00 AM · REM · 1h",
            "3:00 AM · Core · 4h 27m",
        ])
        #expect(chart.reading(segment: 5) == nil)
    }

    @Test func laneLabelsShowTheirTotals() throws {
        #expect(try chart.laneTotals.map(\.text) == ["Awake · 3 min", "REM · 1h", "Core · 6h 22m", "Deep · 1h"])
    }

    @Test func theAudioGraphAxisReadsClockTimes() throws {
        let chart = try chart
        #expect(chart.minutes == 505)
        #expect(plain(chart.clockText(at: 0)) == "11:02 PM")
        #expect(plain(chart.clockText(at: 1)) == "7:27 AM")
    }

    @Test func withoutStagesThereIsNothingToScrub() {
        let samples = [Fixture.sample(Fixture.date(2026, 9, 23, 23), Fixture.date(2026, 9, 24, 7), .unspecified)]
        let snapshot = HomeSnapshotBuilder.build(HomeHealthInputs(sleep: samples, hrv: [], restingHeartRate: [], heartRate: []),
                                                 profile: UserProfileSnapshot(), now: now, timeZone: Fixture.newYork)
        let chart = HomeScreenBuilder.build(snapshot, now: now, calendar: Fixture.calendar(), locale: Locale(identifier: "en_US")).lastNight?.chart
        #expect(chart?.reading(at: 0.5) == nil)
        #expect(chart?.laneTotals.isEmpty == true)
    }
}

// MARK: - This week, share, the evening status

struct HomeWeekAndShareTests {
    private let now = Fixture.date(2026, 9, 24, 10)
    private let locale = Locale(identifier: "en_US")

    private func screen(_ scenario: MockScenario) async -> (HomeSnapshot, HomeScreen) {
        let provider = MockHealthKitProvider(scenario: scenario, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let clock = now
        let snapshot = await HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { clock }).refresh(profile: UserProfileSnapshot())
        return (snapshot, HomeScreenBuilder.build(snapshot, now: now, calendar: Fixture.calendar(), locale: locale))
    }

    @Test func aSelectedBarNamesTheDayTheSleepAndItsDeepAndREM() async throws {
        let (snapshot, screen) = await screen(.full)
        let week = try #require(screen.week)
        let last = try #require(week.bars.last)
        let lastNight = try #require(snapshot.recentNights.last)
        let stages = try #require(lastNight.stages)
        let slept = HomeFormat.compactDuration(Int(try #require(lastNight.asleepMinutes).rounded()))
        let deep = HomeFormat.compactDuration(Int(stages.deep.rounded()))
        let rem = HomeFormat.compactDuration(Int(stages.rem.rounded()))
        #expect(last.detail == "Thu · \(slept) · Deep \(deep) · REM \(rem)")
        // Deep, Core and REM share the bar; awake isn't in it.
        let split = try #require(last.stages)
        #expect(abs(split.deep + split.core + split.rem - 1) < 1e-9)
        #expect(abs(split.deep - stages.deep / (stages.deep + stages.core + stages.rem)) < 1e-9)
    }

    @Test func barsWithoutASleepOrStagesSaySo() {
        // Sep 21: 6h, Sep 22: none, Sep 23: 8h — unstaged nights.
        let samples = Fixture.plainNight(september: 21, hours: 6) + [Fixture.sample(Fixture.date(2026, 9, 23, 23), Fixture.date(2026, 9, 24, 7), .unspecified)]
        let snapshot = HomeSnapshotBuilder.build(HomeHealthInputs(sleep: samples, hrv: [], restingHeartRate: [], heartRate: []),
                                                 profile: UserProfileSnapshot(), now: now, timeZone: Fixture.newYork)
        let bars = HomeScreenBuilder.build(snapshot, now: now, calendar: Fixture.calendar(), locale: locale).week?.bars ?? []
        // A staged night names its Deep and REM even at zero; an unstaged one can't.
        #expect(bars.suffix(3).map(\.detail) == ["Tue · 6h · Deep 0m · REM 0m", "Wed · No data", "Thu · 8h · No stages"])
        // Sep 21's plain core night has stages; last night's unspecified sleep doesn't.
        #expect(bars.last?.stages == nil)
        #expect(bars.last?.accessibilityLabel.hasSuffix("no stage detail") == true)
        #expect(bars[bars.count - 3].stages != nil)
    }

    @Test func nightlyScoresSkipLearningNightsAndNightsWithoutSleep() {
        let history = Fixture.metrics(count: 7) { _ in (asleep: 420, bedtime: 660, wake: 1140, hrv: nil, resting: nil) }
        let keys = history.map(\.night) + [SleepNightKey(year: 2026, month: 9, day: 24)]
        let scores = RecoveryEngine.nightlyScores(history: history, nights: keys, needMinutes: 480, asOf: Fixture.morningAfter)
        // Nights 1–4 were still learning; the fifth on score.
        #expect(Set(scores.keys) == Set(history.suffix(3).map(\.night)))
        guard case .scored(let today) = RecoveryEngine.evaluate(history: history, needMinutes: 480, asOf: Fixture.morningAfter) else {
            Issue.record("should score")
            return
        }
        #expect(scores[history.last!.night] == today.score)
    }

    @Test func theShareCardCarriesDetailsOnlyWhenThereAreAny() async throws {
        let (_, full) = await screen(.full)
        let share = try #require(full.share)
        #expect(share.recovery != nil)
        #expect(share.lastNight?.parts.contains(.unit("h")) == true)
        #expect(share.details?.contains("HRV ") == true)
        #expect(share.details?.contains("Resting HR ") == true)
        #expect(share.fileName == "noctis-2026-09-24")
        #expect(share.title == "NOCTIS · Thursday, September 24")

        let (_, sleepOnly) = await screen(.sleepOnly)
        #expect(sleepOnly.share?.details == nil)
        let (_, empty) = await screen(.empty)
        #expect(empty.share == nil)
    }

    @Test func theShareCardRendersAt1080By1350() async throws {
        let (_, full) = await screen(.full)
        let share = try #require(full.share)
        for scheme in [ColorScheme.light, .dark] {
            let image = try #require(ShareCardRenderer.render(share, includeDetails: false, colorScheme: scheme))
            #expect(image.size.width * image.scale == 1080)
            #expect(image.size.height * image.scale == 1350)
        }
        let plainCard = try #require(ShareCardRenderer.render(share, includeDetails: false, colorScheme: .light)?.pngData())
        let detailed = try #require(ShareCardRenderer.render(share, includeDetails: true, colorScheme: .light)?.pngData())
        #expect(plainCard != detailed)
        if let directory = ProcessInfo.processInfo.environment["NOCTIS_RENDER_OUT"] {
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            for (name, scheme, details) in [("share-light", ColorScheme.light, false), ("share-dark", .dark, false), ("share-details", .light, true)] {
                try? ShareCardRenderer.render(share, includeDetails: details, colorScheme: scheme)?.pngData()?
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
            }
        }
    }

    @Test func theEveningStatusCountsDownThenLooksBack() {
        let format = HomeFormat(calendar: Fixture.calendar(), locale: locale)
        let plan = TonightPlan(profile: UserProfileSnapshot())
        let times = HomeScreenBuilder.tonightTimes(now: Fixture.date(2026, 9, 24, 20, 46), plan: plan, format: format)
        #expect(plain(times.status(at: Fixture.date(2026, 9, 24, 20, 46))) == "Bedtime 11:00 PM · in 2h 14m")
        #expect(plain(times.status(at: Fixture.date(2026, 9, 24, 23, 30))) == "Bedtime was 11:00 PM")
    }
}

// MARK: - Live updates

struct HomeLiveUpdateTests {
    @Test func aNewNightFromHealthShowsTheBanner() async throws {
        let provider = ArrivingNightProvider()
        let clock = Fixture.morningAfter
        let model = HomeViewModel(repository: HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { clock }),
                                  profile: { UserProfileSnapshot() }, clock: { clock })
        await model.onAppear()
        #expect(!model.showsNewNight)
        provider.nightArrives()
        for _ in 0..<100 where !model.showsNewNight {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.showsNewNight)
        #expect(model.snapshot?.lastNight != nil)
        model.stopObserving()
    }

    @Test func aChangeWithoutANewNightStaysQuiet() async throws {
        let provider = ControlledHealthProvider()
        let clock = Fixture.morningAfter
        let model = HomeViewModel(repository: HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { clock }),
                                  profile: { UserProfileSnapshot() }, clock: { clock })
        await model.onAppear()
        provider.emitChange()
        for _ in 0..<100 where provider.sleepFetches < 2 {
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(!model.showsNewNight)
        model.stopObserving()
    }
}

/// Sep 22's night at first; Sep 23's arrives when the test says so, with
/// a Health change.
final class ArrivingNightProvider: HealthDataProviding {
    let isHealthDataAvailable = true
    let sourceName = "Test"
    private var arrived = false
    private let changes = AsyncStream<Void>.makeStream()

    func nightArrives() {
        arrived = true
        changes.continuation.yield()
    }

    func authorizationStatus() async -> HealthAuthorizationStatus { .authorized }
    func requestAuthorization(for kinds: [HealthDataKind]) async -> HealthAuthorizationStatus { .authorized }

    func fetchSleepSamples(from start: Date, to end: Date) async throws -> [RawSleepSample] {
        Fixture.plainNight(september: 22) + (arrived ? Fixture.plainNight(september: 23) : [])
    }

    func fetchHeartRateSamples(from start: Date, to end: Date) async throws -> [HeartRateSample] { [] }
    func fetchRestingHeartRate(from start: Date, to end: Date) async throws -> [HeartRateSample] { [] }
    func fetchHRVSamples(from start: Date, to end: Date) async throws -> [HRVSample] { [] }
    func fetchRespiratorySamples(from start: Date, to end: Date) async throws -> [RespiratoryRateSample] { [] }

    func sampleChanges() -> AsyncStream<Void> { changes.stream }
}
