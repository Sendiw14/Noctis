// DEBUG only: MockHealthKitProvider must never compile into a Release build.
#if DEBUG
import Foundation

/// The data situations the mock can simulate (`-mockScenario <name>`).
public enum MockScenario: String, Sendable, CaseIterable {
    /// 120 nights of sleep with HRV, resting and overnight heart rate.
    case full
    /// The same nights, but no HRV or heart rate of any kind.
    case sleepOnly
    /// Only the last 3 nights.
    case learning
    /// No Health data at all.
    case empty
    /// Nothing newer than 30 hours ago.
    case stale
    /// No data last night; today's daytime heart rate still arrives.
    case gap
}

/// Development-only stand-in for a real HealthKit-backed provider. Clearly
/// separate type from anything that will ship reading real device data —
/// never wire this into a Release configuration.
///
/// Two sources, like a real iPhone + Apple Watch: the watch writes stages,
/// heart rate, HRV (several per night) and resting heart rate; the iPhone
/// writes an overlapping in-bed sample.
public final class MockHealthKitProvider: HealthDataProviding {
    public let isHealthDataAvailable: Bool
    public let sourceName = "Apple Watch (Simulated)"
    public let scenario: MockScenario

    private var status: HealthAuthorizationStatus
    private let sleep: [RawSleepSample]
    private let heartRate: [HeartRateSample]
    private let resting: [HeartRateSample]
    private let hrv: [HRVSample]
    private let respiratory: [RespiratoryRateSample]
    /// Debug-only failure injection — Plan's build checklist needs a way to
    /// exercise its genuine-failure branch (distinct from "no permission"/
    /// "no data") in the simulator, where the mock otherwise never fails a
    /// query once authorized.
    private let failsQueries: Bool

    public init(
        scenario: MockScenario = .full,
        seed: UInt64 = 0x4E4F435449_53,
        historyDays: Int = 120,
        referenceDate: Date = .now,
        calendar: Calendar = .current,
        startAuthorized: Bool = false,
        isHealthDataAvailable: Bool = true,
        failsQueries: Bool = false
    ) {
        self.scenario = scenario
        self.status = startAuthorized ? .authorized : .notDetermined
        self.isHealthDataAvailable = isHealthDataAvailable
        self.failsQueries = failsQueries

        let generated = MockNightGenerator.generate(seed: seed, count: historyDays, referenceDate: referenceDate, calendar: calendar)
        let nights: [NightProfile] = switch scenario {
        case .full, .sleepOnly, .stale: generated
        case .learning: Array(generated.suffix(3))
        case .empty: []
        case .gap: Array(generated.dropLast())
        }
        let daytime = scenario == .empty ? [] : MockNightGenerator.daytimeHeartRate(referenceDate: referenceDate, nights: generated, seed: seed)
        let hasHeartData = scenario != .sleepOnly
        // Stale: everything stops 30 hours before now.
        let cutoff = scenario == .stale ? referenceDate.addingTimeInterval(-30 * 3600) : referenceDate

        let allSleep = nights.flatMap(\.sleepSamples)
        sleep = scenario == .stale ? allSleep.filter { $0.end <= cutoff } : allSleep
        heartRate = hasHeartData ? (nights.flatMap(\.heartRateSamples) + daytime).filter { $0.date <= cutoff }.sorted { $0.date < $1.date } : []
        resting = hasHeartData ? nights.map(\.restingHeartRate).filter { $0.date <= cutoff } : []
        hrv = hasHeartData ? nights.flatMap(\.hrvSamples).filter { $0.date <= cutoff } : []
        respiratory = hasHeartData ? nights.flatMap(\.respiratorySamples).filter { $0.date <= cutoff } : []
    }

    public func authorizationStatus() async -> HealthAuthorizationStatus { status }

    public func requestAuthorization(for kinds: [HealthDataKind]) async -> HealthAuthorizationStatus {
        status = .authorized
        return status
    }

    public func fetchSleepSamples(from start: Date, to end: Date) async throws -> [RawSleepSample] {
        try requireAuthorized()
        if failsQueries { throw HealthProviderError.queryFailed }
        return sleep.filter { $0.start < end && $0.end > start }
    }

    public func fetchHeartRateSamples(from start: Date, to end: Date) async throws -> [HeartRateSample] {
        try requireAuthorized()
        return heartRate.filter { $0.date >= start && $0.date <= end }
    }

    public func fetchRestingHeartRate(from start: Date, to end: Date) async throws -> [HeartRateSample] {
        try requireAuthorized()
        return resting.filter { $0.date >= start && $0.date <= end }
    }

    public func fetchHRVSamples(from start: Date, to end: Date) async throws -> [HRVSample] {
        try requireAuthorized()
        return hrv.filter { $0.date >= start && $0.date <= end }
    }

    public func fetchRespiratorySamples(from start: Date, to end: Date) async throws -> [RespiratoryRateSample] {
        try requireAuthorized()
        return respiratory.filter { $0.date >= start && $0.date <= end }
    }

    /// The mock's data never changes after launch.
    public func sampleChanges() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    private func requireAuthorized() throws {
        guard status == .authorized else { throw HealthProviderError.unauthorized }
    }
}
#endif
