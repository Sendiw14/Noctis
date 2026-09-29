import DesignSystem
import Foundation
import HomeFeature
import NoctisCore
import RecoveryKit
import SleepKit

// Recovery over 7, 30 or 90 nights: the words around the line, the stat
// tiles and the factor rows. Built by `RecoveryScreenBuilder` from the
// snapshot's history and the render model's geometry; views lay it out and
// add nothing (APP_RULES.md R18, R20). A trend is a direction, never a
// judgment: nothing is colored as a warning.

/// Where a day's score sits against the person's usual range: the score
/// dots' color (sage above, butter within, orange below), always with the
/// number in the pill.
public nonisolated enum RecoveryUsualPosition: Sendable, Equatable, Hashable {
    case above
    case within
    case below

    public init(score: Int, usual: ClosedRange<Double>) {
        let value = Double(score)
        self = value > usual.upperBound ? .above : value < usual.lowerBound ? .below : .within
    }

    public var word: String {
        switch self {
        case .above: "Above"
        case .within: "Within"
        case .below: "Below"
        }
    }
}

public nonisolated struct RecoveryHistoryPointContent: Sendable, Equatable {
    public let night: SleepNightKey
    /// Against the usual range; nil for a day with no score or no baseline.
    public let position: RecoveryUsualPosition?
    /// The pill: "Tue · Recovery 76 · Sleep 7h 12m", or "Tue · No score".
    public let detail: String
    public let accessibilityLabel: String
}

public nonisolated struct RecoveryHistoryTile: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let value: NoctisMetricValue
    /// A caption under the value: a date, or a direction ("Rising").
    public let note: String?
    /// An SF Symbol beside the note (the trend's arrow).
    public let symbol: String?
    public let accessibilityLabel: String
}

/// A factor over the same range: its average and a small line; opens that
/// factor's page.
public nonisolated struct RecoveryHistoryFactorRow: Sendable, Equatable, Identifiable {
    public let kind: RecoveryFactorKind
    public let name: String
    /// The mean over the range's nights with a value ("68 ms"); nil with none.
    public let average: NoctisMetricValue?
    /// The range the factor page opens on.
    public let factorRange: RecoveryFactorRange
    public let accessibilityLabel: String

    public var id: RecoveryFactorKind { kind }
}

public nonisolated struct RecoveryHistoryContent: Sendable, Equatable {
    public let range: RecoveryHistoryRange
    /// "SEP 23 – SEP 29".
    public let caption: String
    /// One per day of the chart, oldest first.
    public let points: [RecoveryHistoryPointContent]
    /// The score axis, from the top: 100, 75, 50, 25, 0.
    public let yLabels: [RecoveryAxisLabel]
    /// Under the chart: a weekday initial a day for 7D, dates otherwise.
    public let xLabels: [RecoveryAxisLabel]
    /// Whether each day gets a dot (7D).
    public let showsDots: Bool
    /// Whether the line is the smoothed one with weekly averages (90D).
    public let isSmoothed: Bool
    /// "Showing 12 nights" when the history is shorter than the range.
    public let partialNote: String?
    /// "The shaded band is your usual range: 82 – 94." nil without a baseline.
    public let bandCaption: String?
    public let tiles: [RecoveryHistoryTile]
    /// "In your usual range on 11 of 14 days."
    public let usualLine: String?
    public let factorRows: [RecoveryHistoryFactorRow]
    public let accessibilityLabel: String
}

nonisolated extension RecoveryScreenBuilder {
    /// A history segment's content; nil under 5 scored days (the learning
    /// state takes over) or without a history.
    static func historyContent(_ snapshot: RecoverySnapshot, segment: RecoverySegment, format: HomeFormat) -> RecoveryHistoryContent? {
        guard let range = segment.historyRange, let history = snapshot.history(range),
              history.stats.scoredDays >= RecoveryHistoryModel.trendMinimumDays else { return nil }
        let days = history.days
        let first = days.first.map { format.monthDay($0.night.adding(days: 1)) } ?? ""
        let last = days.last.map { format.monthDay($0.night.adding(days: 1)) } ?? ""

        let points = days.map { day -> RecoveryHistoryPointContent in
            let wake = day.night.adding(days: 1)
            let name = range == .week ? format.weekday(wake, width: .abbreviated) : format.weekdayMonthDay(wake)
            guard let score = day.score else {
                return RecoveryHistoryPointContent(night: day.night, position: nil, detail: "\(name) · No score", accessibilityLabel: "\(format.wideDate(wake)), no score")
            }
            let sleep = HomeFormat.compactDuration(Int(score.asleepMinutes.rounded()))
            let position = history.stats.usualRange.map { RecoveryUsualPosition(score: score.score, usual: $0) }
            return RecoveryHistoryPointContent(
                night: day.night,
                position: position,
                detail: "\(name) · Recovery \(score.score) · Sleep \(sleep)",
                accessibilityLabel: "\(format.wideDate(wake)), recovery \(score.score), slept \(HomeFormat.spokenDuration(Int(score.asleepMinutes.rounded())))"
            )
        }
        let yLabels = [100, 75, 50, 25, 0].map { RecoveryAxisLabel(position: 1 - Double($0) / 100, text: "\($0)") }
        let count = Double(max(days.count, 1))
        var xLabels: [RecoveryAxisLabel] = []
        if range == .week {
            xLabels = days.enumerated().map { index, day in
                RecoveryAxisLabel(position: (Double(index) + 0.5) / count, text: format.weekday(day.night.adding(days: 1), width: .narrow))
            }
        } else if !days.isEmpty {
            for index in [0, days.count / 2, days.count - 1] {
                xLabels.append(RecoveryAxisLabel(position: (Double(index) + 0.5) / count, text: format.monthDay(days[index].night.adding(days: 1))))
            }
        }
        var band: String?
        if let usual = history.stats.usualRange {
            band = "The shaded band is your usual range: \(Int(usual.lowerBound.rounded())) – \(Int(usual.upperBound.rounded()))."
        }
        var usualLine: String?
        if let within = history.stats.daysInUsualRange {
            let total = history.stats.scoredDays
            usualLine = "In your usual range on \(within) of \(total) \(total == 1 ? "day" : "days")."
        }
        let tiles = historyTiles(history.stats, format: format)
        let rows = RecoveryContributionEngine.factorOrder.compactMap { historyRow($0, segment: segment, snapshot: snapshot, format: format) }
        var label = "Recovery over \(range.nights) nights, \(first) to \(last)."
        if let average = history.stats.average { label += " Average \(Int(average.rounded()))." }
        if let usualLine { label += " " + usualLine }
        if let trend = history.stats.trend { label += " " + trendWords(trend) + "." }
        return RecoveryHistoryContent(
            range: range,
            caption: "\(first) – \(last)".uppercased(),
            points: points,
            yLabels: yLabels,
            xLabels: xLabels,
            showsDots: range == .week,
            isSmoothed: range == .quarter,
            partialNote: history.isPartial ? "Showing \(history.spanNights) \(history.spanNights == 1 ? "night" : "nights")" : nil,
            bandCaption: band,
            tiles: tiles,
            usualLine: usualLine,
            factorRows: rows,
            accessibilityLabel: label
        )
    }

    // MARK: Stats

    /// Current, Average, Baseline, High, Low and Trend; a tile with no value
    /// isn't made.
    static func historyTiles(_ stats: RecoveryHistoryStats, format: HomeFormat) -> [RecoveryHistoryTile] {
        func number(_ value: Int) -> NoctisMetricValue { NoctisMetricValue(parts: [.number("\(value)")], spoken: "\(value)") }
        func dated(_ date: Date) -> String { format.shortDate(date) }
        var tiles: [RecoveryHistoryTile] = []
        if let current = stats.current {
            tiles.append(RecoveryHistoryTile(
                id: "current", title: "Current", value: number(current.score), note: dated(current.date), symbol: nil,
                accessibilityLabel: "Current \(current.score)"
            ))
        }
        if let average = stats.average {
            let value = Int(average.rounded())
            tiles.append(RecoveryHistoryTile(
                id: "average", title: "Average", value: number(value), note: "\(stats.scoredDays) \(stats.scoredDays == 1 ? "night" : "nights")", symbol: nil,
                accessibilityLabel: "Average \(value)"
            ))
        }
        if let baseline = stats.baseline {
            let value = Int(baseline.value.rounded())
            tiles.append(RecoveryHistoryTile(
                id: "baseline", title: "Baseline", value: number(value), note: "last \(baseline.nights) nights", symbol: nil,
                accessibilityLabel: "Baseline \(value)"
            ))
        }
        if let high = stats.high {
            tiles.append(RecoveryHistoryTile(
                id: "high", title: "High", value: number(high.score), note: dated(high.date), symbol: nil,
                accessibilityLabel: "High \(high.score), \(format.longDate(high.date))"
            ))
        }
        if let low = stats.low {
            tiles.append(RecoveryHistoryTile(
                id: "low", title: "Low", value: number(low.score), note: dated(low.date), symbol: nil,
                accessibilityLabel: "Low \(low.score), \(format.longDate(low.date))"
            ))
        }
        if let trend = stats.trend {
            let slope = signedSlope(trend.pointsPerWeek)
            let direction: String
            let symbol: String
            switch trend.direction {
            case .rising: (direction, symbol) = ("Rising", "arrow.up.right")
            case .steady: (direction, symbol) = ("Steady", "arrow.right")
            case .lower: (direction, symbol) = ("Lower than earlier", "arrow.down.right")
            }
            tiles.append(RecoveryHistoryTile(
                id: "trend", title: "Trend",
                value: NoctisMetricValue(parts: [.number(slope), .space, .unit("/ wk")], spoken: "\(slope) points a week"),
                note: direction, symbol: symbol, accessibilityLabel: trendWords(trend)
            ))
        }
        return tiles
    }

    /// "+2.1", "−0.4" (a real minus sign), "0.0".
    static func signedSlope(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        let text = String(format: "%.1f", abs(rounded))
        if rounded > 0 { return "+\(text)" }
        if rounded < 0 { return "\u{2212}\(text)" }
        return text
    }

    static func trendWords(_ trend: RecoveryHistoryTrend) -> String {
        let direction = switch trend.direction {
        case .rising: "Rising"
        case .steady: "Steady"
        case .lower: "Lower than earlier"
        }
        return "Trend: \(direction), \(signedSlope(trend.pointsPerWeek).replacingOccurrences(of: "\u{2212}", with: "minus ")) points a week"
    }

    // MARK: Factor rows

    static func historyRow(_ kind: RecoveryFactorKind, segment: RecoverySegment, snapshot: RecoverySnapshot, format: HomeFormat) -> RecoveryHistoryFactorRow? {
        let factorRange = segment.factorRange
        guard let series = snapshot.series(kind, factorRange) else { return nil }
        // 7D is the last 7 nights of the 14-night series.
        let points = segment == .week ? Array(series.points.suffix(7)) : series.points
        let values = points.compactMap(\.value)
        let name = HomeScreenBuilder.shortName(kind)
        guard !values.isEmpty else {
            return RecoveryHistoryFactorRow(kind: kind, name: name, average: nil, factorRange: factorRange, accessibilityLabel: "\(name), nothing recorded in these nights")
        }
        let mean = values.reduce(0, +) / Double(values.count)
        let metric = valueMetric(kind, mean, format: format)
        return RecoveryHistoryFactorRow(
            kind: kind, name: name, average: metric, factorRange: factorRange,
            accessibilityLabel: "\(name), average \(spokenValue(kind, mean, format: format))"
        )
    }
}
