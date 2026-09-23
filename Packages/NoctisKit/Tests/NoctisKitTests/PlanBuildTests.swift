import Foundation
import SwiftData
import Testing
@testable import HealthProviding
@testable import NoctisCore

struct PlanBuildTests {
    private func makeModel(provider: some HealthDataProviding) throws -> AppModel {
        let schema = Schema([UserProfileRecord.self, InsightFatigueRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        return AppModel(
            healthProvider: provider,
            profileStore: ProfileStore(context: context),
            insightFatigueStore: InsightFatigueStore(context: context)
        )
    }

    // MARK: - The 1.6s floor

    @Test func floorDelayReturnsRemainingTimeBeforeTheFloor() {
        #expect(noctisPlanBuildFloorDelay(elapsedSeconds: 0.5, floorSeconds: 1.6) == 1.1)
        #expect(noctisPlanBuildFloorDelay(elapsedSeconds: 0, floorSeconds: 1.6) == 1.6)
    }

    @Test func floorDelayIsZeroOnceRealWorkAlreadyMetOrExceededTheFloor() {
        #expect(noctisPlanBuildFloorDelay(elapsedSeconds: 1.6, floorSeconds: 1.6) == 0)
        #expect(noctisPlanBuildFloorDelay(elapsedSeconds: 2.4, floorSeconds: 1.6) == 0)
    }

    // MARK: - The no-data branch

    @Test func recentNightCountIsZeroWhenHealthDataIsUnavailable() async throws {
        let model = try makeModel(provider: MockHealthKitProvider(startAuthorized: true, isHealthDataAvailable: false))
        #expect(try await model.fetchRecentNightCount() == 0)
    }

    @Test func recentNightCountIsZeroWhenNotYetAuthorized() async throws {
        let model = try makeModel(provider: MockHealthKitProvider(startAuthorized: false))
        #expect(try await model.fetchRecentNightCount() == 0)
    }

    @Test func recentNightCountIsPositiveWhenAuthorizedWithHistory() async throws {
        let model = try makeModel(provider: MockHealthKitProvider(startAuthorized: true))
        #expect(try await model.fetchRecentNightCount() > 0)
    }

    @Test func recentNightCountThrowsOnAGenuineQueryFailure() async throws {
        let model = try makeModel(provider: MockHealthKitProvider(startAuthorized: true, failsQueries: true))
        await #expect(throws: HealthProviderError.self) {
            _ = try await model.fetchRecentNightCount()
        }
    }

    // MARK: - Nights, not days

    /// 30-day window holding only five real nights: one bedtime after
    /// midnight (still the previous evening's night), one night split in
    /// two by a 90-minute data gap (still one night), and a separate day
    /// with only a 40-minute nap (not a night at all). A days-in-window
    /// count would say 30; a raw session count would say 6.
    @Test func recentNightCountCountsDistinctNightsWithSleepNotDaysInTheWindow() async throws {
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: .now) ?? .now
        func at(_ daysAgo: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        func block(_ start: Date, hours: Double) -> RawSleepSample {
            RawSleepSample(start: start, end: start.addingTimeInterval(hours * 3600), stage: .core, sourceName: "Stub", sourceBundleID: "stub")
        }
        let samples = [
            block(at(20, 23), hours: 7.5),
            block(at(14, 22, 30), hours: 8),
            block(at(9, 1, 15), hours: 6.5), // after midnight: night of day 10
            block(at(5, 22), hours: 3.5), // split night, part 1
            block(at(4, 3), hours: 4), // split night, part 2 (90-minute gap)
            block(at(3, 14), hours: 40.0 / 60), // afternoon nap only
            block(at(1, 23), hours: 8),
        ]
        let model = try makeModel(provider: StubSleepProvider(samples: samples))
        #expect(try await model.fetchRecentNightCount(asOf: now) == 5)
    }

    /// The same data counted at 2:27 AM and 3:15 AM must give the same
    /// answer. Nights run 11 PM to 7 AM for the 35 evenings before Sep 24,
    /// except Aug 24's, which runs 8 PM to 3 AM. The 30-day window opens at
    /// 2:27 AM or 3:15 AM on Aug 25, so that early night overlaps it at
    /// 2:27 but not at 3:15, and Sep 23's night is still in progress at
    /// both times. Counting overlap made the old total drift (31 vs 30);
    /// only complete nights inside the window count: Aug 25 to Sep 22, 29.
    @Test func recentNightCountIsTheSameAt227AMAnd315AM() async throws {
        let calendar = Calendar.current
        let sep24 = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 24)))
        let at0227 = try #require(calendar.date(bySettingHour: 2, minute: 27, second: 0, of: sep24))
        let at0315 = try #require(calendar.date(bySettingHour: 3, minute: 15, second: 0, of: sep24))
        var samples: [RawSleepSample] = []
        for eveningsBefore in 1...35 {
            let evening = try #require(calendar.date(byAdding: .day, value: -eveningsBefore, to: sep24))
            let isEarlyNight = eveningsBefore == 31 // Aug 24
            let bedtime = try #require(calendar.date(bySettingHour: isEarlyNight ? 20 : 23, minute: 0, second: 0, of: evening))
            samples.append(RawSleepSample(
                start: bedtime,
                end: bedtime.addingTimeInterval(isEarlyNight ? 7 * 3600 : 8 * 3600),
                stage: .core,
                sourceName: "Stub",
                sourceBundleID: "stub"
            ))
        }
        let model = try makeModel(provider: StubSleepProvider(samples: samples))
        let countAt0227 = try await model.fetchRecentNightCount(asOf: at0227)
        let countAt0315 = try await model.fetchRecentNightCount(asOf: at0315)
        #expect(countAt0227 == countAt0315)
        #expect(countAt0227 == 29)
    }

    @Test func seedTypicalBedtimeBaselineDoesNotThrowWithNoData() async throws {
        let model = try makeModel(provider: MockHealthKitProvider(startAuthorized: false))
        try await model.seedTypicalBedtimeBaseline()
    }
}

private struct StubSleepProvider: HealthDataProviding {
    let samples: [RawSleepSample]
    let isHealthDataAvailable = true
    let sourceName = "Stub"

    func authorizationStatus() async -> HealthAuthorizationStatus { .authorized }
    func requestAuthorization(for kinds: [HealthDataKind]) async -> HealthAuthorizationStatus { .authorized }
    func fetchSleepSamples(from start: Date, to end: Date) async throws -> [RawSleepSample] {
        samples.filter { $0.start < end && $0.end > start }
    }
    func fetchHeartRateSamples(from start: Date, to end: Date) async throws -> [HeartRateSample] { [] }
    func fetchRestingHeartRate(from start: Date, to end: Date) async throws -> [HeartRateSample] { [] }
    func fetchHRVSamples(from start: Date, to end: Date) async throws -> [HRVSample] { [] }
    func fetchRespiratorySamples(from start: Date, to end: Date) async throws -> [RespiratoryRateSample] { [] }
}
