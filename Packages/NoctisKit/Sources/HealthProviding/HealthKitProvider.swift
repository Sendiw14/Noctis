import Foundation
import HealthKit

/// The shipping `HealthDataProviding`: reads the user's own Apple Health
/// data through `HKHealthStore`, read-only.
///
/// HealthKit never reveals whether the user denied *read* access — a
/// declined type simply returns no samples. So once the permission sheet
/// has been shown, this reports `.authorized` either way, and "no data"
/// (never "denied") is what the rest of the app sees for a decline.
/// `.unavailable` is reserved for devices without Health and for a request
/// that genuinely failed.
public final class HealthKitProvider: HealthDataProviding {
    public let sourceName = "Apple Health"

    private let store = HKHealthStore()
    /// The observer queries behind background delivery (not the foreground `sampleChanges()` ones).
    private var backgroundObservers: BackgroundObservers?

    public init() {}

    public var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    public func authorizationStatus() async -> HealthAuthorizationStatus {
        guard isHealthDataAvailable else { return .unavailable }
        let types = Self.readTypes(for: HealthDataKind.allCases)
        let requestStatus = try? await store.statusForAuthorizationRequest(toShare: [], read: types)
        return requestStatus == .unnecessary ? .authorized : .notDetermined
    }

    public func requestAuthorization(for kinds: [HealthDataKind]) async -> HealthAuthorizationStatus {
        guard isHealthDataAvailable else { return .unavailable }
        do {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes(for: kinds))
            return .authorized
        } catch {
            return .unavailable
        }
    }

    public func fetchSleepSamples(from start: Date, to end: Date) async throws -> [RawSleepSample] {
        let samples = try await categorySamples(.sleepAnalysis, from: start, to: end)
        return samples.compactMap { sample in
            guard let stage = Self.stage(for: sample.value) else { return nil }
            return RawSleepSample(
                id: sample.uuid,
                start: sample.startDate,
                end: sample.endDate,
                stage: stage,
                sourceName: sample.sourceRevision.source.name,
                sourceBundleID: sample.sourceRevision.source.bundleIdentifier,
                timeZone: (sample.metadata?[HKMetadataKeyTimeZone] as? String).flatMap(TimeZone.init(identifier:))
            )
        }
    }

    public func fetchHeartRateSamples(from start: Date, to end: Date) async throws -> [HeartRateSample] {
        let samples = try await quantitySamples(.heartRate, from: start, to: end)
        return samples.map {
            HeartRateSample(id: $0.uuid, date: $0.startDate, bpm: $0.quantity.doubleValue(for: Self.perMinute), sourceName: $0.sourceRevision.source.name)
        }
    }

    public func fetchRestingHeartRate(from start: Date, to end: Date) async throws -> [HeartRateSample] {
        let samples = try await quantitySamples(.restingHeartRate, from: start, to: end)
        return samples.map {
            HeartRateSample(id: $0.uuid, date: $0.startDate, bpm: $0.quantity.doubleValue(for: Self.perMinute), sourceName: $0.sourceRevision.source.name)
        }
    }

    public func fetchHRVSamples(from start: Date, to end: Date) async throws -> [HRVSample] {
        let samples = try await quantitySamples(.heartRateVariabilitySDNN, from: start, to: end)
        return samples.map {
            HRVSample(id: $0.uuid, date: $0.startDate, sdnnMilliseconds: $0.quantity.doubleValue(for: .secondUnit(with: .milli)))
        }
    }

    public func fetchRespiratorySamples(from start: Date, to end: Date) async throws -> [RespiratoryRateSample] {
        let samples = try await quantitySamples(.respiratoryRate, from: start, to: end)
        return samples.map {
            RespiratoryRateSample(id: $0.uuid, date: $0.startDate, breathsPerMinute: $0.quantity.doubleValue(for: Self.perMinute))
        }
    }

    public func sampleChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            guard isHealthDataAvailable else {
                continuation.finish()
                return
            }
            let queries = ObserverQueries(yieldingTo: continuation)
            queries.run(on: store)
            continuation.onTermination = { [store] _ in queries.stop(on: store) }
        }
    }

    // MARK: - Queries

    private static let perMinute = HKUnit.count().unitDivided(by: .minute())

    private func categorySamples(_ identifier: HKCategoryTypeIdentifier, from start: Date, to end: Date) async throws -> [HKCategorySample] {
        guard isHealthDataAvailable else { throw HealthProviderError.unavailable }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(identifier), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await run { try await descriptor.result(for: store) }
    }

    private func quantitySamples(_ identifier: HKQuantityTypeIdentifier, from start: Date, to end: Date) async throws -> [HKQuantitySample] {
        guard isHealthDataAvailable else { throw HealthProviderError.unavailable }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await run { try await descriptor.result(for: store) }
    }

    /// Maps HealthKit's errors onto the app's own: permission problems read
    /// as `.unauthorized`, everything else (locked device, store failure) as
    /// a genuine `.queryFailed`.
    private func run<T>(_ query: () async throws -> T) async throws -> T {
        do {
            return try await query()
        } catch let error as HKError where error.code == .errorAuthorizationDenied || error.code == .errorAuthorizationNotDetermined {
            throw HealthProviderError.unauthorized
        } catch {
            throw HealthProviderError.queryFailed
        }
    }

    // MARK: - Mapping

    private static func readTypes(for kinds: [HealthDataKind]) -> Set<HKObjectType> {
        Set(kinds.map { kind -> HKObjectType in
            switch kind {
            case .sleepAnalysis: HKCategoryType(.sleepAnalysis)
            case .heartRate: HKQuantityType(.heartRate)
            case .restingHeartRate: HKQuantityType(.restingHeartRate)
            case .hrv: HKQuantityType(.heartRateVariabilitySDNN)
            case .respiratoryRate: HKQuantityType(.respiratoryRate)
            }
        })
    }

    private static func stage(for value: Int) -> SleepStageValue? {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .inBed: .inBed
        case .awake: .awake
        case .asleepREM: .rem
        case .asleepCore: .core
        case .asleepDeep: .deep
        case .asleepUnspecified: .unspecified
        default: nil
        }
    }
}

/// Holds the observer queries behind one `sampleChanges()` stream so its
/// termination handler can stop them. HealthKit queries are thread-safe to
/// execute and stop.
/// Built nonisolated on purpose: HealthKit calls the update handlers on
/// its own background queue, so they must not inherit the main actor.
private nonisolated final class ObserverQueries: @unchecked Sendable {
    private let queries: [HKObserverQuery]

    init(yieldingTo continuation: AsyncStream<Void>.Continuation) {
        let observed: [HKSampleType] = [
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
        ]
        queries = observed.map { type in
            HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, error in
                if error == nil { continuation.yield() }
                completionHandler()
            }
        }
    }

    func run(on store: HKHealthStore) {
        queries.forEach(store.execute)
    }

    func stop(on store: HKHealthStore) {
        queries.forEach(store.stop)
    }
}


// MARK: - Background delivery (APP_RULES.md R46)

extension HealthKitProvider: HealthBackgroundDelivering {
    public func startBackgroundDelivery(wake: @escaping @Sendable (_ done: @escaping @Sendable () -> Void) -> Void) async {
        guard isHealthDataAvailable else { return }
        backgroundObservers?.stop(on: store)
        for entry in HealthBackgroundPlan.observed {
            guard let type = Self.readTypes(for: [entry.kind]).first as? HKSampleType else { continue }
            let frequency: HKUpdateFrequency = entry.frequency == .hourly ? .hourly : .daily
            // A failure (no entitlement in this build, access not yet asked) leaves the foreground observers working.
            try? await store.enableBackgroundDelivery(for: type, frequency: frequency)
        }
        let observers = BackgroundObservers(wake: wake)
        observers.run(on: store)
        backgroundObservers = observers
    }

    public func stopBackgroundDelivery() async {
        backgroundObservers?.stop(on: store)
        backgroundObservers = nil
        try? await store.disableAllBackgroundDelivery()
    }
}

/// One observer query for each kind in `HealthBackgroundPlan`. HealthKit calls the handler on its own queue when the app is woken or
/// running; the handler's `completionHandler` is given to `wake` as `done`, and called here on every path (an error included), so
/// HealthKit is never left waiting.
private nonisolated final class BackgroundObservers: @unchecked Sendable {
    private let queries: [HKObserverQuery]

    init(wake: @escaping @Sendable (_ done: @escaping @Sendable () -> Void) -> Void) {
        let types: [HKSampleType] = HealthBackgroundPlan.observed.compactMap { entry in
            switch entry.kind {
            case .sleepAnalysis: HKCategoryType(.sleepAnalysis)
            case .hrv: HKQuantityType(.heartRateVariabilitySDNN)
            case .restingHeartRate: HKQuantityType(.restingHeartRate)
            case .heartRate, .respiratoryRate: nil
            }
        }
        queries = types.map { type in
            HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, error in
                let completion = Completion(call: completionHandler)
                if error == nil {
                    wake { completion.call() }
                } else {
                    completion.call()
                }
            }
        }
    }

    func run(on store: HKHealthStore) {
        queries.forEach(store.execute)
    }

    func stop(on store: HKHealthStore) {
        queries.forEach(store.stop)
    }
}

/// HealthKit's completion handler, which it documents as callable from any queue, passed to code that runs elsewhere.
private nonisolated struct Completion: @unchecked Sendable {
    let call: () -> Void
}
