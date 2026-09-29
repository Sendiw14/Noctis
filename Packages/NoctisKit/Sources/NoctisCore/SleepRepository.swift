import DesignSystem
import Foundation
import HealthProviding
import SleepAnalysisKit
import SleepKit

/// Reads Health for the Sleep tab and derives every night off the main
/// thread: sessions, metrics, quality, balance, consistency and timing
/// (`SleepSnapshot`), and the render model for each selection. Refreshes
/// are coalesced, derived values are cached, and each selection's render
/// model is built once per snapshot.
public actor SleepRepository {
    /// Days of history fetched: the 30 nights Month shows, the 14-night
    /// baseline behind the oldest of them, and a night to spare.
    public static let historyDays = 46
    /// Heart rate is fetched for the nights the snapshot keeps.
    public static let heartRateDays = SleepSnapshotBuilder.retainedNights + 1

    private let provider: any HealthDataProviding
    private let timeZone: TimeZone
    private let clock: @Sendable () -> Date
    private var inFlight: Task<SleepSnapshot, Never>?
    private var models: [SleepSelection: SleepRenderModel] = [:]
    private var modelsSnapshot: Date?

    /// The last snapshot built, if any.
    public private(set) var cachedSnapshot: SleepSnapshot?

    public init(
        provider: any HealthDataProviding,
        timeZone: TimeZone = .autoupdatingCurrent,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.timeZone = timeZone
        self.clock = clock
    }

    public func refresh(profile: UserProfileSnapshot) async -> SleepSnapshot {
        if let inFlight { return await inFlight.value }
        NoctisSignpost.begin(.sleepLoad)
        let task = Task { await load(profile: profile) }
        inFlight = task
        let snapshot = await task.value
        inFlight = nil
        NoctisSignpost.end(.sleepLoad)
        cachedSnapshot = snapshot
        return snapshot
    }

    /// The render model for `selection` on the cached snapshot, built
    /// once and kept until the next snapshot. Nil before a snapshot exists.
    public func model(for selection: SleepSelection) -> SleepRenderModel? {
        guard let snapshot = cachedSnapshot else { return nil }
        return model(for: selection, in: snapshot)
    }

    public func model(for selection: SleepSelection, in snapshot: SleepSnapshot) -> SleepRenderModel {
        if modelsSnapshot != snapshot.lastUpdated {
            models = [:]
            modelsSnapshot = snapshot.lastUpdated
        }
        if let cached = models[selection] { return cached }
        NoctisSignpost.begin(.sleepModel)
        let model = SleepRenderModelBuilder.build(snapshot, selection: selection)
        NoctisSignpost.end(.sleepModel)
        models[selection] = model
        return model
    }

    // MARK: Range queries

    /// One night's record.
    public func night(_ key: SleepNightKey) -> SleepNightRecord? {
        cachedSnapshot?.record(key)
    }

    /// The `count` nights (7 or 30) ending on `night`, oldest first, with
    /// nil where nothing was recorded.
    public func nights(endingAt night: SleepNightKey, count: Int) -> [(night: SleepNightKey, record: SleepNightRecord?)] {
        cachedSnapshot?.nights(endingAt: night, count: count) ?? []
    }

    /// Yields when Health data behind Sleep changes.
    public func changes() async -> AsyncStream<Void> {
        await provider.sampleChanges()
    }

    // MARK: Loading

    private func load(profile: UserProfileSnapshot) async -> SleepSnapshot {
        let now = clock()
        guard await provider.isHealthDataAvailable else {
            return SleepSnapshotBuilder.placeholder(.healthDataUnavailable, profile: profile, now: now, timeZone: timeZone)
        }
        guard await provider.authorizationStatus() == .authorized else {
            return SleepSnapshotBuilder.placeholder(.permissionRequired, profile: profile, now: now, timeZone: timeZone)
        }
        // Reach back 18 hours more so the oldest night is seen whole.
        let start = now.addingTimeInterval(-Double(Self.historyDays) * 86_400 - 18 * 3600)
        do {
            async let sleep = provider.fetchSleepSamples(from: start, to: now)
            async let heartRate = provider.fetchHeartRateSamples(from: now.addingTimeInterval(-Double(Self.heartRateDays) * 86_400), to: now)
            let inputs = try await HomeHealthInputs(sleep: sleep, hrv: [], restingHeartRate: [], heartRate: heartRate)
            return SleepSnapshotBuilder.build(inputs, profile: profile, now: now, timeZone: timeZone)
        } catch HealthProviderError.unauthorized {
            return SleepSnapshotBuilder.placeholder(.permissionRequired, profile: profile, now: now, timeZone: timeZone)
        } catch {
            return SleepSnapshotBuilder.placeholder(.failed, profile: profile, now: now, timeZone: timeZone)
        }
    }
}
