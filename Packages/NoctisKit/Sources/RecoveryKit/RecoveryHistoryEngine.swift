import Foundation
import SleepKit

/// The constants behind Recovery's history: one place, so changing how a
/// trend or a usual range is judged means editing here and its tests.
public enum RecoveryHistoryModel {
    public static let version = "recovery-history-v1"
    /// A trend needs this many scored days in the window.
    public static let trendMinimumDays = 5
    /// A slope of at least this many points a week is "Rising"; of at most
    /// its negative, "Lower".
    public static let trendPointsPerWeek: Double = 1.5
    /// The spread the usual range is drawn with never goes below this many
    /// points, so a very steady fortnight can't make a one-point change
    /// look unusual (the same idea as `RecoveryNormalRange`'s floors).
    public static let scoreSpreadFloor: Double = 3
    /// A chart never draws more than this many points.
    public static let maximumChartPoints = 120
}

/// The ranges Recovery's history shows, in nights ending on the newest.
public enum RecoveryHistoryRange: Int, Sendable, CaseIterable, Hashable, Codable {
    case week = 7
    case month = 30
    case quarter = 90

    public var nights: Int { rawValue }
}

/// One night's recovery score, as it was on its own morning.
public struct RecoveryDayScore: Sendable, Equatable, Codable {
    public struct FactorScore: Sendable, Equatable, Codable {
        public let kind: RecoveryFactorKind
        /// 0...100.
        public let score: Int

        public init(kind: RecoveryFactorKind, score: Int) {
            self.kind = kind
            self.score = score
        }
    }

    public let night: SleepNightKey
    /// When the night ended: the morning the score belongs to.
    public let date: Date
    /// 0...100.
    public let score: Int
    public let confidence: RecoveryConfidence
    /// The factors that made it up, in factor order.
    public let factorScores: [FactorScore]
    /// V3's heart-signal cap held the score down that morning.
    public let capApplied: Bool
    /// How long the night's sleep was, for a chart's pill.
    public let asleepMinutes: Double

    public init(
        night: SleepNightKey, date: Date, score: Int, confidence: RecoveryConfidence, factorScores: [FactorScore], capApplied: Bool,
        asleepMinutes: Double = 0
    ) {
        self.asleepMinutes = asleepMinutes
        self.night = night
        self.date = date
        self.score = score
        self.confidence = confidence
        self.factorScores = factorScores
        self.capApplied = capApplied
    }

    public func factorScore(_ kind: RecoveryFactorKind) -> Int? {
        factorScores.first { $0.kind == kind }?.score
    }
}

public enum RecoveryTrendDirection: String, Sendable, Equatable, Codable {
    case rising
    case steady
    case lower
}

/// The least-squares slope of the window's scores, in points a week, and
/// what it says.
public struct RecoveryHistoryTrend: Sendable, Equatable, Codable {
    public let direction: RecoveryTrendDirection
    public let pointsPerWeek: Double

    public init(direction: RecoveryTrendDirection, pointsPerWeek: Double) {
        self.direction = direction
        self.pointsPerWeek = pointsPerWeek
    }
}

public struct RecoveryExtreme: Sendable, Equatable, Codable {
    public let score: Int
    public let night: SleepNightKey
    public let date: Date

    public init(score: Int, night: SleepNightKey, date: Date) {
        self.score = score
        self.night = night
        self.date = date
    }
}

/// What a window of recovery scores adds up to.
public struct RecoveryHistoryStats: Sendable, Equatable, Codable {
    /// The newest scored night in the window.
    public let current: RecoveryDayScore?
    /// Mean of the window's scores.
    public let average: Double?
    /// Your recovery baseline: the mean (and spread) of the 14 nights
    /// before the newest one, each scored as its own morning. Nil under 5
    /// nights.
    public let baseline: Baseline?
    /// Your usual range: the baseline ± 1 SD (spread never under
    /// `RecoveryHistoryModel.scoreSpreadFloor`); nil without a baseline.
    public let usualRange: ClosedRange<Double>?
    /// Scored days in the window inside `usualRange`; nil without one.
    public let daysInUsualRange: Int?
    /// Ties go to the later night.
    public let high: RecoveryExtreme?
    public let low: RecoveryExtreme?
    /// Nil under `RecoveryHistoryModel.trendMinimumDays` scored days.
    public let trend: RecoveryHistoryTrend?
    public let scoredDays: Int

    public init(
        current: RecoveryDayScore?, average: Double?, baseline: Baseline?, usualRange: ClosedRange<Double>?, daysInUsualRange: Int?,
        high: RecoveryExtreme?, low: RecoveryExtreme?, trend: RecoveryHistoryTrend?, scoredDays: Int
    ) {
        self.current = current
        self.average = average
        self.baseline = baseline
        self.usualRange = usualRange
        self.daysInUsualRange = daysInUsualRange
        self.high = high
        self.low = low
        self.trend = trend
        self.scoredDays = scoredDays
    }
}

/// One calendar night of a window: its score, or nil where none exists.
public struct RecoveryHistoryDay: Sendable, Equatable, Codable {
    public let night: SleepNightKey
    public let score: RecoveryDayScore?

    public init(night: SleepNightKey, score: RecoveryDayScore?) {
        self.night = night
        self.score = score
    }
}

public struct RecoveryHistory: Sendable, Equatable, Codable {
    public let range: RecoveryHistoryRange
    /// The calendar nights from the range's first (or, with a shorter
    /// history, the first scored one) to the last, oldest first.
    public let days: [RecoveryHistoryDay]
    public let stats: RecoveryHistoryStats

    public init(range: RecoveryHistoryRange, days: [RecoveryHistoryDay], stats: RecoveryHistoryStats) {
        self.range = range
        self.days = days
        self.stats = stats
    }

    /// The scored days, oldest first.
    public var series: [RecoveryDayScore] { days.compactMap(\.score) }
    /// Nights the chart spans: fewer than `range.nights` when the history
    /// starts inside the range.
    public var spanNights: Int { days.count }
    /// The history starts inside the range: draw what exists.
    public var isPartial: Bool { days.count < range.nights }
}

/// One daily recovery score per complete night, and what a window of them
/// adds up to. Deterministic; time comes in as `now`.
///
/// Each night is scored exactly as its own morning was: its baselines are
/// built from the nights before it only (`BaselineEngine.window`), and a
/// night from while the person was still learning (under 5 nights up to
/// and including it) has no score. So adding later nights never changes an
/// earlier night's score.
public enum RecoveryHistoryEngine {
    /// Every scored night ending by `now`, oldest first.
    public static func scores(history: [NightMetrics], needMinutes: Double, asOf now: Date, model: RecoveryModel = .current) -> [RecoveryDayScore] {
        let complete = history.filter { $0.wakeTime <= now }
        let unique = Dictionary(complete.map { ($0.night, $0) }, uniquingKeysWith: { first, _ in first })
        return unique.values.sorted { $0.night < $1.night }.compactMap { night in
            guard let result = RecoveryEngine.scoreResultAsOfThatMorning(night, complete: complete, needMinutes: needMinutes, model: model) else { return nil }
            return RecoveryDayScore(
                night: night.night,
                date: night.wakeTime,
                score: result.score,
                confidence: result.confidence,
                factorScores: RecoveryFactorKind.allCases.compactMap { kind in
                    result.factor(kind).map { RecoveryDayScore.FactorScore(kind: kind, score: $0.score) }
                },
                capApplied: result.heartCapApplied,
                asleepMinutes: night.asleepMinutes
            )
        }
    }

    /// The window of `range` nights ending on `night` (the newest scored
    /// night by default) with its stats. `scores` is every scored night,
    /// oldest first (`scores(history:…)`).
    public static func history(scores: [RecoveryDayScore], range: RecoveryHistoryRange, endingAt night: SleepNightKey? = nil) -> RecoveryHistory {
        let ordered = scores.sorted { $0.night < $1.night }
        guard let end = night ?? ordered.last?.night else {
            return RecoveryHistory(range: range, days: [], stats: emptyStats)
        }
        let start = end.adding(days: -(range.nights - 1))
        let inWindow = ordered.filter { $0.night >= start && $0.night <= end }
        let byNight = Dictionary(inWindow.map { ($0.night, $0) }, uniquingKeysWith: { first, _ in first })
        // A history that starts inside the range: draw from its first score.
        let first = inWindow.first?.night ?? end
        let spanStart = max(first, start)
        let count = end.days(from: spanStart) + 1
        let days = (0..<max(count, 0)).map { offset -> RecoveryHistoryDay in
            let key = spanStart.adding(days: offset)
            return RecoveryHistoryDay(night: key, score: byNight[key])
        }
        return RecoveryHistory(range: range, days: days, stats: stats(window: inWindow, all: ordered, end: end))
    }

    // MARK: - Stats

    static let emptyStats = RecoveryHistoryStats(
        current: nil, average: nil, baseline: nil, usualRange: nil, daysInUsualRange: nil, high: nil, low: nil, trend: nil, scoredDays: 0
    )

    static func stats(window: [RecoveryDayScore], all: [RecoveryDayScore], end: SleepNightKey) -> RecoveryHistoryStats {
        guard let newest = window.last else { return emptyStats }
        let average = Double(window.reduce(0) { $0 + $1.score }) / Double(window.count)
        // The 14 nights before the newest one, as the rest of Recovery counts them.
        let windowStart = newest.night.adding(days: -BaselineEngine.windowNights)
        let baseline = BaselineEngine.baseline(all.filter { $0.night >= windowStart && $0.night < newest.night }.map { Double($0.score) })
        var usual: ClosedRange<Double>?
        var within: Int?
        if let baseline {
            let spread = max(baseline.standardDeviation, RecoveryHistoryModel.scoreSpreadFloor)
            let range = (baseline.value - spread)...(baseline.value + spread)
            usual = range
            within = window.filter { range.contains(Double($0.score)) }.count
        }
        func extreme(_ day: RecoveryDayScore) -> RecoveryExtreme { RecoveryExtreme(score: day.score, night: day.night, date: day.date) }
        // Later nights win ties: `max`/`min` keep the first, so walk newest first.
        let newestFirst = window.reversed()
        let high = newestFirst.max { $0.score < $1.score }.map(extreme)
        let low = newestFirst.min { $0.score < $1.score }.map(extreme)
        let firstNight = window[0].night
        let points = window.map { (day: $0.night.days(from: firstNight), score: Double($0.score)) }
        return RecoveryHistoryStats(
            current: newest, average: average, baseline: baseline, usualRange: usual, daysInUsualRange: within,
            high: high, low: low, trend: trend(points: points), scoredDays: window.count
        )
    }

    // MARK: - Trend

    /// The least-squares slope of `score` over `day`, in points a week;
    /// nil under `trendMinimumDays` points or when every point is on one
    /// day.
    public static func slopePerWeek(points: [(day: Int, score: Double)]) -> Double? {
        guard points.count >= RecoveryHistoryModel.trendMinimumDays else { return nil }
        let n = Double(points.count)
        let meanX = points.reduce(0) { $0 + Double($1.day) } / n
        let meanY = points.reduce(0) { $0 + $1.score } / n
        let sxx = points.reduce(0) { $0 + (Double($1.day) - meanX) * (Double($1.day) - meanX) }
        guard sxx > 0 else { return nil }
        let sxy = points.reduce(0) { $0 + (Double($1.day) - meanX) * ($1.score - meanY) }
        return sxy / sxx * 7
    }

    public static func trend(points: [(day: Int, score: Double)]) -> RecoveryHistoryTrend? {
        slopePerWeek(points: points).map { trend(pointsPerWeek: $0) }
    }

    /// Rising at +1.5 a week or more, Lower at −1.5 or less, otherwise
    /// Steady. The slope is compared to two decimals, so a slope that is
    /// 1.5 to the eye is 1.5 to the rule.
    public static func trend(pointsPerWeek slope: Double) -> RecoveryHistoryTrend {
        let rounded = (slope * 100).rounded() / 100
        let direction: RecoveryTrendDirection
        if rounded >= RecoveryHistoryModel.trendPointsPerWeek {
            direction = .rising
        } else if rounded <= -RecoveryHistoryModel.trendPointsPerWeek {
            direction = .lower
        } else {
            direction = .steady
        }
        return RecoveryHistoryTrend(direction: direction, pointsPerWeek: slope)
    }
}
