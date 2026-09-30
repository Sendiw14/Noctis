import Foundation
import HealthProviding
import Testing
@testable import HomeFeature
@testable import InsightsKit
@testable import NoctisCore
@testable import SleepKit

/// The mock scenarios through the whole pipeline: provider → inputs →
/// engine → store → snapshot. Clock and zone are fixed: 10:00 AM on
/// Thursday, Sep 24, 2026, New York.
struct InsightScenarioTests {
    private let now = Fixture.date(2026, 9, 24, 10)
    private let last = SleepNightKey(year: 2026, month: 9, day: 23)

    private func mock(_ scenario: MockScenario, authorized: Bool = true, available: Bool = true, fails: Bool = false) -> MockHealthKitProvider {
        MockHealthKitProvider(
            scenario: scenario, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: authorized,
            isHealthDataAvailable: available, failsQueries: fails
        )
    }

    private func records(_ scenario: MockScenario) async throws -> [InsightRecord] {
        let provider = mock(scenario)
        let start = now.addingTimeInterval(-Double(InsightInputsBuilder.historyDays) * 86_400 - 18 * 3600)
        let inputs = InsightInputsBuilder.build(
            sleep: try await provider.fetchSleepSamples(from: start, to: now), hrv: try await provider.fetchHRVSamples(from: start, to: now),
            restingHeartRate: try await provider.fetchRestingHeartRate(from: start, to: now), needMinutes: 480, now: now, timeZone: Fixture.newYork
        )
        return InsightRanking.ranked(InsightEngineV2.generate(inputs), on: last)
    }

    private func repository(_ scenario: MockScenario, store: InsightStore = InsightStore()) -> InsightsRepository {
        let clock = now
        return InsightsRepository(provider: mock(scenario), store: store, timeZone: Fixture.newYork, clock: { clock })
    }

    // MARK: - What each scenario says

    @Test func theFullScenarioFiresAtLeastFiveDifferentInsights() async throws {
        let all = try await records(.full)
        #expect(all.count >= 5)
        #expect(Set(all.map(\.id)).count == all.count, "five different insights")
        #expect(Set(all.map(\.type)) == [.bedtimeShift, .sleepDurationShift, .sleepBalance, .stageShare])
        let stages = all.compactMap { record -> InsightStage? in
            if case .stageShare(let e) = record.evidence { e.stage } else { nil }
        }
        #expect(Set(stages) == [.deep, .rem])
    }

    @Test func earlyBirdFindsTheEarlierBedtimePatternWithHighConfidence() async throws {
        let all = try await records(.earlyBird)
        let pattern = try #require(all.first { $0.type == .earlierBedtimePattern })
        guard case .pattern(let evidence) = pattern.evidence else { Issue.record("expected pattern evidence"); return }
        #expect(pattern.confidence == .high)
        #expect(evidence.earlyNights >= 10 && evidence.lateNights >= 10)
        #expect(evidence.difference > 6)
        #expect(evidence.effectSize >= 0.8)
        #expect(evidence.windowNights == 60)
    }

    @Test func weekendShiftFindsLaterWeekendBedtimes() async throws {
        let all = try await records(.weekendShift)
        let weekend = try #require(all.first { $0.type == .weekendShift })
        guard case .weekend(let evidence) = weekend.evidence else { Issue.record("expected weekend evidence"); return }
        #expect(evidence.delta >= 45)
        #expect(evidence.weekendNights >= 3)
    }

    @Test func hrvDipFindsBothHeartSignals() async throws {
        let types = Set(try await records(.hrvDip).map(\.type))
        #expect(types.isSuperset(of: [.hrvBelowRange, .restingHeartRateAboveRange]))
    }

    @Test func steadyFindsTheBedtimeStreak() async throws {
        let all = try await records(.steady)
        #expect(all.contains { $0.type == .consistentBedtime })
    }

    @Test func sparseAndLearningHaveNothingToSayYet() async throws {
        #expect(try await records(.sparse).isEmpty)
        #expect(try await records(.learning).isEmpty)
        #expect(try await records(.empty).isEmpty)
    }

    @Test func highsFindsTheRecords() async throws {
        let types = Set(try await records(.highs).map(\.type))
        #expect(types.isSuperset(of: [.recordLongestNight, .recordHighestRecovery, .recordLowestRestingHeartRate]))
    }

    @Test func theScenariosAreDeterministic() async throws {
        for scenario in [MockScenario.full, .earlyBird, .weekendShift, .hrvDip, .highs] {
            let first = try await records(scenario)
            let second = try await records(scenario)
            #expect(first == second, "\(scenario.rawValue): same data, same ordered list")
        }
    }

    // MARK: - Through the repository

    @Test func theRepositoryBuildsTheTabsSnapshot() async {
        let snapshot = await repository(.full).refresh(profile: UserProfileSnapshot())
        #expect(snapshot.dataState == .ready)
        #expect(snapshot.night == last)
        #expect(snapshot.featured != nil)
        #expect(snapshot.recent.count >= 4)
        #expect(snapshot.newThisWeek == snapshot.recent.count, "everything is new the first time")
        #expect(snapshot.all.count == snapshot.recent.count)
        #expect(!snapshot.records.isEmpty)
    }

    @Test func theFeaturedInsightIsTheSameOnEveryOpen() async {
        let store = InsightStore()
        let first = await repository(.full, store: store).refresh(profile: UserProfileSnapshot())
        let second = await repository(.full, store: store).refresh(profile: UserProfileSnapshot())
        #expect(first.featured?.id == second.featured?.id)
        #expect(first.featured == second.featured)
        #expect(first.recent.map(\.id) == second.recent.map(\.id))
    }

    @Test func dismissingTheFeaturedInsightLeavesNoneThatNight() async throws {
        let repo = repository(.full)
        let snapshot = await repo.refresh(profile: UserProfileSnapshot())
        let featured = try #require(snapshot.featured)
        let after = try #require(await repo.dismiss(id: featured.id))
        #expect(after.featured == nil)
        #expect(!after.recent.contains { $0.id == featured.id })
        #expect(after.all.first { $0.id == featured.id }?.state == .dismissed, "History keeps it, muted")
        // A refresh agrees.
        #expect(await repo.refresh(profile: UserProfileSnapshot()).featured == nil)
    }

    @Test func hidingATypeRemovesItEverywhere() async throws {
        let repo = repository(.full)
        let snapshot = await repo.refresh(profile: UserProfileSnapshot())
        let type = try #require(snapshot.featured?.type)
        let after = try #require(await repo.hide(type))
        #expect(!after.all.contains { $0.record.type == type })
        #expect(!after.recent.contains { $0.record.type == type })
        #expect(after.featured?.type != type, "the next insight takes its place, if there is one")
        #expect(after.featured != nil, "the full scenario has others")
        #expect(await repo.refresh(profile: UserProfileSnapshot()).all.contains { $0.record.type == type } == false)
    }

    @Test func openingAnInsightStopsItCountingAsNew() async throws {
        let repo = repository(.full)
        let snapshot = await repo.refresh(profile: UserProfileSnapshot())
        let id = try #require(snapshot.recent.first?.id)
        let after = try #require(await repo.markSeen(id: id))
        #expect(after.newThisWeek == snapshot.newThisWeek - 1)
        #expect(after.insight(id: id)?.state == .seen)
    }

    @Test func sparseIsTheLearningState() async {
        let snapshot = await repository(.sparse).refresh(profile: UserProfileSnapshot())
        #expect(snapshot.dataState == .learning(nightsSoFar: 6))
        #expect(snapshot.featured == nil)
        #expect(snapshot.recent.isEmpty)
        #expect(snapshot.nightsRecorded == 6)
    }

    @Test func emptyPermissionUnavailableAndFailedReuseHomesStates() async {
        let empty = await repository(.empty).refresh(profile: UserProfileSnapshot())
        #expect(empty.dataState == .empty)
        let clock = now
        let noPermission = await InsightsRepository(provider: mock(.full, authorized: false), timeZone: Fixture.newYork, clock: { clock }).refresh(profile: UserProfileSnapshot())
        #expect(noPermission.dataState == .permissionRequired)
        let unavailable = await InsightsRepository(provider: mock(.full, available: false), timeZone: Fixture.newYork, clock: { clock }).refresh(profile: UserProfileSnapshot())
        #expect(unavailable.dataState == .healthDataUnavailable)
        let failed = await InsightsRepository(provider: mock(.full, fails: true), timeZone: Fixture.newYork, clock: { clock }).refresh(profile: UserProfileSnapshot())
        #expect(failed.dataState == .failed)
        for snapshot in [empty, noPermission, unavailable, failed] {
            #expect(snapshot.featured == nil && snapshot.recent.isEmpty && snapshot.records.isEmpty)
        }
    }

    @Test func aStaleScenarioHasNoFeaturedStoryButKeepsItsHistory() async {
        let snapshot = await repository(.stale).refresh(profile: UserProfileSnapshot())
        #expect(snapshot.featured == nil)
        #expect(snapshot.dataState == .noSleepLastNight)
    }

    @Test func concurrentRefreshesShareOneResult() async {
        let repo = repository(.full)
        async let a = repo.refresh(profile: UserProfileSnapshot())
        async let b = repo.refresh(profile: UserProfileSnapshot())
        let (first, second) = await (a, b)
        #expect(first == second)
    }

    @Test func standingRecordsCoverNinetyNights() async throws {
        let snapshot = await repository(.full).refresh(profile: UserProfileSnapshot())
        let types = Set(snapshot.records.map(\.type))
        #expect(types.isSubset(of: [.recordLongestNight, .recordBestConsistency, .recordHighestRecovery, .recordLowestRestingHeartRate]))
        for record in snapshot.records {
            #expect(record.nightsInWindow >= InsightModelV2.recordMinimumLong)
            #expect(last.days(from: record.night) < InsightModelV2.recordLongWindow)
        }
    }
}
