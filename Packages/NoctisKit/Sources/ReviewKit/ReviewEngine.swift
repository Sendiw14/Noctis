import Foundation
import InsightsKit
import RecoveryKit
import SleepAnalysisKit
import SleepKit

// Builds a review from the nights (APP_RULES.md R39, R18). Pure and deterministic: the same nights, the same period and the same clock give the same record. Every number
// is the existing engines' (`BaselineEngine`'s mean and sample standard deviation, `RecoveryHistoryEngine`'s trend, `InsightRanking`'s order) or a median, a count or a
// difference of those. Nothing is invented, padded or carried over: with too few nights the engine says how many it has, and a comparison with the previous period
// is made only when the previous period has enough nights of its own.

public nonisolated enum ReviewModel {
    public static let version = "review-v2"

    /// A change counts as a change, or an improvement, only when it is at least this much of the person's own variation.
    public static let normalizedThreshold = 0.5
    /// The nights before the period whose variation a change is set against.
    public static let priorNights = 28
    /// Values a mean, a deviation or an average needs before it exists (the baselines' own minimum).
    public static let minimumValues = BaselineEngine.minimumNights

    /// The least a metric's own variation is taken to be, so a very steady person is never divided by almost nothing. Minutes, points, ms and bpm.
    public static func floor(_ metric: ReviewMetric) -> Double {
        switch metric {
        case .duration: 15
        case .bedtimeVariation: 10
        case .recovery: RecoveryHistoryModel.scoreSpreadFloor
        case .hrv: 3
        case .restingHeartRate: 1.5
        }
    }

    /// The next-focus thresholds, in the fixed order they are tried.
    public static let bedtimeVariationMinutes = 45.0
    public static let balanceBehindMinutes = 60.0
    public static let laterShiftMinutes = 45.0
    public static let recoveryLowerMinimumNights = 5

    /// The rolling recovery average of a month: 7 mornings, drawn only when 4 of them have a score.
    public static let rollingMornings = 7
    public static let rollingMinimum = 4
}

public nonisolated enum ReviewEngine {
    /// The review of `period`, or how many nights are short. `nights` may hold any nights (the period, the previous period and the 28 before it among them), in any order;
    /// each is used where it belongs. `insights` are the insights NOCTIS found, from which the ones generated inside the period are pointed to.
    public static func build(
        period: ReviewPeriod, nights: [ReviewNightInput], needMinutes: Int, insights: [ReviewInsightInput] = [], now: Date, calendar: Calendar
    ) -> ReviewResult {
        // A night is counted once, whichever source repeated it.
        let unique = Dictionary(nights.map { ($0.night, $0) }, uniquingKeysWith: { first, _ in first }).values.sorted { $0.night < $1.night }
        let inPeriod = unique.filter { period.contains(morning: $0.morning) }
        let need = period.kind.minimumNights
        guard inPeriod.count >= need else { return .notEnoughNights(have: inPeriod.count, need: need) }

        let previousPeriod = period.previous
        let before = unique.filter { previousPeriod.contains(morning: $0.morning) }
        // Everything compared with the previous period needs the previous period to have enough nights of its own.
        let comparable = before.count >= need
        let priorStart = period.firstMorning.adding(days: -ReviewModel.priorNights)
        let prior = unique.filter { $0.morning >= priorStart && $0.morning < period.firstMorning }

        let sleep = sleepSummary(inPeriod, before: comparable ? before : nil, needMinutes: needMinutes)
        let consistency = consistencySummary(inPeriod, before: comparable ? before : nil)
        let recovery = recoverySummary(inPeriod, before: comparable ? before : nil)
        let heart = heartSummary(inPeriod, before: comparable ? before : nil)
        let timing = timingSummary(inPeriod, before: comparable ? before : nil)

        let candidates = comparable ? changes(inPeriod: inPeriod, before: before, prior: prior) : []
        let (improvement, biggest) = highlights(candidates, comparable: comparable, needMinutes: needMinutes)
        let major = comparable ? majorChanges(candidates) : []

        let values = inPeriod.map { night in
            ReviewNightValues(
                morning: night.morning, asleepMinutes: Int(night.asleepMinutes.rounded()), stages: night.stages,
                bedtimeMinutes: Int(night.bedtimeMinutes.rounded()),
                wakeMinutes: Int(night.wakeMinutes.rounded()), recoveryScore: night.recoveryScore
            )
        }

        let record = ReviewRecord(
            id: period.id, firstMorning: period.firstMorning, lastMorning: period.lastMorning, generatedAt: now, nightsRecorded: inPeriod.count,
            nightsInPeriod: period.morningCount, hasComparison: comparable, sleep: sleep, consistency: consistency, recovery: recovery, heart: heart,
            timing: timing,
            nights: values, biggestImprovement: improvement, biggestChange: biggest, topChanges: major,
            topInsightIDs: topInsights(insights, period: period, calendar: calendar),
            nextFocus: focus(period: period, inPeriod: inPeriod, consistency: consistency, timing: timing, recovery: recovery, needMinutes: needMinutes),
            monthly: period.kind == .monthly ? monthlyExtras(inPeriod) : nil
        )
        return .record(record)
    }

    // MARK: Sections

    private static func sleepSummary(_ nights: [ReviewNightInput], before: [ReviewNightInput]?, needMinutes: Int) -> ReviewSleep {
        let asleep = nights.map(\.asleepMinutes)
        let average = BaselineEngine.baseline(asleep)?.value ?? asleep.reduce(0, +) / Double(asleep.count)
        let previous = before.flatMap { BaselineEngine.baseline($0.map(\.asleepMinutes))?.value }
        return ReviewSleep(
            averageMinutes: average, nightsReachedNeed: asleep.filter { $0 >= Double(needMinutes) }.count, needMinutes: needMinutes,
            deltaMinutes: previous.map { average - $0 }
        )
    }

    private static func consistencySummary(_ nights: [ReviewNightInput], before: [ReviewNightInput]?) -> ReviewConsistency {
        let bedtime = BaselineEngine.baseline(nights.map(\.bedtimeMinutes))?.standardDeviation ?? 0
        let wake = BaselineEngine.baseline(nights.map(\.wakeMinutes))?.standardDeviation ?? 0
        let previousBedtime = before.flatMap { BaselineEngine.baseline($0.map(\.bedtimeMinutes))?.standardDeviation }
        let previousWake = before.flatMap { BaselineEngine.baseline($0.map(\.wakeMinutes))?.standardDeviation }
        return ReviewConsistency(
            bedtimeSD: bedtime, wakeSD: wake, bedtimeSDDelta: previousBedtime.map { bedtime - $0 }, wakeSDDelta: previousWake.map { wake - $0 })
    }

    private static func recoverySummary(_ nights: [ReviewNightInput], before: [ReviewNightInput]?) -> ReviewRecovery? {
        let scored = nights.compactMap { night in night.recoveryScore.map { (morning: night.morning, score: $0) } }
        guard scored.count >= ReviewModel.minimumValues, let average = BaselineEngine.baseline(scored.map { Double($0.score) })?.value else { return nil }
        let first = scored[0].morning
        let trend = RecoveryHistoryEngine.trend(points: scored.map { (day: $0.morning.days(from: first), score: Double($0.score)) })
        let previous = before.flatMap { BaselineEngine.baseline($0.compactMap { $0.recoveryScore.map(Double.init) })?.value }
        return ReviewRecovery(
            average: average, scoredNights: scored.count,
            high: extreme(scored.map { (Double($0.score), $0.morning) }, highest: true),
            low: extreme(scored.map { (Double($0.score), $0.morning) }, highest: false),
            trend: trend, delta: previous.map { average - $0 }
        )
    }

    private static func heartSummary(_ nights: [ReviewNightInput], before: [ReviewNightInput]?) -> ReviewHeart {
        func average(_ list: [ReviewNightInput], _ value: (ReviewNightInput) -> Double?) -> Double? { BaselineEngine.baseline(list.compactMap(value))?.value }
        let hrv = average(nights) { $0.hrv }
        let resting = average(nights) { $0.restingHeartRate }
        let previousHRV = before.flatMap { average($0) { $0.hrv } }
        let previousResting = before.flatMap { average($0) { $0.restingHeartRate } }
        return ReviewHeart(
            hrvAverage: hrv, hrvDelta: both(hrv, previousHRV).map { $0 - $1 }, restingHeartRateAverage: resting,
            restingHeartRateDelta: both(resting, previousResting).map { $0 - $1 }
        )
    }

    private static func timingSummary(_ nights: [ReviewNightInput], before: [ReviewNightInput]?) -> ReviewTiming {
        let bedtime = median(nights.map(\.bedtimeMinutes)) ?? 0
        let wake = median(nights.map(\.wakeMinutes)) ?? 0
        let previousBedtime = before.flatMap { median($0.map(\.bedtimeMinutes)) }
        let previousWake = before.flatMap { median($0.map(\.wakeMinutes)) }
        return ReviewTiming(
            medianBedtimeMinutes: bedtime, medianWakeMinutes: wake, bedtimeShift: previousBedtime.map { bedtime - $0 },
            wakeShift: previousWake.map { wake - $0 }
        )
    }

    // MARK: Changes

    /// Every metric that can be compared: it has a value in both periods and the person's own variation over the 28 nights before the period (at least five
    /// nights of it), floored.
    static func changes(inPeriod: [ReviewNightInput], before: [ReviewNightInput], prior: [ReviewNightInput]) -> [ReviewChange] {
        func make(_ metric: ReviewMetric, _ value: Double?, _ previous: Double?, _ nightly: [Double]) -> ReviewChange? {
            guard let value, let previous, let spread = BaselineEngine.baseline(nightly)?.standardDeviation else { return nil }
            return ReviewChange(metric: metric, value: value, previous: previous, normalized: (value - previous) / max(spread, ReviewModel.floor(metric)))
        }
        func mean(_ list: [ReviewNightInput], _ value: (ReviewNightInput) -> Double?) -> Double? { BaselineEngine.baseline(list.compactMap(value))?.value }
        func deviation(_ list: [ReviewNightInput], _ value: (ReviewNightInput) -> Double?) -> Double? {
            BaselineEngine.baseline(list.compactMap(value))?.standardDeviation
        }
        return [
            make(.duration, mean(inPeriod) { $0.asleepMinutes }, mean(before) { $0.asleepMinutes }, prior.map(\.asleepMinutes)),
            make(.bedtimeVariation, deviation(inPeriod) { $0.bedtimeMinutes }, deviation(before) { $0.bedtimeMinutes }, prior.map(\.bedtimeMinutes)),
            make(
                .recovery, mean(inPeriod) { $0.recoveryScore.map(Double.init) }, mean(before) { $0.recoveryScore.map(Double.init) },
                prior.compactMap { $0.recoveryScore.map(Double.init) }),
            make(.hrv, mean(inPeriod) { $0.hrv }, mean(before) { $0.hrv }, prior.compactMap(\.hrv)),
            make(.restingHeartRate, mean(inPeriod) { $0.restingHeartRate }, mean(before) { $0.restingHeartRate }, prior.compactMap(\.restingHeartRate)),
        ].compactMap { $0 }
    }

    /// The rule: a figure to three decimals, so a change that is 0.5 of the person's variation to the eye is 0.5 to the rule.
    static func passes(_ value: Double) -> Bool {
        ((abs(value) * 1000).rounded() / 1000) >= ReviewModel.normalizedThreshold
    }

    /// The changes that count (at least half the person's own variation), the largest first, at most three; equals keep the metrics' own order.
    static func majorChanges(_ candidates: [ReviewChange]) -> [ReviewChange] {
        let counted = candidates.enumerated().filter { passes($0.element.normalized) }
        let ordered = counted.sorted {
            abs($0.element.normalized) != abs($1.element.normalized) ? abs($0.element.normalized) > abs($1.element.normalized) : $0.offset < $1.offset
        }
        return ordered.prefix(3).map(\.element)
    }

    static func highlights(_ candidates: [ReviewChange], comparable: Bool, needMinutes: Int) -> (improvement: ReviewHighlight, biggest: ReviewHighlight) {
        guard comparable, !candidates.isEmpty else { return (.noComparison, .noComparison) }
        // The first of equals wins, in the metrics' own order, so the same nights always say the same thing.
        let biggest = candidates.filter { passes($0.normalized) }.reduce(nil as ReviewChange?) { best, next in
            guard let best else { return next }
            return abs(next.normalized) > abs(best.normalized) ? next : best
        }
        // More sleep is an improvement only while the sleep was below the need: more of a night that already met it is not one.
        let better = candidates.filter { change in
            guard passes(change.goodness), change.goodness > 0 else { return false }
            if change.metric == .duration { return change.previous < Double(needMinutes) }
            return true
        }.reduce(nil as ReviewChange?) { best, next in
            guard let best else { return next }
            return next.goodness > best.goodness ? next : best
        }
        return (better.map(ReviewHighlight.change) ?? .steady, biggest.map(ReviewHighlight.change) ?? .steady)
    }

    // MARK: Next focus

    /// One thing, by a fixed priority: a bedtime that varied by more than 45 minutes, the last 7 nights 60 minutes or more behind the need, a median bedtime 45 minutes or
    /// more later than before, recovery lower over five or more nights. Otherwise keep going.
    static func focus(
        period: ReviewPeriod, inPeriod: [ReviewNightInput], consistency: ReviewConsistency, timing: ReviewTiming, recovery: ReviewRecovery?, needMinutes: Int
    ) -> ReviewFocus {
        if consistency.bedtimeSD > ReviewModel.bedtimeVariationMinutes { return .steadyBedtime(minutes: consistency.bedtimeSD) }
        // The balance of the last 7 nights, as `SleepBalanceEngine` adds it up: it needs the nights of the window the engine needs.
        let lastNight = ReviewPeriod.night(endingOn: period.lastMorning)
        let byNight = Dictionary(inPeriod.map { ($0.night, $0.asleepMinutes) }, uniquingKeysWith: { first, _ in first })
        let window = (0..<SleepBalanceEngine.windowNights).compactMap { byNight[lastNight.adding(days: -$0)] }
        if window.count >= SleepBalanceEngine.minimumNights {
            let balance = window.reduce(0) { $0 + ($1 - Double(needMinutes)) }
            if balance <= -ReviewModel.balanceBehindMinutes { return .sleepNeed(minutesBehind: -balance) }
        }
        if let shift = timing.bedtimeShift, shift >= ReviewModel.laterShiftMinutes { return .gentleShiftBack(minutesLater: shift) }
        if let recovery, recovery.scoredNights >= ReviewModel.recoveryLowerMinimumNights, recovery.trend?.direction == .lower {
            return .recentNights(nights: recovery.scoredNights)
        }
        return .keepGoing
    }

    // MARK: Insights

    static func topInsights(_ insights: [ReviewInsightInput], period: ReviewPeriod, calendar: Calendar) -> [String] {
        var seen: Set<String> = []
        return
            insights
            .filter { period.contains(morning: ReviewPeriod.today($0.generatedAt, calendar: calendar)) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id }
            .filter { seen.insert($0.id).inserted }
            .prefix(period.kind.topInsights)
            .map(\.id)
    }

    // MARK: A month's extras

    static func monthlyExtras(_ nights: [ReviewNightInput]) -> ReviewMonthlyExtras {
        let rolling = nights.compactMap { night -> ReviewRollingPoint? in
            let first = night.morning.adding(days: -(ReviewModel.rollingMornings - 1))
            let scores = nights.filter { $0.morning >= first && $0.morning <= night.morning }.compactMap { $0.recoveryScore.map(Double.init) }
            guard scores.count >= ReviewModel.rollingMinimum else { return nil }
            return ReviewRollingPoint(morning: night.morning, value: scores.reduce(0, +) / Double(scores.count))
        }
        let longest = extreme(nights.map { ($0.asleepMinutes.rounded(), $0.morning) }, highest: true)
        let scored = nights.compactMap { night in night.recoveryScore.map { (Double($0), night.morning) } }
        return ReviewMonthlyExtras(recoveryRolling: rolling, longestNight: longest, highestRecovery: scored.isEmpty ? nil : extreme(scored, highest: true))
    }

    // MARK: Helpers

    /// The highest (or lowest) value, with the latest night that had it and how many others equalled it. `values` is oldest first and not empty.
    static func extreme(_ values: [(Double, SleepNightKey)], highest: Bool) -> ReviewExtreme {
        var best = values[0]
        for candidate in values.dropFirst() where highest ? candidate.0 >= best.0 : candidate.0 <= best.0 { best = candidate }
        return ReviewExtreme(value: best.0, morning: best.1, alsoOn: values.filter { $0.0 == best.0 }.count - 1)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }
}

private nonisolated func both(_ lhs: Double?, _ rhs: Double?) -> (Double, Double)? {
    guard let lhs, let rhs else { return nil }
    return (lhs, rhs)
}
