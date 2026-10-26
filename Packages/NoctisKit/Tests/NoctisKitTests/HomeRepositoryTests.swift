import Foundation
import Testing

@testable import HealthProviding
@testable import HomeFeature
@testable import InsightsKit
@testable import NoctisCore
@testable import RecoveryKit
@testable import SleepAnalysisKit
@testable import SleepKit

/// Home's snapshot for every mock scenario, built end to end: mock
/// provider → HomeRepository → engines. The clock and zone are fixed:
/// 10:00 AM on Thursday, Sep 24, 2026, New York.
struct HomeRepositoryTests {
    private let now = Fixture.date(2026, 9, 24, 10)
    private let lastNightKey = SleepNightKey(year: 2026, month: 9, day: 23)

    private func mock(_ scenario: MockScenario = .full, authorized: Bool = true, available: Bool = true, fails: Bool = false) -> MockHealthKitProvider {
        MockHealthKitProvider(
            scenario: scenario,
            referenceDate: now,
            calendar: Fixture.calendar(),
            startAuthorized: authorized,
            isHealthDataAvailable: available,
            failsQueries: fails
        )
    }

    private func snapshot(_ provider: some HealthDataProviding) async -> HomeSnapshot {
        let clock = now
        let repository = HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { clock })
        return await repository.refresh(profile: UserProfileSnapshot())
    }

    private func scored(_ snapshot: HomeSnapshot) -> RecoveryResult? {
        if case .scored(let result)? = snapshot.recovery { return result }
        return nil
    }

    // MARK: - Sleep quality on the Last night card

    @Test func lastNightCarriesTheSleepTabsQualityWhenThereIsAScore() async throws {
        let snapshot = await snapshot(mock(.full))
        let sleep = await SleepRepository(provider: mock(.full), timeZone: Fixture.newYork, clock: { now }).refresh(profile: UserProfileSnapshot())
        let record = try #require(sleep.record(lastNightKey))
        #expect(snapshot.lastNightSleepQuality == record.quality.score, "Home and Sleep say the same number")
        let screen = HomeScreenBuilder.build(snapshot, now: now, calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"))
        let card = try #require(screen.lastNight)
        #expect(card.sleepQuality?.plain == "\(record.quality.score)")
        #expect(card.accessibilityLabel.contains("Sleep quality \(record.quality.score)."))
    }

    @Test func noQualityWhileLearningOrWithoutANight() async throws {
        let learning = await snapshot(mock(.learning))
        #expect(learning.dataState.isLearning)
        #expect(learning.lastNightSleepQuality == nil)
        let card = HomeScreenBuilder.build(learning, now: now, calendar: Fixture.calendar(), locale: Locale(identifier: "en_US")).lastNight
        #expect(card == nil || card?.sleepQuality == nil)
        let none = await snapshot(mock(.empty))
        #expect(none.lastNightSleepQuality == nil)
    }

    @Test func aNightWithNothingToScoreHasNoQuality() {
        let unscored = SleepQualityResult(
            night: lastNightKey, score: 0, factors: [], confidence: .low, baselineNights: 0,
            modelVersion: "sleep-quality-v1", missingFactors: [:], stageBalance: nil, topContributor: nil
        )
        #expect(!unscored.isScored)
    }

    // MARK: - Scenarios

    @Test func fullScenarioIsReadyWithAHighConfidenceScore() async throws {
        let snapshot = await snapshot(mock(.full))
        #expect(snapshot.dataState == .ready)
        let result = try #require(scored(snapshot))
        #expect(result.factorsUsed == [.sleepDuration, .sleepConsistency, .hrv, .restingHeartRate])
        #expect(result.baselineNights == 14)
        #expect(result.confidence == .high)
        #expect((0...100).contains(result.score))
        // The mock's last night: about 55 minutes later to bed.
        let bedtimeShift = try #require(result.factor(.sleepConsistency)?.delta)
        #expect(abs(bedtimeShift - 55) < 1)
    }

    @Test func fullScenarioSummarizesLastNightFromBothSources() async throws {
        let snapshot = await snapshot(mock(.full))
        let lastNight = try #require(snapshot.lastNight)
        #expect(lastNight.night == lastNightKey)
        #expect(lastNight.completeness.hasStageDetail)
        #expect(lastNight.completeness.hasInBedData)
        #expect(lastNight.totals.inBed > lastNight.totals.asleep)
        #expect(lastNight.efficiency != nil)
        #expect(lastNight.sourceName == MockNightGenerator.watchSource)
    }

    @Test func fullScenarioListsTheLastSevenNights() async {
        let snapshot = await snapshot(mock(.full))
        #expect(snapshot.recentNights.count == 7)
        #expect(snapshot.recentNights.first?.night == lastNightKey.adding(days: -6))
        #expect(snapshot.recentNights.last?.night == lastNightKey)
        #expect(snapshot.recentNights.allSatisfy { $0.asleepMinutes != nil })
        #expect(snapshot.recentNights.last?.asleepMinutes == snapshot.lastNight.map { $0.totals.asleep / 60 })
    }

    @Test func fullScenarioFiresTheShorterNightInsight() async throws {
        let insight = try #require(await snapshot(mock(.full)).topInsight)
        // Duration, bedtime, balance and stage insights all fire; 70 minutes short outranks 55 late.
        #expect(insight.type == .sleepDurationShift)
        guard case .baseline(let evidence) = insight.evidence else {
            Issue.record("expected a baseline insight")
            return
        }
        #expect(abs(evidence.delta + 70) < 1)
    }

    @Test func theLateBedtimeScenarioFiresABedtimeShift() async throws {
        let insight = try #require(await snapshot(mock(.lateBedtime)).topInsight)
        #expect(insight.type == .bedtimeShift)
        guard case .baseline(let evidence) = insight.evidence else {
            Issue.record("expected a baseline insight")
            return
        }
        #expect(abs(evidence.delta - 55) < 1)
    }

    @Test func theSteadyScenarioFiresAStreak() async throws {
        let insight = try #require(await snapshot(mock(.steady)).topInsight)
        #expect(insight.type == .consistentBedtime)
        guard case .baseline(let evidence) = insight.evidence else {
            Issue.record("expected a baseline insight")
            return
        }
        #expect((evidence.streakNights ?? 0) >= InsightEngine.minimumStreakNights)
    }

    @Test func lastNightsHeartRateComesWithTheSnapshot() async throws {
        let heart = try #require(await snapshot(mock(.full)).lastNightHeart)
        #expect(heart.points.count > 10)
        #expect(heart.points.count <= NightHeartSeries.maxPoints)
        #expect(heart.points.allSatisfy { (0...1).contains($0.position) })
        #expect(await snapshot(mock(.sleepOnly)).lastNightHeart == nil)
    }

    @Test func tonightsBedtimeComesFromTheProfile() async {
        var profile = UserProfileSnapshot()
        profile.typicalWakeMinutes = 6 * 60 + 30
        profile.needMinutes = 8 * 60 + 15
        let clock = now
        let repository = HomeRepository(provider: mock(.empty), timeZone: Fixture.newYork, clock: { clock })
        let snapshot = await repository.refresh(profile: profile)
        #expect(snapshot.tonight.bedtimeMinutes == 22 * 60 + 15)
        #expect(snapshot.tonight.wakeMinutes == 6 * 60 + 30)
        #expect(snapshot.tonight.needMinutes == 8 * 60 + 15)
        #expect(snapshot.lastUpdated == now)
    }

    @Test func sleepOnlyScenarioScoresOnSleepAlone() async throws {
        let snapshot = await snapshot(mock(.sleepOnly))
        #expect(snapshot.dataState == .ready)
        let result = try #require(scored(snapshot))
        #expect(result.factorsUsed == [.sleepDuration, .sleepConsistency])
        #expect(result.confidence == .low)
    }

    @Test func learningScenarioCountsItsThreeNights() async {
        let snapshot = await snapshot(mock(.learning))
        #expect(snapshot.dataState == .learning(nightsSoFar: 3))
        #expect(snapshot.recovery == .learning(nightsSoFar: 3))
        #expect(snapshot.topInsight == nil)
        #expect(snapshot.recentNights.map { $0.asleepMinutes != nil } == [false, false, false, false, true, true, true])
    }

    @Test func emptyScenarioStatesThatThereIsNoData() async {
        let snapshot = await snapshot(mock(.empty))
        #expect(snapshot.dataState == .empty)
        #expect(snapshot.recovery == nil)
        #expect(snapshot.lastNight == nil)
        #expect(snapshot.topInsight == nil)
        #expect(snapshot.recentNights.count == 7)
        #expect(snapshot.recentNights.last?.night == lastNightKey)
        #expect(snapshot.recentNights.allSatisfy { $0.asleepMinutes == nil })
    }

    @Test func staleScenarioIsStaleWithNoScore() async throws {
        let snapshot = await snapshot(mock(.stale))
        guard case .stale(let newest) = snapshot.dataState else {
            Issue.record("expected stale, got \(snapshot.dataState)")
            return
        }
        let age = now.timeIntervalSince(newest)
        #expect(age >= 30 * 3600 && age < 31 * 3600)
        #expect(snapshot.recovery == .noSleepLastNight)
        #expect(snapshot.lastNight == nil)
    }

    @Test func gapScenarioHasFreshDataButNoSleepLastNight() async {
        let snapshot = await snapshot(mock(.gap))
        #expect(snapshot.dataState == .noSleepLastNight)
        #expect(snapshot.recovery == .noSleepLastNight)
        #expect(snapshot.lastNight == nil)
        #expect(snapshot.topInsight == nil)
        #expect(snapshot.recentNights.last == NightDuration(night: lastNightKey, asleepMinutes: nil))
        #expect(snapshot.recentNights.dropLast().allSatisfy { $0.asleepMinutes != nil })
    }

    @Test func withoutPermissionHomeAsksForIt() async {
        let snapshot = await snapshot(mock(authorized: false))
        #expect(snapshot.dataState == .permissionRequired)
        #expect(snapshot.recovery == nil)
    }

    @Test func withoutHealthDataHomeSaysSo() async {
        #expect(await snapshot(mock(available: false)).dataState == .healthDataUnavailable)
    }

    @Test func aFailedQueryIsStated() async {
        #expect(await snapshot(mock(fails: true)).dataState == .failed)
    }

    @Test func withoutALastNightTheWeekEndsOnTheNightThatShouldHaveEnded() {
        let key = { (date: Date) in HomeSnapshotBuilder.expectedLastNight(now: date, timeZone: Fixture.newYork, wakeMinutes: 7 * 60) }
        let sep22 = SleepNightKey(year: 2026, month: 9, day: 22)
        // 6:00 AM: the Sep 23 night is still under way.
        #expect(key(Fixture.date(2026, 9, 24, 6)) == sep22)
        // From the 7:00 AM planned wake-up on, it's last night.
        #expect(key(Fixture.date(2026, 9, 24, 7)) == lastNightKey)
        #expect(key(Fixture.date(2026, 9, 24, 13)) == lastNightKey)
        #expect(key(Fixture.date(2026, 9, 24, 23, 30)) == lastNightKey)
        #expect(key(Fixture.date(2026, 9, 25, 1)) == lastNightKey)
    }

    // MARK: - Caching

    @Test func refreshCachesTheSnapshot() async {
        let clock = now
        let repository = HomeRepository(provider: mock(.full), timeZone: Fixture.newYork, clock: { clock })
        #expect(await repository.cachedSnapshot == nil)
        let snapshot = await repository.refresh(profile: UserProfileSnapshot())
        #expect(await repository.cachedSnapshot == snapshot)
    }

    @Test func concurrentRefreshesShareOneLoad() async {
        let provider = ControlledHealthProvider(delay: .milliseconds(200))
        let clock = now
        let repository = HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { clock })
        async let first = repository.refresh(profile: UserProfileSnapshot())
        async let second = repository.refresh(profile: UserProfileSnapshot())
        let (a, b) = await (first, second)
        #expect(a == b)
        #expect(provider.sleepFetches == 1)
    }
}

// MARK: - View model refresh triggers

struct HomeViewModelTests {
    private func makeViewModel(_ provider: ControlledHealthProvider) -> HomeViewModel {
        let clock = Fixture.morningAfter
        let repository = HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { clock })
        return HomeViewModel(repository: repository, profile: { UserProfileSnapshot() })
    }

    @Test func appearingBuildsTheSnapshot() async {
        let provider = ControlledHealthProvider()
        let viewModel = makeViewModel(provider)
        #expect(viewModel.snapshot == nil)
        await viewModel.onAppear()
        #expect(viewModel.snapshot?.dataState == .learning(nightsSoFar: 1))
        #expect(provider.sleepFetches == 1)
        viewModel.stopObserving()
    }

    @Test func pullToRefreshRebuilds() async {
        let provider = ControlledHealthProvider()
        let viewModel = makeViewModel(provider)
        await viewModel.onAppear()
        await viewModel.refresh()
        #expect(provider.sleepFetches == 2)
        #expect(!viewModel.isRefreshing)
        viewModel.stopObserving()
    }

    @Test func aHealthChangeRebuilds() async throws {
        let provider = ControlledHealthProvider()
        let viewModel = makeViewModel(provider)
        await viewModel.onAppear()
        #expect(provider.sleepFetches == 1)
        provider.emitChange()
        _ = await waitFor { !(provider.sleepFetches < 2) }
        #expect(provider.sleepFetches == 2)
        viewModel.stopObserving()
    }

    @Test func appearingAgainDoesNotObserveTwice() async throws {
        let provider = ControlledHealthProvider()
        let viewModel = makeViewModel(provider)
        await viewModel.onAppear()
        await viewModel.onAppear()
        #expect(provider.changeSubscriptions == 1)
        viewModel.stopObserving()
    }
}

/// A provider whose data is one plain night (Sep 23, 11 PM–7 AM) and
/// whose Health changes the test fires by hand.
final class ControlledHealthProvider: HealthDataProviding {
    let isHealthDataAvailable = true
    let sourceName = "Test"
    private(set) var sleepFetches = 0
    private(set) var changeSubscriptions = 0
    private let delay: Duration
    private let changes = AsyncStream<Void>.makeStream()

    init(delay: Duration = .zero) {
        self.delay = delay
    }

    func emitChange() {
        changes.continuation.yield()
    }

    func authorizationStatus() async -> HealthAuthorizationStatus { .authorized }
    func requestAuthorization(for kinds: [HealthDataKind]) async -> HealthAuthorizationStatus { .authorized }

    func fetchSleepSamples(from start: Date, to end: Date) async throws -> [RawSleepSample] {
        sleepFetches += 1
        if delay > .zero { try await Task.sleep(for: delay) }
        return Fixture.plainNight(september: 23)
    }

    func fetchHeartRateSamples(from start: Date, to end: Date) async throws -> [HeartRateSample] { [] }
    func fetchRestingHeartRate(from start: Date, to end: Date) async throws -> [HeartRateSample] { [] }
    func fetchHRVSamples(from start: Date, to end: Date) async throws -> [HRVSample] { [] }
    func fetchRespiratorySamples(from start: Date, to end: Date) async throws -> [RespiratoryRateSample] { [] }

    func sampleChanges() -> AsyncStream<Void> {
        changeSubscriptions += 1
        return changes.stream
    }
}
