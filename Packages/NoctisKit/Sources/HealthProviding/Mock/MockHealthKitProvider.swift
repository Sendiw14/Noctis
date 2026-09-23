// DEBUG only: MockHealthKitProvider must never compile into a Release build.
#if DEBUG
import Foundation

/// Development-only stand-in for a real HealthKit-backed provider. Clearly
/// separate type from anything that will ship reading real device data —
/// never wire this into a Release configuration.
public final class MockHealthKitProvider: HealthDataProviding {
    public let isHealthDataAvailable: Bool
    public let sourceName = "Apple Watch (Simulated)"

    private var status: HealthAuthorizationStatus
    private let nights: [NightProfile]
    /// Debug-only failure injection — Plan's build checklist needs a way to
    /// exercise its genuine-failure branch (distinct from "no permission"/
    /// "no data") in the simulator, where the mock otherwise never fails a
    /// query once authorized.
    private let failsQueries: Bool

    public init(
        seed: UInt64 = 0x4E4F435449_53,
        historyDays: Int = 120,
        referenceDate: Date = .now,
        calendar: Calendar = .current,
        startAuthorized: Bool = false,
        isHealthDataAvailable: Bool = true,
        failsQueries: Bool = false
    ) {
        self.status = startAuthorized ? .authorized : .notDetermined
        self.nights = MockNightGenerator.generate(seed: seed, count: historyDays, referenceDate: referenceDate, calendar: calendar)
        self.isHealthDataAvailable = isHealthDataAvailable
        self.failsQueries = failsQueries
    }

    public func authorizationStatus() async -> HealthAuthorizationStatus { status }

    public func requestAuthorization(for kinds: [HealthDataKind]) async -> HealthAuthorizationStatus {
        status = .authorized
        return status
    }

    public func fetchSleepSamples(from start: Date, to end: Date) async throws -> [RawSleepSample] {
        try requireAuthorized()
        if failsQueries { throw HealthProviderError.queryFailed }
        return nights.flatMap(\.sleepSamples).filter { $0.start < end && $0.end > start }
    }

    public func fetchHeartRateSamples(from start: Date, to end: Date) async throws -> [HeartRateSample] {
        try requireAuthorized()
        return nights.flatMap(\.heartRateSamples).filter { $0.date >= start && $0.date <= end }
    }

    public func fetchRestingHeartRate(from start: Date, to end: Date) async throws -> [HeartRateSample] {
        try requireAuthorized()
        return nights.map(\.restingHeartRate).filter { $0.date >= start && $0.date <= end }
    }

    public func fetchHRVSamples(from start: Date, to end: Date) async throws -> [HRVSample] {
        try requireAuthorized()
        return nights.flatMap(\.hrvSamples).filter { $0.date >= start && $0.date <= end }
    }

    public func fetchRespiratorySamples(from start: Date, to end: Date) async throws -> [RespiratoryRateSample] {
        try requireAuthorized()
        return nights.flatMap(\.respiratorySamples).filter { $0.date >= start && $0.date <= end }
    }

    private func requireAuthorized() throws {
        guard status == .authorized else { throw HealthProviderError.unauthorized }
    }
}
#endif
