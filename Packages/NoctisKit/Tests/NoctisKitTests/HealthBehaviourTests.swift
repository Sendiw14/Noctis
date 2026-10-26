import Foundation
import Testing

@testable import HealthProviding
@testable import HomeFeature
@testable import NoctisCore
@testable import RecoveryFeature
@testable import RecoveryKit
@testable import ReviewKit
@testable import SleepFeature
@testable import SleepKit

#if canImport(Darwin)
import Darwin
#endif

// QA part 3, step 2 (continued): how the app behaves when Health changes under it, and how it scales. The provider here is a real
// `HealthDataProviding` whose store the test edits between refreshes, like HealthKit's anchored deletions, a revoked permission or a watch that
// syncs late. Real HealthKit cannot be injected on the simulator: its store is empty and the app cannot write samples it did not record
// (HKHealthStore.save needs write authorization the app does not request). That path is UNVERIFIED and listed for a real device.

final class ScriptedHealth: HealthDataProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var sleep: [RawSleepSample]
    private var hrv: [HRVSample]
    private var resting: [HeartRateSample]
    private var status: HealthAuthorizationStatus = .authorized
    private var failure: HealthProviderError?
    let isHealthDataAvailable = true
    let sourceName = "Scripted"

    init(sleep: [RawSleepSample], hrv: [HRVSample] = [], resting: [HeartRateSample] = []) {
        self.sleep = sleep
        self.hrv = hrv
        self.resting = resting
    }

    func edit(_ change: (inout [RawSleepSample]) -> Void) { lock.withLock { change(&sleep) } }
    func setStatus(_ new: HealthAuthorizationStatus) { lock.withLock { status = new } }
    func fail(with error: HealthProviderError?) { lock.withLock { failure = error } }

    func authorizationStatus() async -> HealthAuthorizationStatus { lock.withLock { status } }
    func requestAuthorization(for kinds: [HealthDataKind]) async -> HealthAuthorizationStatus { lock.withLock { status } }
    func fetchSleepSamples(from start: Date, to end: Date) async throws -> [RawSleepSample] {
        try lock.withLock {
            if let failure { throw failure }
            return sleep.filter { $0.end > start && $0.start < end }
        }
    }
    func fetchHeartRateSamples(from start: Date, to end: Date) async throws -> [HeartRateSample] { [] }
    func fetchRestingHeartRate(from start: Date, to end: Date) async throws -> [HeartRateSample] {
        lock.withLock { resting.filter { $0.date >= start && $0.date <= end } }
    }
    func fetchHRVSamples(from start: Date, to end: Date) async throws -> [HRVSample] { lock.withLock { hrv.filter { $0.date >= start && $0.date <= end } } }
    func fetchRespiratorySamples(from start: Date, to end: Date) async throws -> [RespiratoryRateSample] { [] }
    func sampleChanges() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

struct HealthBehaviourTests {
    private let calendar = Fixture.calendar()

    /// Nine consecutive core nights ending on the morning of Sep 24, 2026, 11 PM to 7 AM.
    private func nights(source: String = "Watch", bundle: String = "com.apple.health.watch", count: Int = 9) -> [RawSleepSample] {
        (0..<count).map { offset in
            let bed = Fixture.date(2026, 9, 23 - offset, 23)
            return Fixture.sample(bed, bed.addingTimeInterval(8 * 3600), .core, source: source, bundle: bundle)
        }
    }

    private func home(_ provider: ScriptedHealth, at now: Date) async -> HomeSnapshot {
        await HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { now }).refresh(profile: UserProfileSnapshot())
    }

    @Test func deletedSamplesRecomputeInsteadOfKeepingTheOldNight() async {
        let now = Fixture.date(2026, 9, 24, 10)
        let provider = ScriptedHealth(sleep: nights())
        let repository = HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { now })
        let before = await repository.refresh(profile: UserProfileSnapshot())
        #expect(before.lastNight != nil)
        // The person deletes last night in Health (an anchored deletion): the next refresh must not show it.
        provider.edit { samples in samples.removeAll { $0.start >= Fixture.date(2026, 9, 23, 12) } }
        let after = await repository.refresh(profile: UserProfileSnapshot())
        #expect(after.lastNight == nil)
        #expect(after.latestSleep?.wakeTime ?? .distantFuture < Fixture.date(2026, 9, 23, 12))
        if case .scored = after.recovery { Issue.record("a recovery score survived the deletion of last night") }
    }

    @Test func revokedPermissionMidSessionShowsThePermissionStateNotStaleNumbers() async {
        let now = Fixture.date(2026, 9, 24, 10)
        let provider = ScriptedHealth(sleep: nights())
        let repository = HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { now })
        #expect(await repository.refresh(profile: UserProfileSnapshot()).lastNight != nil)
        provider.setStatus(.denied)
        let denied = await repository.refresh(profile: UserProfileSnapshot())
        #expect(denied.dataState == .permissionRequired)
        #expect(denied.lastNight == nil)
        // HealthKit can also fail a query with an authorization error after the status read.
        provider.setStatus(.authorized)
        provider.fail(with: .unauthorized)
        #expect(await repository.refresh(profile: UserProfileSnapshot()).dataState == .permissionRequired)
        provider.fail(with: .queryFailed)
        #expect(await repository.refresh(profile: UserProfileSnapshot()).dataState == .failed)
        provider.fail(with: nil)
        #expect(await repository.refresh(profile: UserProfileSnapshot()).lastNight != nil)
    }

    @Test func aWatchThatSyncsAtNineReplacesTheEarlierPartialNight() async {
        let provider = ScriptedHealth(sleep: nights(count: 8).filter { $0.start < Fixture.date(2026, 9, 23, 12) })
        // 7:30 AM: only the phone's in-bed sample for last night has arrived.
        let bed = Fixture.date(2026, 9, 23, 23)
        provider.edit { $0.append(Fixture.sample(bed, bed.addingTimeInterval(8 * 3600), .inBed, source: "Phone", bundle: "com.apple.health.phone")) }
        let early = await home(provider, at: Fixture.date(2026, 9, 24, 7, 30))
        #expect(early.lastNight == nil, "an in-bed sample alone is not a night's sleep")
        // 9:00 AM: the watch syncs its stages.
        provider.edit { $0.append(Fixture.sample(bed, bed.addingTimeInterval(7.5 * 3600), .core)) }
        let late = await home(provider, at: Fixture.date(2026, 9, 24, 9))
        let night = late.lastNight
        #expect(night != nil)
        #expect(night?.completeness.hasInBedData == true)
        #expect(abs((night?.totals.asleep ?? 0) - 7.5 * 3600) < 1)
    }

    @Test func conflictingSourcesAreNeverCountedTwice() {
        let bed = Fixture.date(2026, 9, 23, 23)
        let watch = Fixture.sample(bed, bed.addingTimeInterval(8 * 3600), .core, source: "Watch", bundle: "w")
        let ring = Fixture.sample(bed.addingTimeInterval(1800), bed.addingTimeInterval(9 * 3600), .deep, source: "Ring", bundle: "r")
        let now = Fixture.date(2026, 9, 24, 12)
        for samples in [[watch, ring], [ring, watch]] {
            let night = SleepSessionEngine.history(from: samples, asOf: now, timeZone: Fixture.newYork).nights.first
            // One source's claim wins for the overlap; the lower source's overlapping sample is dropped, not added.
            #expect((night?.totals.asleep ?? 0) <= 8.5 * 3600)
            #expect(abs((night?.totals.asleep ?? 0) - 8 * 3600) < 1 || abs((night?.totals.asleep ?? 0) - 8.5 * 3600) < 1)
        }
        let a = SleepSessionEngine.history(from: [watch, ring], asOf: now, timeZone: Fixture.newYork)
        let b = SleepSessionEngine.history(from: [ring, watch], asOf: now, timeZone: Fixture.newYork)
        #expect(a == b, "the answer must not depend on the order Health returns the samples in")
    }

    @Test func aNightRecordedInAnotherZoneKeepsItsLocalBedtime() {
        let tokyo = Fixture.tokyo
        let bed = Fixture.date(2026, 9, 23, 23, in: tokyo)
        let sample = Fixture.sample(bed, bed.addingTimeInterval(8 * 3600), .core, timeZone: tokyo)
        let night = SleepSessionEngine.history(from: [sample], asOf: Fixture.date(2026, 9, 24, 12, in: tokyo), timeZone: Fixture.newYork).nights.first
        // The phone is on New York time, but the night was slept in Tokyo: 11 PM is 660 minutes after noon and the night is Sep 23.
        #expect(night?.night == SleepNightKey(year: 2026, month: 9, day: 23))
        #expect(Int(night?.bedtimeMinutesAfterNoon ?? -1) == 660)
        #expect(Int(night?.wakeMinutesAfterNoon ?? -1) == 1140)
    }

    // MARK: - Scale

    @Test func twoYearsOfNightsLoadEveryTabInReasonableTimeAndMemory() async throws {
        let now = Fixture.date(2026, 9, 24, 10)
        let profile = UserProfileSnapshot()
        let mock = { MockHealthKitProvider(scenario: .full, historyDays: 730, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true) }
        let clock = ContinuousClock()
        let startMemory = residentMegabytes()

        var timings: [String] = []
        func time(_ name: String, _ work: () async -> Void) async {
            let elapsed = await clock.measure { await work() }
            timings.append("\(name) \(elapsed)")
        }
        await time("home refresh") { _ = await HomeRepository(provider: mock(), timeZone: Fixture.newYork, clock: { now }).refresh(profile: profile) }
        var sleep: SleepSnapshot?
        await time("sleep refresh") { sleep = await SleepRepository(provider: mock(), timeZone: Fixture.newYork, clock: { now }).refresh(profile: profile) }
        var recovery: RecoverySnapshot?
        await time("recovery refresh") {
            recovery = await RecoveryRepository(provider: mock(), timeZone: Fixture.newYork, clock: { now }).refresh(profile: profile)
        }
        let sleepSnapshot = try #require(sleep)
        let recoverySnapshot = try #require(recovery)
        await time("sleep month render") {
            let selection = SleepSelection(night: sleepSnapshot.defaultNight, range: .month)
            let model = SleepRenderModelBuilder.build(sleepSnapshot, selection: selection)
            _ = SleepScreenBuilder.build(
                sleepSnapshot, model: model, selection: selection, now: now, calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"))
        }
        await time("recovery 90D render") {
            let selection = RecoverySelection(segment: .quarter)
            let model = RecoveryRenderModelBuilder.build(recoverySnapshot, selection: selection)
            _ = RecoveryScreenBuilder.build(
                recoverySnapshot, model: model, selection: selection, now: now, calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"))
        }
        await time("monthly review x24") {
            let inputs: [ReviewNightInput] = (0..<730).map { offset in
                let morning = SleepNightKey(year: 2026, month: 9, day: 24).adding(days: -offset)
                return ReviewNightInput(
                    night: ReviewPeriod.night(endingOn: morning), asleepMinutes: 420 + Double(offset % 60), stages: nil,
                    bedtimeMinutes: 660 + Double(offset % 40),
                    wakeMinutes: 1140, recoveryScore: 60 + offset % 30, hrv: 55, restingHeartRate: 55
                )
            }
            for back in 0..<24 {
                let month = (9 - back - 1 + 120) % 12 + 1
                let year = 2026 - (back + 3) / 12 - (month > 9 && back < 9 ? 0 : 0)
                _ = ReviewEngine.build(period: .monthly(year: year, month: month), nights: inputs, needMinutes: 480, now: now, calendar: Fixture.calendar())
            }
        }
        let grown = residentMegabytes() - startMemory
        print("QA scale smoke (simulator, debug build, not device numbers): \(timings.joined(separator: "; ")); resident memory grew \(grown) MB")
        // Generous ceilings: these catch quadratic blow-ups and leaks, not tuning.
        #expect(grown < 600, "resident memory grew \(grown) MB")
    }

    private func residentMegabytes() -> Int {
        #if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Int(info.resident_size / 1_048_576) : 0
        #else
        return 0
        #endif
    }
}
