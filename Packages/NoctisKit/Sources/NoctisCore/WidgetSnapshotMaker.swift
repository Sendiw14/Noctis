import Foundation
import NightKit
import NoctisWidgetKit
import RecoveryKit
import SleepKit

/// Turns what Home knows into the small `WidgetSnapshot` widgets draw (APP_RULES.md R44). Pure: no I/O and no clock, so every
/// rule is a unit test. It copies derived numbers and clock times only; it never reaches for a sample, a source name, the Journal
/// or anything Coach said, and the snapshot has no place to put them.
public nonisolated enum WidgetSnapshotMaker {
    /// The snapshot for `home`, or nil when there is nothing true to say (a failed read leaves the last snapshot as it was).
    public static func make(
        home: HomeSnapshot, profile: UserProfileSnapshot, bedtime: BedtimeRecommendation?, alarm: WidgetAlarm?, now: Date, calendar: Calendar,
        dataEpoch: Int64 = 0
    ) -> WidgetSnapshot? {
        guard let state = state(of: home, now: now) else { return nil }

        var plan = WidgetPlan(wakeMinutes: profile.typicalWakeMinutes, needMinutes: profile.needMinutes, bedtimeMinutes: home.tonight.bedtimeMinutes)
        if let bedtime {
            plan.bedtimeMinutes = bedtime.centerMinutes
            plan.windowStartMinutes = bedtime.window?.startMinutes
            plan.windowEndMinutes = bedtime.window?.endMinutes
        }

        var recovery: WidgetRecovery?
        var factors: WidgetFactors?
        var recoveryFactors: [WidgetRecoveryFactor] = []
        var nightsOfHistory = 0
        if state.showsScore, case .scored(let result)? = home.recovery {
            recovery = WidgetRecovery(
                score: min(max(result.score, 0), 100), delta: result.comparison.delta, confidence: confidence(result.confidence),
                ring: home.render.ring.compactMap { arc in factorKind(arc.kind).map { WidgetRingSegment(kind: $0, weight: arc.weight, fraction: arc.fraction) } }
            )
            let heart = WidgetFactors(
                hrv: result.factor(.hrv).map { Int($0.value.rounded()) }, restingHeartRate: result.factor(.restingHeartRate).map { Int($0.value.rounded()) }
            )
            factors = heart.isEmpty ? nil : heart
            // The four factors the iPhone scored, in ring order, for the Watch: only those that exist.
            recoveryFactors = WidgetFactorKind.allCases.compactMap { kind in
                result.factors.first { factorKind($0.kind) == kind }.map {
                    WidgetRecoveryFactor(kind: kind, score: $0.score, value: $0.value, baseline: $0.baseline, range: range($0.range))
                }
            }
            nightsOfHistory = result.baselineNights
        }

        // Last night, or on a stale snapshot the newest night on record (it is labelled as old, never as last night).
        var session = home.lastNight
        if case .stale = state { session = session ?? home.latestSleep }
        let night = session.map { night(of: $0, quality: home.lastNightSleepQuality, calendar: calendar) }

        // The day the numbers are for: the morning the night ended; with no night, the day it was made for.
        var forDay = WidgetDay.today(at: now, calendar: calendar)
        if let session, !isStale(state) {
            var zoned = calendar
            zoned.timeZone = session.timeZone
            forDay = WidgetDay(session.wakeTime, calendar: zoned)
        }

        return WidgetSnapshot(
            forDay: forDay, generatedAt: now, plan: plan, state: state, recovery: recovery, lastNight: night, factors: factors, alarm: alarm,
            recoveryFactors: recoveryFactors, nightsOfHistory: nightsOfHistory, dataEpoch: dataEpoch
        )
    }

    /// The widgets' word for Home's data state; nil for a failed read.
    public static func state(of home: HomeSnapshot, now: Date) -> WidgetDataState? {
        switch home.dataState {
        case .failed: return nil
        case .healthDataUnavailable, .empty: return .empty
        case .permissionRequired: return .noPermission
        case .stale(let newest): return .stale(hours: max(Int(now.timeIntervalSince(newest) / 3600), 0))
        case .learning(let nights): return .learning(nightsSoFar: nights)
        case .noSleepLastNight: return .gap
        case .ready:
            guard case .scored(let result)? = home.recovery else { return .gap }
            let heart = result.factor(.hrv) != nil || result.factor(.restingHeartRate) != nil
            return heart ? .full : .sleepOnly
        }
    }

    static func isStale(_ state: WidgetDataState) -> Bool {
        if case .stale = state { true } else { false }
    }

    static func night(of session: SleepSession, quality: Int?, calendar: Calendar) -> WidgetNight {
        var zoned = calendar
        zoned.timeZone = session.timeZone
        func minutes(_ date: Date) -> Int {
            let clock = zoned.dateComponents([.hour, .minute], from: date)
            return (clock.hour ?? 0) * 60 + (clock.minute ?? 0)
        }
        var stages: WidgetStages?
        if session.completeness.hasStageDetail {
            let totals = NightStageMinutes(session.totals)
            stages = WidgetStages(deep: Int(totals.deep.rounded()), core: Int(totals.core.rounded()), rem: Int(totals.rem.rounded()))
        }
        return WidgetNight(
            asleepMinutes: Int((session.totals.asleep / 60).rounded()), stages: stages, bedtimeMinutes: minutes(session.bedtime),
            wakeMinutes: minutes(session.wakeTime), quality: quality
        )
    }

    static func factorKind(_ kind: RecoveryFactorKind) -> WidgetFactorKind? {
        switch kind {
        case .sleepDuration: .sleepDuration
        case .hrv: .hrv
        case .restingHeartRate: .restingHeartRate
        case .sleepConsistency: .sleepConsistency
        }
    }

    static func range(_ range: RecoveryRange?) -> WidgetFactorRange? {
        switch range {
        case .within?: .within
        case .above?: .above
        case .below?: .below
        case nil: nil
        }
    }

    static func confidence(_ value: RecoveryConfidence) -> WidgetConfidence {
        switch value {
        case .low: .low
        case .moderate: .moderate
        case .high: .high
        }
    }

    /// The alarm's line in the snapshot: the time it rings and whether it is on; nil before one was ever set.
    public static func alarm(_ settings: AlarmSettings?) -> WidgetAlarm? {
        settings.map { WidgetAlarm(minutes: $0.minutesSinceMidnight, isOn: $0.isOn) }
    }
}
