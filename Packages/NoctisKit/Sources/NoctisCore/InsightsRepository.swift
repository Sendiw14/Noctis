import Foundation
import HealthProviding
import InsightsKit
import SleepKit

/// Assembles an `InsightsSnapshot`. Pure: no I/O and no clock.
public nonisolated enum InsightsSnapshotBuilder {
    /// The snapshot for `library` (already merged with what `inputs`
    /// generated).
    public static func build(_ library: InsightLibrary, inputs: InsightInputs, now: Date) -> InsightsSnapshot {
        let recorded = inputs.complete.count
        guard let last = inputs.lastNight else {
            // Data, but nothing that ended in the last 24 hours: the library
            // is still worth showing (History, records), with no featured story.
            let night = inputs.complete.map(\.night).max()
            let learning = recorded < InsightModelV2.learningNights
            return InsightsSnapshot(
                dataState: learning ? .learning(nightsSoFar: recorded) : .noSleepLastNight,
                night: night, nightsRecorded: recorded, featured: nil,
                recent: learning ? [] : night.map { library.recent(on: $0) } ?? [],
                all: library.visible, newThisWeek: 0,
                records: learning ? [] : InsightEngineV2.standingRecords(inputs), lastUpdated: now
            )
        }
        let learning = recorded < InsightModelV2.learningNights
        return InsightsSnapshot(
            dataState: learning ? .learning(nightsSoFar: recorded) : .ready,
            night: last.night,
            nightsRecorded: recorded,
            featured: learning ? nil : library.featured(on: last.night),
            recent: learning ? [] : library.recent(on: last.night),
            all: library.visible,
            newThisWeek: learning ? 0 : library.newThisWeek(on: last.night).count,
            records: learning ? [] : InsightEngineV2.standingRecords(inputs),
            lastUpdated: now
        )
    }
}

/// Builds and caches the Insights snapshot off the main thread: reads Health,
/// runs the engine, merges what it generated into the `InsightStore` and
/// reads the store back. Refreshes are coalesced: one requested while one is
/// running shares its result.
public actor InsightsRepository {
    private let provider: any HealthDataProviding
    private let store: InsightStore
    private let timeZone: TimeZone
    private let clock: @Sendable () -> Date
    private var inFlight: Task<InsightsSnapshot, Never>?
    private var lastInputs: InsightInputs?

    public private(set) var cachedSnapshot: InsightsSnapshot?

    public init(
        provider: any HealthDataProviding, store: InsightStore = InsightStore(),
        timeZone: TimeZone = .autoupdatingCurrent, clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.store = store
        self.timeZone = timeZone
        self.clock = clock
    }

    /// Forgets the snapshot held in memory (Data management); the next refresh builds it again from Health.
    public func clearCache() {
        cachedSnapshot = nil
        lastInputs = nil
    }

    public func refresh(profile: UserProfileSnapshot) async -> InsightsSnapshot {
        if let inFlight { return await inFlight.value }
        let task = Task { await load(profile: profile) }
        inFlight = task
        let snapshot = await task.value
        inFlight = nil
        cachedSnapshot = snapshot
        return snapshot
    }

    /// Opening an insight: it stops counting as new.
    public func markSeen(id: String) async -> InsightsSnapshot? {
        await store.markSeen(id: id)
        return await rebuild()
    }

    /// "Not useful": muted everywhere, never featured again for this
    /// evidence.
    public func dismiss(id: String) async -> InsightsSnapshot? {
        await store.dismiss(id: id)
        return await rebuild()
    }

    /// "Hide insights like this".
    public func hide(_ type: InsightType) async -> InsightsSnapshot? {
        await store.hide(type)
        return await rebuild()
    }

    /// Yields when Health data behind the insights changes.
    public func changes() async -> AsyncStream<Void> {
        await provider.sampleChanges()
    }

    /// The cached snapshot rebuilt from the store, without reading Health.
    private func rebuild() async -> InsightsSnapshot? {
        guard let inputs = lastInputs else { return cachedSnapshot }
        let library = await store.snapshot()
        let snapshot = InsightsSnapshotBuilder.build(library, inputs: inputs, now: clock())
        cachedSnapshot = snapshot
        return snapshot
    }

    /// Home already read the last `InsightInputsBuilder.historyDays` days:
    /// the insights are made from those instead of asking Health again.
    public func refresh(
        profile: UserProfileSnapshot, sleep: [RawSleepSample], hrv: [HRVSample], restingHeartRate: [HeartRateSample]
    ) async -> InsightsSnapshot {
        let snapshot = await build(profile: profile, sleep: sleep, hrv: hrv, resting: restingHeartRate)
        cachedSnapshot = snapshot
        return snapshot
    }

    private func load(profile: UserProfileSnapshot) async -> InsightsSnapshot {
        let now = clock()
        guard await provider.isHealthDataAvailable else { return .placeholder(.healthDataUnavailable, now: now) }
        guard await provider.authorizationStatus() == .authorized else { return .placeholder(.permissionRequired, now: now) }
        // Reach back 18 hours more so the oldest night is seen whole.
        let start = now.addingTimeInterval(-Double(InsightInputsBuilder.historyDays) * 86_400 - 18 * 3600)
        do {
            async let sleep = provider.fetchSleepSamples(from: start, to: now)
            async let hrv = provider.fetchHRVSamples(from: start, to: now)
            async let resting = provider.fetchRestingHeartRate(from: start, to: now)
            let (sleepSamples, hrvSamples, restingSamples) = try await (sleep, hrv, resting)
            return await build(profile: profile, sleep: sleepSamples, hrv: hrvSamples, resting: restingSamples)
        } catch HealthProviderError.unauthorized {
            return .placeholder(.permissionRequired, now: now)
        } catch {
            return .placeholder(.failed, now: now)
        }
    }

    /// The insights for these samples, merged into the store.
    private func build(profile: UserProfileSnapshot, sleep: [RawSleepSample], hrv: [HRVSample], resting: [HeartRateSample]) async -> InsightsSnapshot {
        let now = clock()
        guard !sleep.isEmpty || !hrv.isEmpty || !resting.isEmpty else { return .placeholder(.empty, now: now) }
        let inputs = InsightInputsBuilder.build(
            sleep: sleep, hrv: hrv, restingHeartRate: resting, needMinutes: Double(profile.needMinutes), now: now, timeZone: timeZone
        )
        lastInputs = inputs
        let history = await store.snapshot().history
        let generated = InsightEngineV2.generate(inputs, history: history)
        let library = await store.ingest(generated, featuredOn: inputs.lastNight?.night)
        return InsightsSnapshotBuilder.build(library, inputs: inputs, now: now)
    }
}
