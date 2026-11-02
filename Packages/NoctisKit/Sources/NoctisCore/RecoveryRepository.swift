import DesignSystem
import Foundation
import HealthProviding
import RecoveryKit
import SleepKit

/// Reads Health for the Recovery tab and derives everything off the main
/// thread: today's score, each night's score, the 7/30/90-night histories,
/// every factor's series (`RecoverySnapshot`), and the render model for
/// each selection. Refreshes are coalesced, derived values are cached, and
/// each selection's render model is built once per snapshot.
public actor RecoveryRepository {
    private let provider: any HealthDataProviding
    private let timeZone: TimeZone
    private let clock: @Sendable () -> Date
    private var inFlight: Task<RecoverySnapshot, Never>?
    private var models: [RecoverySelection: RecoveryRenderModel] = [:]
    private var modelsSnapshot: Date?

    /// The last snapshot built, if any.
    public private(set) var cachedSnapshot: RecoverySnapshot?

    public init(
        provider: any HealthDataProviding,
        timeZone: TimeZone = .autoupdatingCurrent,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.timeZone = timeZone
        self.clock = clock
    }

    /// Forgets the snapshot held in memory (Data management); the next refresh builds it again from Health.
    public func clearCache() {
        cachedSnapshot = nil
        models = [:]
        modelsSnapshot = nil
    }

    public func refresh(profile: UserProfileSnapshot) async -> RecoverySnapshot {
        if let inFlight { return await inFlight.value }
        NoctisSignpost.begin(.recoveryLoad)
        let task = Task { await load(profile: profile) }
        inFlight = task
        let snapshot = await task.value
        inFlight = nil
        NoctisSignpost.end(.recoveryLoad)
        cachedSnapshot = snapshot
        return snapshot
    }

    /// The render model for `selection` on the cached snapshot, built once
    /// and kept until the next snapshot. Nil before a snapshot exists.
    public func model(for selection: RecoverySelection) -> RecoveryRenderModel? {
        guard let snapshot = cachedSnapshot else { return nil }
        return model(for: selection, in: snapshot)
    }

    public func model(for selection: RecoverySelection, in snapshot: RecoverySnapshot) -> RecoveryRenderModel {
        if modelsSnapshot != snapshot.lastUpdated {
            models = [:]
            modelsSnapshot = snapshot.lastUpdated
        }
        if let cached = models[selection] { return cached }
        NoctisSignpost.begin(.recoveryModel)
        let model = RecoveryRenderModelBuilder.build(snapshot, selection: selection)
        NoctisSignpost.end(.recoveryModel)
        models[selection] = model
        return model
    }

    /// Yields when Health data behind Recovery changes.
    public func changes() async -> AsyncStream<Void> {
        await provider.sampleChanges()
    }

    // MARK: Loading

    private func load(profile: UserProfileSnapshot) async -> RecoverySnapshot {
        let now = clock()
        guard await provider.isHealthDataAvailable else {
            return RecoverySnapshotBuilder.placeholder(.healthDataUnavailable, profile: profile, now: now, timeZone: timeZone)
        }
        guard await provider.authorizationStatus() == .authorized else {
            return RecoverySnapshotBuilder.placeholder(.permissionRequired, profile: profile, now: now, timeZone: timeZone)
        }
        // Reach back 18 hours more so the oldest night is seen whole.
        let start = now.addingTimeInterval(-Double(RecoverySnapshotBuilder.historyNights) * 86_400 - 18 * 3600)
        do {
            async let sleep = provider.fetchSleepSamples(from: start, to: now)
            async let hrv = provider.fetchHRVSamples(from: start, to: now)
            async let resting = provider.restingHeartRateIfAsked(from: start, to: now)
            async let heartRate = provider.fetchHeartRateSamples(from: now.addingTimeInterval(-2 * 86_400), to: now)
            let inputs = try await HomeHealthInputs(sleep: sleep, hrv: hrv, restingHeartRate: resting, heartRate: heartRate)
            return RecoverySnapshotBuilder.build(inputs, profile: profile, now: now, timeZone: timeZone)
        } catch HealthProviderError.unauthorized {
            return RecoverySnapshotBuilder.placeholder(.permissionRequired, profile: profile, now: now, timeZone: timeZone)
        } catch {
            return RecoverySnapshotBuilder.placeholder(.failed, profile: profile, now: now, timeZone: timeZone)
        }
    }
}
