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

// MARK: - Home's Insight block and the shared store

/// Home shows the insight the Insights tab features: one `InsightStore`, so
/// the two never disagree. Fatigue itself is `InsightV2FatigueTests`'.
struct InsightFatigueTests {
    private let now = Fixture.date(2026, 9, 24, 10)

    private func provider(_ scenario: MockScenario = .full) -> MockHealthKitProvider {
        MockHealthKitProvider(scenario: scenario, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
    }

    private func pair(_ scenario: MockScenario = .full) -> (home: HomeRepository, insights: InsightsRepository) {
        let clock = now
        let insights = InsightsRepository(provider: provider(scenario), timeZone: Fixture.newYork, clock: { clock })
        return (HomeRepository(provider: provider(scenario), timeZone: Fixture.newYork, clock: { clock }, insights: insights), insights)
    }

    @Test func homeAndTheTabFeatureTheSameInsight() async throws {
        let repositories = pair()
        let home = try #require(await repositories.home.refresh(profile: UserProfileSnapshot()).topInsight)
        let tab = try #require(await repositories.insights.refresh(profile: UserProfileSnapshot()).featured)
        #expect(home.id == tab.id)
        #expect(home == tab)
        // And the other way round: the tab first.
        let other = pair()
        let first = try #require(await other.insights.refresh(profile: UserProfileSnapshot()).featured)
        #expect(try #require(await other.home.refresh(profile: UserProfileSnapshot()).topInsight).id == first.id)
    }

    @Test func homeAndTheTabAgreeForEveryScenario() async throws {
        for scenario in MockScenario.allCases {
            let repositories = pair(scenario)
            let home = await repositories.home.refresh(profile: UserProfileSnapshot()).topInsight
            let tab = await repositories.insights.refresh(profile: UserProfileSnapshot()).featured
            #expect(home?.id == tab?.id, "\(scenario.rawValue)")
        }
    }

    @Test func dismissingOnHomeLeavesTheTabWithoutItToo() async throws {
        let repositories = pair()
        let featured = try #require(await repositories.home.refresh(profile: UserProfileSnapshot()).topInsight)
        let dropped = await repositories.home.dismiss(id: featured.id)
        #expect(dropped?.topInsight == nil)
        let tab = await repositories.insights.refresh(profile: UserProfileSnapshot())
        #expect(tab.featured == nil, "nothing stands in for it that night")
        #expect(tab.all.first { $0.id == featured.id }?.state == .dismissed, "History keeps it, muted")
        #expect(await repositories.home.refresh(profile: UserProfileSnapshot()).topInsight == nil)
    }

    @Test func hidingThroughTheRepositorySticks() async throws {
        let repositories = pair()
        let first = try #require(await repositories.home.refresh(profile: UserProfileSnapshot()).topInsight)
        let hidden = await repositories.home.hide(first.type)
        #expect(hidden?.topInsight == nil)
        let after = await repositories.home.refresh(profile: UserProfileSnapshot())
        #expect(after.topInsight?.type != first.type)
        let tab = await repositories.insights.refresh(profile: UserProfileSnapshot())
        #expect(!tab.all.contains { $0.record.type == first.type }, "hidden everywhere")
    }

    @Test func theBlockCarriesTheIdItOpens() async throws {
        let repositories = pair()
        let snapshot = await repositories.home.refresh(profile: UserProfileSnapshot())
        let record = try #require(snapshot.topInsight)
        let card = try #require(HomeScreenBuilder.build(snapshot, now: now, calendar: Fixture.calendar(), locale: Locale(identifier: "en_US")).insight)
        #expect(card.id == record.id)
        #expect(!card.title.isEmpty)
    }

    @Test func aRuleBeyondTheFirstThreeShowsItsTwoNumbers() throws {
        let format = HomeFormat(calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"))
        let card = HomeScreenBuilder.insightCard(InsightRecordFixture.pattern(), format: format)
        #expect(card.id == InsightRecordFixture.pattern().id)
        #expect(card.title == "Earlier bedtimes, higher sleep scores")
        guard case .figures(let numbers, let join) = card.chart else {
            Issue.record("expected figures")
            return
        }
        #expect(numbers.map(\.value.plain) == ["92pts", "66pts"])
        #expect(join == .versus)
        #expect(!card.accessibilityLabel.isEmpty)
    }

    @Test func aBaselineRuleKeepsItsSmallChart() throws {
        let format = HomeFormat(calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"))
        let duration = HomeScreenBuilder.insightCard(InsightRecordFixture.duration(delta: -70), format: format)
        guard case .comparison = duration.chart else {
            Issue.record("expected the two bars")
            return
        }
        #expect(duration.title == "Shorter night than usual")
        // The streak's page draws two weeks; the card draws one.
        let streak = HomeScreenBuilder.insightCard(InsightRecordFixture.streak(nights: 6), format: format)
        guard case .nights(let dots, let caption) = streak.chart else {
            Issue.record("expected dots")
            return
        }
        #expect(dots.count == 7 && caption == "Last 7 nights")
    }

    @Test func dismissingThroughTheViewModelCollapsesAtOnce() async throws {
        let now = Fixture.date(2026, 9, 24, 10)
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let repository = HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { now })
        let model = HomeViewModel(
            repository: repository, profile: { UserProfileSnapshot() }, clock: { now },
            calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"))
        await model.refresh()
        #expect(model.screen?.insight != nil)
        model.dismissInsight()
        #expect(model.screen?.insight == nil)
        // The write goes through the repository actor: a rebuild after it keeps the insight away.
        #expect(
            await waitFor {
                await model.refresh()
                return model.screen?.insight == nil
            })
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
            let snapshot = HomeSnapshotBuilder.build(
                HomeHealthInputs(sleep: samples, hrv: [], restingHeartRate: [], heartRate: []),
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
        #expect(
            texts == [
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
        let snapshot = HomeSnapshotBuilder.build(
            HomeHealthInputs(sleep: samples, hrv: [], restingHeartRate: [], heartRate: []),
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
        let snapshot = HomeSnapshotBuilder.build(
            HomeHealthInputs(sleep: samples, hrv: [], restingHeartRate: [], heartRate: []),
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
        let model = HomeViewModel(
            repository: HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { clock }),
            profile: { UserProfileSnapshot() }, clock: { clock })
        await model.onAppear()
        #expect(!model.showsNewNight)
        provider.nightArrives()
        _ = await waitFor { !(!model.showsNewNight) }
        #expect(model.showsNewNight)
        #expect(model.snapshot?.lastNight != nil)
        model.stopObserving()
    }

    @Test func aChangeWithoutANewNightStaysQuiet() async throws {
        let provider = ControlledHealthProvider()
        let clock = Fixture.morningAfter
        let model = HomeViewModel(
            repository: HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { clock }),
            profile: { UserProfileSnapshot() }, clock: { clock })
        await model.onAppear()
        provider.emitChange()
        _ = await waitFor { !(provider.sleepFetches < 2) }
        // The rebuild the change started has finished: and it found no new night.
        _ = await waitFor { !model.isRefreshing }
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
