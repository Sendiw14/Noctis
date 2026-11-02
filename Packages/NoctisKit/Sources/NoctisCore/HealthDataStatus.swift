import Foundation
import HealthProviding

/// What NOCTIS can honestly say about Health data. HealthKit never says whether read access was allowed (a
/// denied type just returns nothing), so the only truth is whether samples are there: "Data found, the last
/// one on Sep 29", or "No data found". The page never says "denied", because nothing here can know it.
public nonisolated struct HealthKindStatus: Sendable, Equatable, Identifiable {
    public let kind: HealthDataKind
    /// When the newest sample in the look-back ended; nil when there is none.
    public let lastSample: Date?
    /// The look could not be made (the store was unavailable or the query failed).
    public let couldNotCheck: Bool

    public var id: HealthDataKind { kind }
    public var hasData: Bool { lastSample != nil }

    public init(kind: HealthDataKind, lastSample: Date?, couldNotCheck: Bool = false) {
        self.kind = kind
        self.lastSample = lastSample
        self.couldNotCheck = couldNotCheck
    }
}

public nonisolated struct HealthDataStatus: Sendable, Equatable {
    /// One per `HealthDataKind`, in the order the authorization manager lists them.
    public let kinds: [HealthKindStatus]
    /// How far back "the last sample" looks.
    public static let lookBackDays = 30
    /// The app that recorded last night's sleep, when the source resolver knows it; nil otherwise.
    public let lastNightSource: String?
    /// Health is not available on this device at all.
    public let isUnavailable: Bool
    /// The system's question has not been asked yet for at least one of the five kinds, so "Connect Apple Health" would show it (for a person
    /// who answered onboarding, that is resting heart rate and respiratory rate, which onboarding does not ask for). Once every kind has been
    /// asked it never shows again, and the only way to change an answer is the Health app.
    public let canRequestAccess: Bool

    public init(kinds: [HealthKindStatus], lastNightSource: String?, isUnavailable: Bool = false, canRequestAccess: Bool = false) {
        self.kinds = kinds
        self.lastNightSource = lastNightSource
        self.isUnavailable = isUnavailable
        self.canRequestAccess = canRequestAccess
    }

    public var hasAnyData: Bool { kinds.contains(where: \.hasData) }
    public var hasAllData: Bool { !kinds.isEmpty && kinds.allSatisfy(\.hasData) }
    public var missing: [HealthKindStatus] { kinds.filter { !$0.hasData } }
}

/// Reads the status from the same provider the rest of the app reads, over the last 30 days. The provider's
/// protocol is main-actor, so the read is too; it is one look when Profile or the Health page appears.
public struct HealthDataStatusReader {
    private let provider: any HealthDataProviding
    private let resolver: any SourceResolving

    public init(provider: any HealthDataProviding, resolver: any SourceResolving = DefaultSourceResolver()) {
        self.provider = provider
        self.resolver = resolver
    }

    public func read(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) async -> HealthDataStatus {
        guard provider.isHealthDataAvailable else {
            return HealthDataStatus(
                kinds: HealthDataKind.allCases.map { HealthKindStatus(kind: $0, lastSample: nil, couldNotCheck: true) }, lastNightSource: nil,
                isUnavailable: true)
        }
        let start = calendar.date(byAdding: .day, value: -HealthDataStatus.lookBackDays, to: now) ?? now.addingTimeInterval(-30 * 86_400)
        var statuses: [HealthKindStatus] = []
        var sleepSamples: [RawSleepSample] = []
        for kind in HealthDataKind.allCases {
            do {
                switch kind {
                case .sleepAnalysis:
                    sleepSamples = try await provider.fetchSleepSamples(from: start, to: now)
                    statuses.append(HealthKindStatus(kind: kind, lastSample: sleepSamples.map(\.end).max()))
                case .heartRate:
                    statuses.append(HealthKindStatus(kind: kind, lastSample: try await provider.fetchHeartRateSamples(from: start, to: now).map(\.date).max()))
                case .restingHeartRate:
                    statuses.append(HealthKindStatus(kind: kind, lastSample: try await provider.fetchRestingHeartRate(from: start, to: now).map(\.date).max()))
                case .hrv:
                    statuses.append(HealthKindStatus(kind: kind, lastSample: try await provider.fetchHRVSamples(from: start, to: now).map(\.date).max()))
                case .respiratoryRate:
                    statuses.append(
                        HealthKindStatus(kind: kind, lastSample: try await provider.fetchRespiratorySamples(from: start, to: now).map(\.date).max()))
                }
            } catch HealthProviderError.unauthorized {
                // The system's question has not been asked (a read that was declined returns nothing instead):
                // there is no data to be found, and nothing went wrong.
                statuses.append(HealthKindStatus(kind: kind, lastSample: nil))
            } catch {
                statuses.append(HealthKindStatus(kind: kind, lastSample: nil, couldNotCheck: true))
            }
        }
        // Any of the five still to be asked (resting heart rate and respiratory rate are asked only from here, never by onboarding).
        let canRequest = await provider.authorizationStatus(for: HealthDataKind.allCases) == .notDetermined
        return HealthDataStatus(
            kinds: statuses, lastNightSource: Self.lastNightSource(sleepSamples, resolver: resolver, now: now), isUnavailable: false,
            canRequestAccess: canRequest
        )
    }

    /// The source of the newest night's asleep samples after the resolver has chosen between sources; nil when
    /// there is no night in the last two days or no name.
    public nonisolated static func lastNightSource(_ samples: [RawSleepSample], resolver: any SourceResolving, now: Date) -> String? {
        let recent = samples.filter { $0.end > now.addingTimeInterval(-48 * 3600) && $0.stage.isAsleep }
        let resolved = resolver.resolveSleepSamples(recent)
        guard let newest = resolved.max(by: { $0.end < $1.end }), !newest.sourceName.isEmpty else { return nil }
        return newest.sourceName
    }
}
