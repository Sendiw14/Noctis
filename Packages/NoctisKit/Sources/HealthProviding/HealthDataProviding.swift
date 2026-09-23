import Foundation

/// The seam between NOCTIS and wherever health samples actually come from.
/// `HealthKitProvider` backs this in every build; `MockHealthKitProvider`
/// exists only in DEBUG builds, behind the `-useMockHealth` launch argument.
public protocol HealthDataProviding: Sendable {
    var isHealthDataAvailable: Bool { get }
    var sourceName: String { get }

    func authorizationStatus() async -> HealthAuthorizationStatus
    func requestAuthorization(for kinds: [HealthDataKind]) async -> HealthAuthorizationStatus

    func fetchSleepSamples(from start: Date, to end: Date) async throws -> [RawSleepSample]
    func fetchHeartRateSamples(from start: Date, to end: Date) async throws -> [HeartRateSample]
    func fetchRestingHeartRate(from start: Date, to end: Date) async throws -> [HeartRateSample]
    func fetchHRVSamples(from start: Date, to end: Date) async throws -> [HRVSample]
    func fetchRespiratorySamples(from start: Date, to end: Date) async throws -> [RespiratoryRateSample]
}

public enum HealthProviderError: Error, Sendable {
    case unauthorized
    case unavailable
    case queryFailed
}
