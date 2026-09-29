import Foundation
import HealthProviding
import InsightsKit
import RecoveryKit
import SleepAnalysisKit
import SleepKit

/// The Health data one Home snapshot is built from.
public nonisolated struct HomeHealthInputs: Sendable {
    public let sleep: [RawSleepSample]
    public let hrv: [HRVSample]
    public let restingHeartRate: [HeartRateSample]
    /// Recent heart rate, used only to tell whether data is still arriving.
    public let heartRate: [HeartRateSample]

    public init(sleep: [RawSleepSample], hrv: [HRVSample], restingHeartRate: [HeartRateSample], heartRate: [HeartRateSample]) {
        self.sleep = sleep
        self.hrv = hrv
        self.restingHeartRate = restingHeartRate
        self.heartRate = heartRate
    }
}

/// Assembles a `HomeSnapshot` from Health data with the engines. Pure: no
/// I/O and no clock, so every rule is unit-testable.
public nonisolated enum HomeSnapshotBuilder {
    public static let recentNightCount = 7
    /// Data whose newest sample is older than this is stale.
    public static let staleAfter: TimeInterval = 24 * 3600

    public static func build(
        _ inputs: HomeHealthInputs,
        profile: UserProfileSnapshot,
        now: Date,
        timeZone: TimeZone,
        insightHistory: InsightHistory = InsightHistory()
    ) -> HomeSnapshot {
        let dates = inputs.sleep.map(\.end) + inputs.hrv.map(\.date) + inputs.restingHeartRate.map(\.date) + inputs.heartRate.map(\.date)
        guard let newest = dates.filter({ $0 <= now }).max() else {
            return placeholder(.empty, profile: profile, now: now, timeZone: timeZone)
        }

        let history = SleepSessionEngine.history(from: inputs.sleep, asOf: now, timeZone: timeZone)
        let metrics = NightMetricsBuilder.metrics(for: history, hrv: inputs.hrv, restingHeartRate: inputs.restingHeartRate)
        let recovery = RecoveryEngine.evaluate(history: metrics, needMinutes: Double(profile.needMinutes), asOf: now)
        let lastNight = history.lastNight(asOf: now, within: RecoveryModelV1.lastNightWindow)

        let dataState: HomeDataState
        if now.timeIntervalSince(newest) > staleAfter {
            dataState = .stale(newestSample: newest)
        } else if case .learning(let nights) = recovery {
            dataState = .learning(nightsSoFar: nights)
        } else if lastNight == nil {
            dataState = .noSleepLastNight
        } else {
            dataState = .ready
        }

        // The Sleep tab's number for the same night; none while learning or
        // when nothing could be scored.
        var sleepQuality: Int?
        if let lastNight, !dataState.isLearning {
            let quality = SleepQualityEngine.score(night: lastNight, history: history.nights, needMinutes: Double(profile.needMinutes))
            sleepQuality = quality.isScored ? quality.score : nil
        }

        let weekEnd = lastNight?.night ?? expectedLastNight(now: now, timeZone: timeZone, wakeMinutes: profile.typicalWakeMinutes)
        let week = recentNights(history, endingAt: weekEnd)
        return HomeSnapshot(
            dataState: dataState,
            recovery: recovery,
            lastNight: lastNight,
            latestSleep: history.nights.max { $0.wakeTime < $1.wakeTime },
            recentNights: week,
            weekAverageMinutes: averageMinutes(week),
            tonight: TonightPlan(profile: profile),
            topInsight: InsightEngine.topInsight(history: metrics, asOf: now, fatigue: insightHistory),
            lastNightHeart: lastNight.flatMap { heartSeries(inputs.heartRate, for: $0) },
            lastNightSleepQuality: sleepQuality,
            newestSample: newest,
            lastUpdated: now
        )
    }

    /// A snapshot with no Health data in it: only tonight's plan, and seven
    /// empty nights.
    public static func placeholder(_ state: HomeDataState, profile: UserProfileSnapshot, now: Date, timeZone: TimeZone) -> HomeSnapshot {
        HomeSnapshot(
            dataState: state,
            recovery: nil,
            lastNight: nil,
            latestSleep: nil,
            recentNights: recentNights(.empty, endingAt: expectedLastNight(now: now, timeZone: timeZone, wakeMinutes: profile.typicalWakeMinutes)),
            weekAverageMinutes: nil,
            tonight: TonightPlan(profile: profile),
            topInsight: nil,
            newestSample: nil,
            lastUpdated: now
        )
    }

    /// The night that should be "last night" by now when none was
    /// recorded: the latest night whose planned wake-up (the profile's
    /// wake time, the next morning) has passed. At 6:00 AM with a 7:00 AM
    /// wake, that's the night before the one still in progress.
    static func expectedLastNight(now: Date, timeZone: TimeZone, wakeMinutes: Int) -> SleepNightKey {
        let current = SleepNightKey(containing: now, in: timeZone)
        let morning = current.adding(days: 1)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(year: morning.year, month: morning.month, day: morning.day, hour: wakeMinutes / 60, minute: wakeMinutes % 60)
        guard let plannedWake = calendar.date(from: components) else { return current.adding(days: -1) }
        return now >= plannedWake ? current : current.adding(days: -1)
    }

    /// Mean of the nights that have data; nil when none do.
    static func averageMinutes(_ nights: [NightDuration]) -> Double? {
        let values = nights.compactMap(\.asleepMinutes)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    static func recentNights(_ history: SleepHistory, endingAt last: SleepNightKey) -> [NightDuration] {
        (0..<recentNightCount).reversed().map { offset in
            let key = last.adding(days: -offset)
            let session = history.night(key)
            return NightDuration(
                night: key,
                asleepMinutes: session.map { $0.totals.asleep / 60 },
                stages: session.flatMap { $0.completeness.hasStageDetail ? NightStageMinutes($0.totals) : nil }
            )
        }
    }

    /// Heart rate across the session's span, the same span the night
    /// panel's chart runs over.
    static func heartSeries(_ samples: [HeartRateSample], for session: SleepSession) -> NightHeartSeries? {
        let start = session.timeline.first?.interval.start ?? session.bedtime
        let end = session.timeline.map(\.interval.end).max() ?? session.wakeTime
        return NightHeartSeries.build(samples: samples, from: start, to: end)
    }
}

/// Builds and caches Home's snapshot off the main thread. Refreshes are
/// coalesced: a refresh requested while one is running shares its result.
public actor HomeRepository {
    /// Days of history fetched: enough for the 14-night baselines of every
    /// night in the last week.
    public static let historyDays = 30

    private let provider: any HealthDataProviding
    private let timeZone: TimeZone
    private let clock: @Sendable () -> Date
    private let insightHistory: InsightHistoryStore
    private let store: HomeSnapshotStore?
    private var inFlight: Task<HomeSnapshot, Never>?

    /// The last snapshot built (or restored), if any.
    public private(set) var cachedSnapshot: HomeSnapshot?
    /// The snapshot the last launch saved, read once when the repository
    /// was made: Home draws it in its first frame, then revalidates. Nil
    /// without a store, or when the saved file was missing, unreadable,
    /// from another schema or too old.
    public nonisolated let restoredSnapshot: HomeSnapshot?

    /// `insightHistory` defaults to one kept in memory; the app passes
    /// the persisted store. With a `store`, every snapshot built is saved
    /// (`HomeSnapshotStore`) and the last one is restored at launch.
    public init(
        provider: any HealthDataProviding,
        timeZone: TimeZone = .autoupdatingCurrent,
        clock: @escaping @Sendable () -> Date = { Date() },
        insightHistory: InsightHistoryStore = InsightHistoryStore(),
        store: HomeSnapshotStore? = nil
    ) {
        self.provider = provider
        self.timeZone = timeZone
        self.clock = clock
        self.insightHistory = insightHistory
        self.store = store
        let restored = store?.load()
        restoredSnapshot = restored
        cachedSnapshot = restored
    }

    public func refresh(profile: UserProfileSnapshot) async -> HomeSnapshot {
        if let inFlight { return await inFlight.value }
        let task = Task { await load(profile: profile) }
        inFlight = task
        let snapshot = await task.value
        inFlight = nil
        if let insight = snapshot.topInsight {
            insightHistory.update { $0.recordShown(insight) }
        }
        cachedSnapshot = snapshot
        store?.save(snapshot)
        return snapshot
    }

    /// "Not useful": no insight for the rest of this night.
    public func dismiss(_ insight: Insight) -> HomeSnapshot? {
        insightHistory.update { $0.recordDismissal(insight) }
        return dropInsight()
    }

    /// "Hide insights like this": this kind never shows again.
    public func hide(_ insight: Insight) -> HomeSnapshot? {
        insightHistory.update { $0.hide(insight.kind) }
        return dropInsight()
    }

    /// The cached snapshot without its insight, so the card can collapse
    /// before the next refresh (which agrees).
    private func dropInsight() -> HomeSnapshot? {
        cachedSnapshot = cachedSnapshot?.replacingInsight(nil)
        // Saved too, so the dismissed insight isn't restored next launch.
        if let cachedSnapshot { store?.save(cachedSnapshot) }
        return cachedSnapshot
    }

    /// Yields when Health data behind Home changes (`HKObserverQuery`).
    public func changes() async -> AsyncStream<Void> {
        await provider.sampleChanges()
    }

    private func load(profile: UserProfileSnapshot) async -> HomeSnapshot {
        let now = clock()
        guard await provider.isHealthDataAvailable else {
            return HomeSnapshotBuilder.placeholder(.healthDataUnavailable, profile: profile, now: now, timeZone: timeZone)
        }
        guard await provider.authorizationStatus() == .authorized else {
            return HomeSnapshotBuilder.placeholder(.permissionRequired, profile: profile, now: now, timeZone: timeZone)
        }
        // Reach back 18 hours more so the oldest night is seen whole.
        let start = now.addingTimeInterval(-Double(Self.historyDays) * 86_400 - 18 * 3600)
        do {
            async let sleep = provider.fetchSleepSamples(from: start, to: now)
            async let hrv = provider.fetchHRVSamples(from: start, to: now)
            async let resting = provider.fetchRestingHeartRate(from: start, to: now)
            async let heartRate = provider.fetchHeartRateSamples(from: now.addingTimeInterval(-2 * 86_400), to: now)
            let inputs = try await HomeHealthInputs(sleep: sleep, hrv: hrv, restingHeartRate: resting, heartRate: heartRate)
            return HomeSnapshotBuilder.build(inputs, profile: profile, now: now, timeZone: timeZone, insightHistory: insightHistory.history)
        } catch HealthProviderError.unauthorized {
            return HomeSnapshotBuilder.placeholder(.permissionRequired, profile: profile, now: now, timeZone: timeZone)
        } catch {
            return HomeSnapshotBuilder.placeholder(.failed, profile: profile, now: now, timeZone: timeZone)
        }
    }
}
