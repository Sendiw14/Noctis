import DesignSystem
import Foundation
import HomeFeature
import NoctisCore
import RecoveryKit
import SleepKit
import NoctisText

// A factor's detail page: the words around its chart. Built by
// `RecoveryScreenBuilder` from the snapshot's series and the render model's
// geometry; views lay it out and add nothing (APP_RULES.md R18, R20).

public nonisolated struct RecoveryFactorPointContent: Sendable, Equatable {
    public let night: SleepNightKey
    /// The pill: "Tue · 48 ms · Score 82", or "Tue · No data".
    public let detail: String
    public let accessibilityLabel: String
}

/// A label on an axis: where along it (0 = top or leading, 1 = bottom or
/// trailing) and what it says.
public nonisolated struct RecoveryAxisLabel: Sendable, Equatable {
    public let position: Double
    public let text: String
}

public nonisolated struct RecoveryFactorTile: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let value: NoctisMetricValue
    /// A small caption under the value ("vs usual: −1").
    public let note: String?
}

public nonisolated struct RecoveryExplanationBlock: Sendable, Equatable {
    public let title: String
    public let text: String
}

public nonisolated struct RecoveryFactorContent: Sendable, Equatable {
    public let kind: RecoveryFactorKind
    /// "HRV".
    public let name: String
    public let range: RecoveryFactorRange
    /// Today's value, its suffix ("off" for consistency), the baseline and
    /// the one sentence: Home's wording for the factor.
    public let value: NoctisMetricValue
    public let valueSuffix: String?
    public let baseline: String
    public let sentence: String
    /// One per night in the chart, oldest first.
    public let points: [RecoveryFactorPointContent]
    /// Down the chart, from the top.
    public let yLabels: [RecoveryAxisLabel]
    /// Along the chart: the first, middle and last night.
    public let xLabels: [RecoveryAxisLabel]
    /// What the chart's line is: "Sleep", "Bedtime", "HRV", "Resting heart rate".
    public let measure: String
    /// "The shaded band is your normal range: 44 – 56 ms." nil without one.
    public let bandCaption: String?
    /// "No HRV recorded in these nights." when the window has no value.
    public let emptyNote: String?
    public let tiles: [RecoveryFactorTile]
    public let explanation: [RecoveryExplanationBlock]
    public let accessibilityLabel: String

    public static let rangeTitles: [RecoveryFactorRange: String] = [.fortnight: "14 nights", .month: "30 nights", .quarter: "90 nights"]
}

nonisolated extension RecoveryScreenBuilder {
    /// The factor page for `selection` (a factor and a range); nil without
    /// a series or today's score.
    public static func factorContent(
        _ snapshot: RecoverySnapshot, model: RecoveryRenderModel?, selection: RecoverySelection, calendar: Calendar, locale: Locale
    ) -> RecoveryFactorContent? {
        guard let kind = selection.factor,
              let series = snapshot.series(kind, selection.factorRange),
              let result = snapshot.result,
              let today = result.factor(kind) else { return nil }
        let format = HomeFormat(calendar: calendar, locale: locale)
        let row = HomeScreenBuilder.detailRow(today, result: result, needMinutes: snapshot.needMinutes, format: format)
        let line = model?.factor
        let name = HomeScreenBuilder.shortName(kind)
        let measure = measureName(kind)

        let points = series.points.map { point -> RecoveryFactorPointContent in
            let wake = point.night.adding(days: 1)
            let day = selection.factorRange == .fortnight ? format.weekday(wake, width: .abbreviated) : format.weekdayMonthDay(wake)
            guard let value = point.value else {
                return RecoveryFactorPointContent(night: point.night, detail: "\(day) · No data", accessibilityLabel: "\(format.wideDate(wake)), no data")
            }
            var pill = "\(day) · \(valueText(kind, value, format: format))"
            var spoken = "\(format.wideDate(wake)), \(spokenMeasure(kind)) \(spokenValue(kind, value, format: format))"
            if let score = point.score {
                pill += " · Score \(score)"
                spoken += ", score \(score)"
            }
            return RecoveryFactorPointContent(night: point.night, detail: pill, accessibilityLabel: spoken)
        }
        let yLabels = (line?.ticks ?? []).map { tick in
            RecoveryAxisLabel(position: 1 - tick.position, text: axisText(kind, tick.value, format: format))
        }
        var xLabels: [RecoveryAxisLabel] = []
        if let first = series.points.first, let last = series.points.last {
            let middle = series.points[series.points.count / 2]
            for (point, position) in [(first, 0.0), (middle, 0.5), (last, 1.0)] {
                xLabels.append(RecoveryAxisLabel(position: position, text: format.monthDay(point.night.adding(days: 1))))
            }
        }
        var band: String?
        if let range = series.normalRange {
            band = "The shaded band is your normal range: \(valueText(kind, range.lowerBound, format: format)) – \(valueText(kind, range.upperBound, format: format))."
        }
        let empty = series.nightsRecorded == 0 ? "No \(spokenMeasure(kind)) recorded in these nights." : nil
        let tiles = tiles(kind, series: series, result: result, snapshot: snapshot, row: row, format: format)
        let explanation = explanation(kind, needMinutes: snapshot.needMinutes)
        var label = "\(name), last \(series.range.nights) nights. \(row.accessibilityLabel)"
        if let band { label += " " + band }
        if let empty { label += " " + empty }
        return RecoveryFactorContent(
            kind: kind, name: name, range: selection.factorRange, value: row.value, valueSuffix: row.valueSuffix,
            baseline: row.baseline, sentence: row.sentence, points: points, yLabels: yLabels, xLabels: xLabels, measure: measure,
            bandCaption: band, emptyNote: empty, tiles: tiles, explanation: explanation, accessibilityLabel: label
        )
    }

    // MARK: Values

    static func measureName(_ kind: RecoveryFactorKind) -> String {
        switch kind {
        case .sleepDuration: "Sleep"
        case .sleepConsistency: "Bedtime"
        case .hrv: "HRV"
        case .restingHeartRate: "Resting heart rate"
        }
    }

    /// What the line is, mid-sentence: "sleep", "bedtime", "HRV", "resting heart rate".
    static func spokenMeasure(_ kind: RecoveryFactorKind) -> String {
        switch kind {
        case .sleepDuration: "sleep"
        case .sleepConsistency: "bedtime"
        case .hrv: "HRV"
        case .restingHeartRate: "resting heart rate"
        }
    }

    /// "7h 12m", "11:08 PM", "48 ms", "54 bpm".
    static func valueText(_ kind: RecoveryFactorKind, _ value: Double, format: HomeFormat) -> String {
        switch kind {
        case .sleepDuration: HomeFormat.compactDuration(Int(value.rounded()))
        case .sleepConsistency: format.clock(minutesAfterNoon: value)
        case .hrv: NoctisQuantityText.text(Int(value.rounded()), .millisecond)
        case .restingHeartRate: NoctisQuantityText.text(Int(value.rounded()), .beatsPerMinute)
        }
    }

    static func spokenValue(_ kind: RecoveryFactorKind, _ value: Double, format: HomeFormat) -> String {
        switch kind {
        case .sleepDuration: HomeFormat.spokenDuration(Int(value.rounded()))
        case .sleepConsistency: format.clock(minutesAfterNoon: value)
        case .hrv: "\(Int(value.rounded())) milliseconds"
        case .restingHeartRate: "\(Int(value.rounded())) beats per minute"
        }
    }

    /// An axis label: "7h", "11 PM", "50", "55".
    static func axisText(_ kind: RecoveryFactorKind, _ value: Double, format: HomeFormat) -> String {
        switch kind {
        case .sleepDuration:
            return HomeFormat.compactDuration(Int(value.rounded()))
        case .sleepConsistency:
            // A tick on the half hour says so ("11:30 PM"), so two ticks never read "11 PM".
            let minutes = Int(value.rounded()) + 720
            return minutes % 60 == 0 ? format.hour(minutesSinceMidnight: minutes) : format.clock(minutesSinceMidnight: minutes)
        case .hrv, .restingHeartRate:
            return "\(Int(value.rounded()))"
        }
    }

    static func valueMetric(_ kind: RecoveryFactorKind, _ value: Double, format: HomeFormat) -> NoctisMetricValue {
        switch kind {
        case .sleepDuration: HomeFormat.durationMetric(Int(value.rounded()))
        case .sleepConsistency: format.clockMetric(format.clock(minutesAfterNoon: value))
        case .hrv: HomeFormat.quantityMetric(Int(value.rounded()), .millisecond)
        case .restingHeartRate: HomeFormat.quantityMetric(Int(value.rounded()), .beatsPerMinute)
        }
    }

    /// Two metrics as one range: "5h 50m – 8h 20m", "38 – 61 ms".
    static func rangeMetric(_ low: NoctisMetricValue, _ high: NoctisMetricValue) -> NoctisMetricValue {
        NoctisMetricValue(parts: low.parts + [.space, .unit("–"), .space] + high.parts, spoken: "\(low.spoken) to \(high.spoken)")
    }

    // MARK: Tiles

    static func tiles(
        _ kind: RecoveryFactorKind, series: RecoveryFactorSeries, result: RecoveryResult, snapshot: RecoverySnapshot,
        row: FactorDetailRow, format: HomeFormat
    ) -> [RecoveryFactorTile] {
        var tiles: [RecoveryFactorTile] = []
        let isConsistency = kind == .sleepConsistency
        if let today = series.today {
            tiles.append(RecoveryFactorTile(
                id: "today", title: isConsistency ? "Today's bedtime" : "Today", value: valueMetric(kind, today, format: format), note: nil
            ))
        }
        if let usual = series.usual {
            tiles.append(RecoveryFactorTile(
                id: "baseline", title: isConsistency ? "Usual bedtime" : "Baseline", value: valueMetric(kind, usual, format: format),
                note: "last \(BaselineEngine.windowNights) nights"
            ))
        }
        if let low = series.minimum, let high = series.maximum {
            tiles.append(RecoveryFactorTile(
                id: "range", title: "Range", value: rangeMetric(valueMetric(kind, low, format: format), valueMetric(kind, high, format: format)),
                note: "last \(series.range.nights) nights"
            ))
        }
        if let item = snapshot.contributions?.contribution(kind) {
            let points = item.wholePoints
            tiles.append(RecoveryFactorTile(
                id: "points", title: "In today's score",
                value: NoctisMetricValue(parts: [.number("+\(points)"), .space, .unit(NoctisUnit.point.symbol)], spoken: NoctisUnit.point.spoken(points)),
                note: item.deltaPoints.map { "vs usual: \(HomeScreenBuilder.signed(Int($0.rounded())))" }
            ))
        }
        return tiles
    }

    // MARK: Explanation

    /// How the factor is scored and why it counts, from the model's own
    /// constants.
    static func explanation(_ kind: RecoveryFactorKind, needMinutes: Int) -> [RecoveryExplanationBlock] {
        let weight = Int((RecoveryModelV3.weights[kind] ?? 0).rounded())
        let center = Int(RecoveryModelV2.variationCenter)
        let step = Int(RecoveryModelV2.pointsPerStandardDeviation)
        let counts = "It counts for \(weight)% of your recovery score when all four signals are recorded, and more when one is missing."
        switch kind {
        case .sleepDuration:
            return [
                RecoveryExplanationBlock(
                    title: "How it's scored",
                    text: "Sleep is scored against your \(HomeFormat.compactDuration(needMinutes)) need. At or above it the score is 100; each 1% under it takes off \(Int(RecoveryModelV1.durationPointsPerShortfall / 100)) points."
                ),
                RecoveryExplanationBlock(title: "Why it counts", text: "\(counts) Your baseline is the average of your last \(BaselineEngine.windowNights) nights."),
            ]
        case .hrv:
            return [
                RecoveryExplanationBlock(
                    title: "How it's scored",
                    text: "HRV is the variation between heartbeats, recorded by your Apple Watch while you sleep. It's scored against how much it normally varies for you: on your usual it scores about \(center), and each standard deviation above it adds \(step) points, each below takes \(step) away."
                ),
                RecoveryExplanationBlock(title: "Why it counts", text: "\(counts) It's only ever compared with your own last \(BaselineEngine.windowNights) nights, never with anyone else's."),
            ]
        case .restingHeartRate:
            return [
                RecoveryExplanationBlock(
                    title: "How it's scored",
                    text: "Resting heart rate is scored the same way, the other way up: on your usual it scores about \(center), each standard deviation lower adds \(step) points, and each higher takes \(step) away."
                ),
                RecoveryExplanationBlock(title: "Why it counts", text: "\(counts) It's only ever compared with your own last \(BaselineEngine.windowNights) nights."),
            ]
        case .sleepConsistency:
            return [
                RecoveryExplanationBlock(
                    title: "How it's scored",
                    text: "Consistency is how close your bedtime and wake time were to your usual, on average. On your usual it scores 100, and it falls to 0 at \(Int(RecoveryModelV1.consistencyZeroAtMinutes)) minutes away."
                ),
                RecoveryExplanationBlock(title: "Why it counts", text: "\(counts) The chart shows your bedtime; the score counts your wake time too."),
            ]
        }
    }
}
