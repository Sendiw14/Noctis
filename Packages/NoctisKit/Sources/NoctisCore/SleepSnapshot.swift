import Foundation
import HealthProviding
import RecoveryKit
import SleepAnalysisKit
import SleepKit

/// The Sleep tab's three views of the same nights.
public nonisolated enum SleepRange: String, Sendable, CaseIterable, Hashable, Codable {
    case day
    case week
    case month

    public var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        }
    }

    /// How many nights the range shows, ending on the selected night.
    public var nights: Int {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        }
    }
}

/// What the Sleep tab is showing: a night, and how many nights ending on
/// it (`range`). Week and Month end on the selected night.
public nonisolated struct SleepSelection: Sendable, Equatable, Hashable {
    public var night: SleepNightKey
    public var range: SleepRange

    public init(night: SleepNightKey, range: SleepRange = .day) {
        self.night = night
        self.range = range
    }
}

/// One night with everything derived from it.
public nonisolated struct SleepNightRecord: Sendable, Equatable {
    public let session: SleepSession
    public let metrics: SleepMetrics
    public let quality: SleepQualityResult
    /// Heart rate across the night; nil without samples.
    public let heart: NightHeartSeries?

    public var night: SleepNightKey { session.night }

    public init(session: SleepSession, metrics: SleepMetrics, quality: SleepQualityResult, heart: NightHeartSeries?) {
        self.session = session
        self.metrics = metrics
        self.quality = quality
        self.heart = heart
    }
}

/// Everything the Sleep tab shows, derived from Health by
/// `SleepRepository`. Views read this and nothing else (APP_RULES.md R20).
public nonisolated struct SleepSnapshot: Sendable, Equatable {
    /// The same states as Home, in the same order of precedence.
    public let dataState: HomeDataState
    /// Main sleeps, oldest first: the newest `SleepSnapshotBuilder.retainedNights`
    /// nights, enough for the 30-night month and the baselines behind it.
    public let records: [SleepNightRecord]
    public let needMinutes: Int
    public let balance: SleepBalanceResult?
    public let consistency: ConsistencyResult?
    public let timing: SleepTimingResult?
    /// The night that should be "last night" by now, whether or not any
    /// sleep was recorded for it.
    public let anchorNight: SleepNightKey
    public let newestSample: Date?
    public let lastUpdated: Date

    public init(
        dataState: HomeDataState, records: [SleepNightRecord], needMinutes: Int, balance: SleepBalanceResult?,
        consistency: ConsistencyResult?, timing: SleepTimingResult?, anchorNight: SleepNightKey, newestSample: Date?, lastUpdated: Date
    ) {
        self.dataState = dataState
        self.records = records
        self.needMinutes = needMinutes
        self.balance = balance
        self.consistency = consistency
        self.timing = timing
        self.anchorNight = anchorNight
        self.newestSample = newestSample
        self.lastUpdated = lastUpdated
    }

    public func record(_ night: SleepNightKey) -> SleepNightRecord? {
        records.first { $0.night == night }
    }

    /// The `count` calendar nights ending on `night`, oldest first, each
    /// with its record or nil where nothing was recorded.
    public func nights(endingAt night: SleepNightKey, count: Int) -> [(night: SleepNightKey, record: SleepNightRecord?)] {
        let byNight = Dictionary(records.map { ($0.night, $0) }, uniquingKeysWith: { first, _ in first })
        return (0..<count).reversed().map { offset in
            let key = night.adding(days: -offset)
            return (key, byNight[key])
        }
    }

    /// The nights before `night` that its baselines are built from: the 14
    /// calendar nights before it.
    public func window(before night: SleepNightKey) -> [SleepNightRecord] {
        let first = night.adding(days: -BaselineEngine.windowNights)
        return records.filter { $0.night >= first && $0.night < night }
    }

    /// The night Sleep opens on: the newest night with sleep, or the night
    /// that should have been last night when nothing newer was recorded.
    public var defaultNight: SleepNightKey {
        max(records.last?.night ?? anchorNight, anchorNight)
    }

    public var hasStageData: Bool { records.contains { $0.session.completeness.hasStageDetail } }
    public var hasHeartData: Bool { records.contains { $0.heart != nil } }
}

public nonisolated enum SleepSnapshotBuilder {
    /// Nights kept in a snapshot.
    public static let retainedNights = 30

    public static func build(_ inputs: HomeHealthInputs, profile: UserProfileSnapshot, now: Date, timeZone: TimeZone) -> SleepSnapshot {
        let dates = inputs.sleep.map(\.end) + inputs.hrv.map(\.date) + inputs.restingHeartRate.map(\.date) + inputs.heartRate.map(\.date)
        guard let newest = dates.filter({ $0 <= now }).max() else {
            return placeholder(.empty, profile: profile, now: now, timeZone: timeZone)
        }
        let history = SleepSessionEngine.history(from: inputs.sleep, asOf: now, timeZone: timeZone)
        let mains = history.nights
        let need = Double(profile.needMinutes)

        let dataState: HomeDataState
        if now.timeIntervalSince(newest) > HomeSnapshotBuilder.staleAfter {
            dataState = .stale(newestSample: newest)
        } else if mains.count < RecoveryModelV1.learningNights {
            dataState = .learning(nightsSoFar: mains.count)
        } else if history.lastNight(asOf: now, within: RecoveryModelV1.lastNightWindow) == nil {
            dataState = .noSleepLastNight
        } else {
            dataState = .ready
        }

        let qualities = Dictionary(SleepQualityEngine.series(history: mains, needMinutes: need).map { ($0.night, $0) }, uniquingKeysWith: { first, _ in first })
        let records = mains.suffix(retainedNights).compactMap { session -> SleepNightRecord? in
            guard let quality = qualities[session.night] else { return nil }
            return SleepNightRecord(
                session: session,
                metrics: SleepMetricsEngine.metrics(for: session),
                quality: quality,
                heart: HomeSnapshotBuilder.heartSeries(inputs.heartRate, for: session)
            )
        }
        let anchor = HomeSnapshotBuilder.expectedLastNight(now: now, timeZone: timeZone, wakeMinutes: profile.typicalWakeMinutes)
        return SleepSnapshot(
            dataState: dataState,
            records: records,
            needMinutes: profile.needMinutes,
            balance: SleepBalanceEngine.balance(history: mains, needMinutes: need),
            consistency: ConsistencyEngine.consistency(history: mains),
            timing: SleepTimingEngine.timing(history: mains),
            anchorNight: anchor,
            newestSample: newest,
            lastUpdated: now
        )
    }

    /// A snapshot with no Health data in it.
    public static func placeholder(_ state: HomeDataState, profile: UserProfileSnapshot, now: Date, timeZone: TimeZone) -> SleepSnapshot {
        SleepSnapshot(
            dataState: state, records: [], needMinutes: profile.needMinutes, balance: nil, consistency: nil, timing: nil,
            anchorNight: HomeSnapshotBuilder.expectedLastNight(now: now, timeZone: timeZone, wakeMinutes: profile.typicalWakeMinutes),
            newestSample: nil, lastUpdated: now
        )
    }
}
