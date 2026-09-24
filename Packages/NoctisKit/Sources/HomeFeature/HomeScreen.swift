import Foundation
import HealthProviding
import InsightsKit
import NoctisCore
import RecoveryKit
import SleepKit

// Everything Home shows, as plain values: every string and number is
// decided here, from `HomeSnapshot`, so the views only lay it out
// (APP_RULES.md R18, R20). Built by `HomeScreenBuilder`.

public nonisolated struct HomeHeader: Sendable, Equatable {
    /// "Good morning." split so one word can be emphasized.
    public let greetingLead: String
    public let greetingEmphasis: String
    public let greetingTrail: String
    /// "Thursday, September 24".
    public let date: String
    /// "Updated 2h ago" once the newest data is over an hour old.
    public let updated: String?

    public var greeting: String { greetingLead + greetingEmphasis + greetingTrail }
}

public nonisolated struct RingSegmentContent: Sendable, Equatable {
    public let kind: RecoveryFactorKind
    /// Renormalized weight (0...1): the segment's share of the ring.
    public let weight: Double
    /// Factor score / 100.
    public let fraction: Double
}

public nonisolated enum DeltaTone: Sendable, Equatable {
    case above
    case inLine
    case below
}

public nonisolated struct DeltaChip: Sendable, Equatable {
    /// "+6 vs your baseline" — the sign is always shown.
    public let text: String
    public let tone: DeltaTone
}

public nonisolated struct FactorCell: Sendable, Equatable {
    public let kind: RecoveryFactorKind
    public let name: String
    public let score: Int
}

public nonisolated struct ScoredRecoveryContent: Sendable, Equatable {
    public let score: Int
    public let segments: [RingSegmentContent]
    public let chip: DeltaChip?
    public let sentence: String
    public let confidence: String
    public let factors: [FactorCell]
    public let accessibilityLabel: String
}

public nonisolated enum RecoveryCardContent: Sendable, Equatable {
    /// Health access never requested (or no Health on this device):
    /// "Your first night starts here."
    case connect(title: String, message: String, showsButton: Bool)
    /// Access already requested, but no sleep data: "No sleep data yet",
    /// with "Open Health".
    case noSleepData(title: String, message: String)
    case learning(nights: Int, required: Int, text: String)
    case scored(ScoredRecoveryContent)
    /// Data is current, but no sleep was recorded last night.
    case noSleep(title: String, detail: String?)
    /// Apple Health hasn't synced for over a day.
    case stale(title: String, detail: String)
    case failed(message: String)
}

public nonisolated enum StripStage: String, Sendable, Equatable, CaseIterable {
    case deep
    case core
    case rem
    case awake
    /// Asleep without a stage ("unspecified").
    case asleep

    public var name: String {
        switch self {
        case .deep: "Deep"
        case .core: "Core"
        case .rem: "REM"
        case .awake: "Awake"
        case .asleep: "Asleep"
        }
    }
}

public nonisolated struct StripSegment: Sendable, Equatable {
    public let stage: StripStage
    /// Position along the night, 0...1.
    public let start: Double
    public let end: Double
}

public nonisolated enum StageStripContent: Sendable, Equatable {
    case stages([StripSegment], legend: [StripStage])
    case noStages(caption: String)
}

public nonisolated struct LastNightCardContent: Sendable, Equatable {
    /// "8h 25m".
    public let duration: String
    /// "11:02 PM – 7:27 AM".
    public let timeRange: String
    public let strip: StageStripContent
    public let accessibilityLabel: String
}

public nonisolated struct InsightCardContent: Sendable, Equatable {
    public let title: String
    public let message: String
}

public nonisolated struct TonightCardContent: Sendable, Equatable {
    /// "Bedtime around 11:00 PM".
    public let bedtime: String
    /// "Wake 7:00 AM · 8h need".
    public let detail: String
}

public nonisolated struct WeekBar: Sendable, Equatable {
    /// Weekday initial of the morning the night ended.
    public let label: String
    /// Bar height as a share of the chart (0...1); nil with no data.
    public let fraction: Double?
    public let isLastNight: Bool
    public let accessibilityLabel: String
}

public nonisolated struct WeekCardContent: Sendable, Equatable {
    public let bars: [WeekBar]
    /// Height of the dashed need line, as a share of the chart.
    public let needFraction: Double
    /// "8h need".
    public let needLabel: String
    /// "Avg 7h 48m"; nil when no night has data.
    public let average: String?
    public let accessibilityLabel: String
}

public nonisolated struct FactorDetailRow: Sendable, Equatable {
    public let kind: RecoveryFactorKind
    public let name: String
    /// "HRV 48 ms".
    public let value: String
    /// "baseline 44 ms".
    public let baseline: String
    public let score: Int
    public let sentence: String
}

public nonisolated struct RecoveryDetailContent: Sendable, Equatable {
    public let recovery: ScoredRecoveryContent
    public let rows: [FactorDetailRow]
    /// "How this is calculated", paragraph by paragraph.
    public let calculation: [String]
    /// "Model recovery-v1".
    public let modelVersion: String
}

public nonisolated struct HomeScreen: Sendable, Equatable {
    public let header: HomeHeader
    public let recovery: RecoveryCardContent
    public let lastNight: LastNightCardContent?
    public let insight: InsightCardContent?
    public let tonight: TonightCardContent
    public let week: WeekCardContent?
    public let detail: RecoveryDetailContent?
}

// MARK: - Builder

public nonisolated enum HomeScreenBuilder {
    /// Ring and factor-row order.
    public static let factorOrder: [RecoveryFactorKind] = [.sleepDuration, .hrv, .restingHeartRate, .sleepConsistency]
    /// "Updated … ago" appears once the newest data is older than this.
    public static let updatedCaptionAfter: TimeInterval = 3600
    /// Headroom above the tallest bar or the need line in This week.
    public static let weekHeadroom = 1.12

    public static func build(_ snapshot: HomeSnapshot, now: Date, calendar: Calendar, locale: Locale) -> HomeScreen {
        let format = HomeFormat(calendar: calendar, locale: locale)
        let recovery = recoveryCard(snapshot, format: format)
        let showsDataCards: Bool = switch recovery {
        case .connect, .noSleepData, .failed: false
        case .learning, .scored, .noSleep, .stale: true
        }
        var detail: RecoveryDetailContent?
        if case .scored(let content) = recovery, case .scored(let result)? = snapshot.recovery {
            detail = recoveryDetail(result, content: content, needMinutes: snapshot.tonight.needMinutes, format: format)
        }
        return HomeScreen(
            header: header(now: now, newestSample: snapshot.newestSample, format: format),
            recovery: recovery,
            lastNight: showsDataCards ? snapshot.lastNight.map { lastNightCard($0, format: format) } : nil,
            insight: showsDataCards ? snapshot.topInsight.map { InsightCardContent(title: $0.title, message: $0.message) } : nil,
            tonight: tonightCard(snapshot.tonight, format: format),
            week: showsDataCards ? weekCard(snapshot, format: format) : nil,
            detail: detail
        )
    }

    // MARK: Header

    public static func header(now: Date, newestSample: Date?, calendar: Calendar, locale: Locale) -> HomeHeader {
        header(now: now, newestSample: newestSample, format: HomeFormat(calendar: calendar, locale: locale))
    }

    static func header(now: Date, newestSample: Date?, format: HomeFormat) -> HomeHeader {
        let hour = format.calendar.component(.hour, from: now)
        let partOfDay = switch hour {
        case 4..<12: "morning"
        case 12..<18: "afternoon"
        default: "evening"
        }
        return HomeHeader(
            greetingLead: "Good ",
            greetingEmphasis: partOfDay,
            greetingTrail: ".",
            date: format.longDate(now),
            updated: newestSample.flatMap { updatedCaption(age: now.timeIntervalSince($0)) }
        )
    }

    /// "Updated 2h ago" past an hour, "Updated 3 days ago" from two days.
    static func updatedCaption(age: TimeInterval) -> String? {
        guard age > updatedCaptionAfter else { return nil }
        let hours = Int(age / 3600)
        return hours < 48 ? "Updated \(hours)h ago" : "Updated \(hours / 24) days ago"
    }

    // MARK: Recovery

    static func recoveryCard(_ snapshot: HomeSnapshot, format: HomeFormat) -> RecoveryCardContent {
        let title = "Your first night starts here."
        switch snapshot.dataState {
        case .healthDataUnavailable:
            return .connect(title: title, message: "Apple Health isn't available on this device.", showsButton: false)
        case .permissionRequired:
            // HealthKit's request status is `.shouldRequest`: never asked.
            return .connect(title: title, message: "Connect Apple Health so NOCTIS can read your nights.", showsButton: true)
        case .empty, .learning(nightsSoFar: 0):
            // Already asked (`.unnecessary`), yet no sleep: HealthKit never
            // says whether reading was allowed, so point to the source.
            return noSleepData
        case .failed:
            return .failed(message: "We couldn't read your latest sleep data.")
        case .stale(let newest):
            // Sync is behind; it doesn't mean the person didn't sleep.
            return .stale(
                title: "Apple Health hasn't updated since \(format.dayAndTime(newest)).",
                detail: "Open Health or pull to refresh."
            )
        case .learning, .noSleepLastNight, .ready:
            break
        }
        switch snapshot.recovery {
        case .learning(let nights)?:
            let required = RecoveryModelV2.learningNights
            return .learning(nights: nights, required: required, text: "Learning your baseline · \(nights) of \(required) nights")
        case .noSleepLastNight?:
            let detail = snapshot.latestSleep.map { "Last recorded night ended \(format.shortDate($0.wakeTime, in: $0.timeZone))." }
            return .noSleep(title: "No sleep recorded last night.", detail: detail)
        case .scored(let result)?:
            return .scored(scoredContent(result))
        case nil:
            return .connect(title: title, message: "Connect Apple Health so NOCTIS can read your nights.", showsButton: true)
        }
    }

    static func scoredContent(_ result: RecoveryResult) -> ScoredRecoveryContent {
        let factors = factorOrder.compactMap { result.factor($0) }
        let chip = result.comparison.delta.map { delta in
            DeltaChip(text: "\(signed(delta)) vs your baseline", tone: tone(result.comparison.trend))
        }
        return ScoredRecoveryContent(
            score: result.score,
            segments: factors.map { RingSegmentContent(kind: $0.kind, weight: $0.weight, fraction: Double($0.score) / 100) },
            chip: chip,
            sentence: result.comparison.sentence,
            confidence: confidenceLine(result),
            factors: factors.map { FactorCell(kind: $0.kind, name: shortName($0.kind), score: $0.score) },
            accessibilityLabel: accessibilitySummary(result, factors: factors)
        )
    }

    static let noSleepData = RecoveryCardContent.noSleepData(
        title: "No sleep data yet",
        message: "NOCTIS reads sleep from Apple Health. Track sleep with Apple Watch or set up Sleep in the Health app."
    )

    static func tone(_ trend: RecoveryTrend) -> DeltaTone {
        switch trend {
        case .above: .above
        case .below: .below
        case .inLine, .unknown: .inLine
        }
    }

    /// "+6", "−4" (a real minus sign), "±0".
    static func signed(_ value: Int) -> String {
        if value > 0 { return "+\(value)" }
        if value < 0 { return "\u{2212}\(-value)" }
        return "±0"
    }

    /// "Moderate confidence · sleep, heart rate, consistency", or for sleep
    /// alone "Low confidence · sleep only. HRV and heart rate aren't
    /// available from your sources."
    static func confidenceLine(_ result: RecoveryResult) -> String {
        let tier = switch result.confidence {
        case .high: "High confidence"
        case .moderate: "Moderate confidence"
        case .low: "Low confidence"
        }
        let used = factorOrder.filter { result.factorsUsed.contains($0) }
        let heartFactors: [RecoveryFactorKind] = [.hrv, .restingHeartRate]
        guard used.contains(where: heartFactors.contains) else {
            let reasons = gapSentences(heartFactors.compactMap { kind in result.missingFactors[kind].map { (kind, $0) } })
            return ([tier + " · sleep only."] + reasons).joined(separator: " ")
        }
        return tier + " · " + used.map(listName).joined(separator: ", ")
    }

    /// One sentence per kind of gap, naming the factors it covers.
    static func gapSentences(_ gaps: [(RecoveryFactorKind, RecoveryFactorGap)]) -> [String] {
        let order: [RecoveryFactorGap] = [.unavailable, .notRecorded, .buildingBaseline]
        return order.compactMap { gap in
            let names = gaps.filter { $0.1 == gap }.map { listName($0.0) }
            guard !names.isEmpty else { return nil }
            let plural = names.count > 1
            let subject = names.joined(separator: " and ")
            let sentence = switch gap {
            case .unavailable: "\(subject) \(plural ? "aren't" : "isn't") available from your sources."
            case .notRecorded: "\(subject) \(plural ? "weren't" : "wasn't") recorded last night."
            case .buildingBaseline: "\(subject) \(plural ? "baselines are" : "baseline is") still forming."
            }
            return sentence.prefix(1).uppercased() + sentence.dropFirst()
        }
    }

    /// "Recovery 82, 6 above your baseline, moderate confidence. Sleep 91,
    /// HRV 78, resting heart rate 85, consistency 74."
    static func accessibilitySummary(_ result: RecoveryResult, factors: [RecoveryFactor]) -> String {
        var lead = ["Recovery \(result.score)"]
        if let delta = result.comparison.delta {
            lead.append(delta == 0 ? "same as your baseline" : "\(abs(delta)) \(delta > 0 ? "above" : "below") your baseline")
        }
        lead.append("\(result.confidence.rawValue) confidence")
        let parts = factors.enumerated().map { index, factor in
            let name = spokenName(factor.kind)
            return "\(index == 0 ? name.prefix(1).uppercased() + name.dropFirst() : name) \(factor.score)"
        }
        return lead.joined(separator: ", ") + "." + (parts.isEmpty ? "" : " " + parts.joined(separator: ", ") + ".")
    }

    static func shortName(_ kind: RecoveryFactorKind) -> String {
        switch kind {
        case .sleepDuration: "Sleep"
        case .hrv: "HRV"
        case .restingHeartRate: "Resting HR"
        case .sleepConsistency: "Consistency"
        }
    }

    static func listName(_ kind: RecoveryFactorKind) -> String {
        switch kind {
        case .sleepDuration: "sleep"
        case .hrv: "HRV"
        case .restingHeartRate: "heart rate"
        case .sleepConsistency: "consistency"
        }
    }

    static func spokenName(_ kind: RecoveryFactorKind) -> String {
        switch kind {
        case .sleepDuration: "sleep"
        case .hrv: "HRV"
        case .restingHeartRate: "resting heart rate"
        case .sleepConsistency: "consistency"
        }
    }

    // MARK: Recovery detail

    static func recoveryDetail(_ result: RecoveryResult, content: ScoredRecoveryContent, needMinutes: Int, format: HomeFormat) -> RecoveryDetailContent {
        let rows = factorOrder.compactMap { result.factor($0) }.map { detailRow($0, result: result, needMinutes: needMinutes, format: format) }
        return RecoveryDetailContent(
            recovery: content,
            rows: rows,
            calculation: calculation(result, needMinutes: needMinutes),
            modelVersion: "Model \(result.modelVersion)"
        )
    }

    static func detailRow(_ factor: RecoveryFactor, result: RecoveryResult, needMinutes: Int, format: HomeFormat) -> FactorDetailRow {
        let name = shortName(factor.kind)
        switch factor.kind {
        case .sleepDuration:
            let slept = Int(factor.value.rounded())
            let need = HomeFormat.compactDuration(needMinutes)
            return FactorDetailRow(
                kind: factor.kind, name: name,
                value: "Sleep \(noctisFormattedDuration(minutes: slept))",
                baseline: factor.baseline.map { "baseline \(noctisFormattedDuration(minutes: Int($0.rounded())))" } ?? "no baseline yet",
                score: factor.score,
                sentence: slept >= needMinutes
                    ? "You met your \(need) sleep need."
                    : "You slept \(noctisFormattedDuration(minutes: slept)) of your \(need) need."
            )
        case .hrv:
            let baseline = factor.baseline ?? factor.value
            let value = Int(factor.value.rounded())
            let percent = baseline > 0 ? Int(((factor.value / baseline - 1) * 100).rounded()) : 0
            let v1Sentence = percent == 0 ? "In line with your baseline." : "\(abs(percent))% \(percent > 0 ? "above" : "below") your baseline."
            return FactorDetailRow(
                kind: factor.kind, name: name,
                value: "HRV \(value) ms",
                baseline: "baseline \(Int(baseline.rounded())) ms",
                score: factor.score,
                sentence: factor.range.map { rangeSentence($0, value: "\(value) ms", baseline: "\(Int(baseline.rounded())) ms") } ?? v1Sentence
            )
        case .restingHeartRate:
            let baseline = factor.baseline ?? factor.value
            let value = Int(factor.value.rounded())
            let difference = value - Int(baseline.rounded())
            let v1Sentence = difference == 0 ? "Same as your baseline." : "\(abs(difference)) bpm \(difference > 0 ? "above" : "below") your baseline."
            return FactorDetailRow(
                kind: factor.kind, name: name,
                value: "Resting HR \(value) bpm",
                baseline: "baseline \(Int(baseline.rounded())) bpm",
                score: factor.score,
                sentence: factor.range.map { rangeSentence($0, value: "\(value) bpm", baseline: "\(Int(baseline.rounded())) bpm") } ?? v1Sentence
            )
        case .sleepConsistency:
            let minutes = Int(factor.value.rounded())
            var usual = "no baseline yet"
            if let bedtime = result.baselines.bedtime?.value, let wake = result.baselines.wakeTime?.value {
                usual = "usual \(format.clock(minutesAfterNoon: bedtime)) – \(format.clock(minutesAfterNoon: wake))"
            }
            return FactorDetailRow(
                kind: factor.kind, name: name,
                value: "Consistency \(HomeFormat.compactDuration(minutes, minutesWord: true)) off",
                baseline: usual,
                score: factor.score,
                sentence: minutes == 0
                    ? "Right on your usual bedtime and wake time."
                    : "Bedtime and wake time were \(HomeFormat.compactDuration(minutes, minutesWord: true)) from your usual, on average."
            )
        }
    }

    /// "Within your normal range: 48 ms vs your 50 ms baseline."
    static func rangeSentence(_ range: RecoveryRange, value: String, baseline: String) -> String {
        let place = switch range {
        case .within: "Within your normal range"
        case .above: "Above your normal range"
        case .below: "Below your normal range"
        }
        return "\(place): \(value) vs your \(baseline) baseline."
    }

    static func calculation(_ result: RecoveryResult, needMinutes: Int) -> [String] {
        let model = RecoveryModel(rawValue: result.modelVersion) ?? .current
        func weight(_ kind: RecoveryFactorKind) -> String {
            "\(Int((model.weights[kind] ?? 0).rounded()))%"
        }
        var paragraphs = [
            "Recovery compares last night with your own last \(BaselineEngine.windowNights) nights. "
                + "Four signals count: sleep against your \(HomeFormat.compactDuration(needMinutes)) need (\(weight(.sleepDuration))), "
                + "HRV (\(weight(.hrv))), resting heart rate (\(weight(.restingHeartRate))) "
                + "and how close your bedtime and wake time were to usual (\(weight(.sleepConsistency)))."
                + (model == .v2
                    ? " HRV and resting heart rate are scored against how much they normally vary for you: a typical night scores about "
                        + "\(Int(RecoveryModelV2.variationCenter)), and each standard deviation better or worse moves the score "
                        + "\(Int(RecoveryModelV2.pointsPerStandardDeviation)) points."
                    : ""),
        ]
        if result.factors.count < RecoveryFactorKind.allCases.count {
            let today = factorOrder.compactMap { result.factor($0) }
                .map { "\(listName($0.kind)) \(Int(($0.weight * 100).rounded()))%" }
                .joined(separator: ", ")
            paragraphs.append("A signal without data, or without \(BaselineEngine.minimumNights) nights to compare with, is left out and the others share its weight. Today: \(today).")
        } else {
            paragraphs.append("Today all four signals count.")
        }
        paragraphs.append(
            "Confidence is high with all four signals and \(RecoveryModelV1.highConfidenceNights) nights of history, "
                + "moderate with at least \(RecoveryModelV1.moderateConfidenceFactors) signals \(model == .v1 ? "or" : "and") "
                + "\(RecoveryModelV1.moderateConfidenceNights) nights, and low otherwise."
        )
        return paragraphs
    }

    // MARK: Last night

    static func lastNightCard(_ session: SleepSession, format: HomeFormat) -> LastNightCardContent {
        let duration = noctisFormattedDuration(minutes: Int((session.totals.asleep / 60).rounded()))
        let bedtime = format.clock(session.bedtime, in: session.timeZone)
        let wake = format.clock(session.wakeTime, in: session.timeZone)
        let strip = stageStrip(session)
        var spoken = "Last night, slept \(duration), \(bedtime) to \(wake)."
        switch strip {
        case .stages(_, let legend):
            let parts = legend.map { stage in
                "\(stage.name) \(HomeFormat.compactDuration(Int((stageTotal(stage, session.totals) / 60).rounded())))"
            }
            spoken += " " + parts.joined(separator: ", ") + "."
        case .noStages(let caption):
            spoken += " " + caption
        }
        return LastNightCardContent(duration: duration, timeRange: "\(bedtime) – \(wake)", strip: strip, accessibilityLabel: spoken)
    }

    static func stageStrip(_ session: SleepSession) -> StageStripContent {
        guard session.completeness.hasStageDetail,
              let start = session.timeline.first?.interval.start,
              let end = session.timeline.map(\.interval.end).max(), end > start else {
            return .noStages(caption: "Stages aren't available from your current sources.")
        }
        let span = end.timeIntervalSince(start)
        var segments: [StripSegment] = []
        for segment in session.timeline {
            guard let stage = stripStage(segment.stage) else { continue }
            let from = segment.interval.start.timeIntervalSince(start) / span
            let to = segment.interval.end.timeIntervalSince(start) / span
            if let last = segments.last, last.stage == stage, abs(last.end - from) < 1e-9 {
                segments[segments.count - 1] = StripSegment(stage: stage, start: last.start, end: to)
            } else {
                segments.append(StripSegment(stage: stage, start: from, end: to))
            }
        }
        let present = Set(segments.map(\.stage))
        return .stages(segments, legend: StripStage.allCases.filter(present.contains))
    }

    static func stripStage(_ stage: SleepStageValue) -> StripStage? {
        switch stage {
        case .deep: .deep
        case .core: .core
        case .rem: .rem
        case .awake: .awake
        case .unspecified: .asleep
        case .inBed: nil
        }
    }

    static func stageTotal(_ stage: StripStage, _ totals: SleepTotals) -> TimeInterval {
        switch stage {
        case .deep: totals.deep
        case .core: totals.core
        case .rem: totals.rem
        case .awake: totals.awake
        case .asleep: totals.unspecified
        }
    }

    // MARK: Tonight

    static func tonightCard(_ plan: TonightPlan, format: HomeFormat) -> TonightCardContent {
        TonightCardContent(
            bedtime: "Bedtime around \(format.clock(minutesSinceMidnight: plan.bedtimeMinutes))",
            detail: "Wake \(format.clock(minutesSinceMidnight: plan.wakeMinutes)) · \(HomeFormat.compactDuration(plan.needMinutes)) need"
        )
    }

    // MARK: This week

    static func weekCard(_ snapshot: HomeSnapshot, format: HomeFormat) -> WeekCardContent {
        let need = Double(snapshot.tonight.needMinutes)
        let longest = snapshot.recentNights.compactMap(\.asleepMinutes).max() ?? 0
        let top = max(need, longest) * weekHeadroom
        let bars = snapshot.recentNights.map { night -> WeekBar in
            let wakeDay = night.night.adding(days: 1)
            let dayName = format.weekday(wakeDay, width: .wide)
            let duration = night.asleepMinutes.map { noctisFormattedDuration(minutes: Int($0.rounded())) }
            return WeekBar(
                label: format.weekday(wakeDay, width: .narrow),
                fraction: night.asleepMinutes.map { top > 0 ? $0 / top : 0 },
                isLastNight: night.night == snapshot.lastNight?.night,
                accessibilityLabel: "\(dayName), \(duration ?? "no data")"
            )
        }
        let needLabel = "\(HomeFormat.compactDuration(snapshot.tonight.needMinutes)) need"
        let averageDuration = snapshot.weekAverageMinutes.map { noctisFormattedDuration(minutes: Int($0.rounded())) }
        let average = averageDuration.map { "Avg \($0)" }
        let spokenAverage = averageDuration.map { ", average \($0)" } ?? ""
        return WeekCardContent(
            bars: bars,
            needFraction: top > 0 ? need / top : 0,
            needLabel: needLabel,
            average: average,
            accessibilityLabel: "This week\(spokenAverage), \(needLabel). " + bars.map(\.accessibilityLabel).joined(separator: "; ") + "."
        )
    }
}

// MARK: - Formatting

/// Locale-aware formatting with an explicit calendar, time zone and
/// locale, so every string is reproducible in tests.
nonisolated struct HomeFormat {
    let calendar: Calendar
    let locale: Locale

    /// "Thursday, September 24".
    func longDate(_ date: Date, in timeZone: TimeZone? = nil) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone ?? calendar.timeZone).weekday(.wide).month(.wide).day())
    }

    /// "Wed, Sep 23".
    func shortDate(_ date: Date, in timeZone: TimeZone? = nil) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone ?? calendar.timeZone).weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "Wed 7:02 AM", kept on one line (no-break spaces).
    func dayAndTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated).hour().minute())
            .replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    /// "11:02 PM" on the clock of `timeZone`.
    func clock(_ date: Date, in timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone))
    }

    /// A clock time given as minutes since midnight.
    func clock(minutesSinceMidnight minutes: Int) -> String {
        let normalized = ((minutes % 1440) + 1440) % 1440
        let components = DateComponents(year: 2026, month: 1, day: 1, hour: normalized / 60, minute: normalized % 60)
        guard let date = calendar.date(from: components) else { return "" }
        return clock(date, in: calendar.timeZone)
    }

    /// A clock time given as minutes after noon (baselines' unit).
    func clock(minutesAfterNoon: Double) -> String {
        clock(minutesSinceMidnight: Int(minutesAfterNoon.rounded()) + 720)
    }

    enum WeekdayWidth { case narrow, wide }

    func weekday(_ day: SleepNightKey, width: WeekdayWidth) -> String {
        let components = DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)
        guard let date = calendar.date(from: components) else { return "" }
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        return date.formatted(width == .narrow ? style.weekday(.narrow) : style.weekday(.wide))
    }

    /// "8h", "8h 15m", "45m" — or with `minutesWord`, "45 min".
    static func compactDuration(_ minutes: Int, minutesWord: Bool = false) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return minutesWord ? "\(remainder) min" : "\(remainder)m" }
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }
}
