import Foundation

/// The seam between NOCTIS and wherever health samples actually come from.
/// `HealthKitProvider` backs this in every build; `MockHealthKitProvider`
/// exists only in DEBUG builds, behind the `-useMockHealth` launch argument.
public protocol HealthDataProviding: Sendable {
    var isHealthDataAvailable: Bool { get }
    var sourceName: String { get }

    /// Whether the system's question has been asked for `HealthDataKind.core`. `.authorized` means "asked", never "allowed": HealthKit does not tell an
    /// app which read types were declined, so the screens treat a declined type as one with no data.
    func authorizationStatus() async -> HealthAuthorizationStatus
    /// The same question for any set of kinds: `.authorized` only when every one of them has been asked for.
    func authorizationStatus(for kinds: [HealthDataKind]) async -> HealthAuthorizationStatus
    func requestAuthorization(for kinds: [HealthDataKind]) async -> HealthAuthorizationStatus

    func fetchSleepSamples(from start: Date, to end: Date) async throws -> [RawSleepSample]
    func fetchHeartRateSamples(from start: Date, to end: Date) async throws -> [HeartRateSample]
    func fetchRestingHeartRate(from start: Date, to end: Date) async throws -> [HeartRateSample]
    func fetchHRVSamples(from start: Date, to end: Date) async throws -> [HRVSample]
    func fetchRespiratorySamples(from start: Date, to end: Date) async throws -> [RespiratoryRateSample]

    /// Yields whenever sleep, HRV or resting heart rate data changes in
    /// the store (`HKObserverQuery` in the real provider). Plain heart rate
    /// is left out: it changes every few minutes while the watch is worn.
    func sampleChanges() -> AsyncStream<Void>
}

extension HealthDataProviding {
    /// A provider that cannot tell kinds apart answers the one question it has.
    public func authorizationStatus(for kinds: [HealthDataKind]) async -> HealthAuthorizationStatus {
        await authorizationStatus()
    }
}

extension HealthDataProviding {
    /// Resting heart rate is an optional extra: onboarding does not ask for it (`HealthDataKind.core`), and HealthKit **throws** "authorization not
    /// determined" for a kind the system's question was never asked for, which the provider reports as `.unauthorized`. For a screen that would read as
    /// "no permission" for everything. Here an unasked optional kind is simply no data; a kind that was asked for and declined already returns nothing.
    public func restingHeartRateIfAsked(from start: Date, to end: Date) async throws -> [HeartRateSample] {
        do {
            return try await fetchRestingHeartRate(from: start, to: end)
        } catch HealthProviderError.unauthorized {
            return []
        }
    }

    /// Respiratory rate, the same way as `restingHeartRateIfAsked`.
    public func respiratorySamplesIfAsked(from start: Date, to end: Date) async throws -> [RespiratoryRateSample] {
        do {
            return try await fetchRespiratorySamples(from: start, to: end)
        } catch HealthProviderError.unauthorized {
            return []
        }
    }
}

public nonisolated enum HealthProviderError: Error, Sendable {
    case unauthorized
    case unavailable
    case queryFailed
}
