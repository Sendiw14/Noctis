import DesignSystem
import Foundation
import HealthProviding
import HomeFeature
import NoctisCore
import RecoveryKit
import SleepAnalysisKit
import SleepKit

// The Sleep tab's presentation model: every string and readable value,
// built by `SleepScreenBuilder` from a `SleepSnapshot` and a render model.
// Views lay it out and add nothing (APP_RULES.md R18, R20). Wording
// describes how nights compare with the person's own need and pattern: it
// never claims to measure health, diagnose or warn.

// MARK: - Content

/// One night in the picker strip.
public nonisolated struct SleepPickerItem: Sendable, Equatable, Identifiable {
    public let night: SleepNightKey
    /// The weekday of the morning the night ended: "T".
    public let initial: String
    /// The day number of that morning: "29".
    public let day: String
    public let hasData: Bool
    /// "Tuesday, September 29, slept 6 hours 42 minutes" or "…, no sleep recorded".
    public let accessibilityLabel: String

    public var id: SleepNightKey { night }
}

/// A stage row of the breakdown card.
public nonisolated struct SleepStageRowContent: Sendable, Equatable {
    public let stage: StripStage
    public let name: String
    public let duration: NoctisMetricValue
    /// "22%".
    public let shareText: String
    public let share: Double
    /// "usual 22%" when there are 5 nights to compare with.
    public let usualText: String?
    public let usual: Double?
    public let accessibilityLabel: String
}

public nonisolated struct SleepStageCardContent: Sendable, Equatable {
    public let rows: [SleepStageRowContent]
    /// "Shares of time asleep; Awake is a share of the time recorded."
    public let footnote: String
}

public nonisolated struct SleepFactorRowContent: Sendable, Equatable {
    public let kind: SleepQualityFactorKind
    public let name: String
    public let score: Int
    /// 0...1.
    public let fraction: Double
    public let sentence: String
}

public nonisolated struct SleepQualityCardContent: Sendable, Equatable {
    public let factors: [SleepFactorRowContent]
    /// "What changed?": one sentence from the largest deviation.
    public let whatChanged: String
    /// "Moderate confidence · 9 nights of your own sleep".
    public let confidence: String
    /// "How this is calculated", paragraph by paragraph.
    public let calculation: [String]
    /// "Model sleep-quality-v1".
    public let modelVersion: String
    /// Factors this night couldn't support, in words ("Stages aren't recorded by your current sources").
    public let omitted: [String]
}

public nonisolated struct SleepQualityRingContent: Sendable, Equatable {
    public let score: Int
    /// 0...1.
    public let fraction: Double
    /// Where your typical score sits on the ring, 0...1; nil without a baseline.
    public let usual: Double?
    /// The ring's angles, from the render model.
    public let arc: NoctisRingArc
    /// "typical 76" when a baseline exists.
    public let typicalText: String?
    public let accessibilityLabel: String
}

/// A tile of the details grid; tiles with no value are never made.
public nonisolated struct SleepDetailTile: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let value: NoctisMetricValue
    /// A small caption under the value ("after falling asleep").
    public let note: String?
}

public nonisolated struct SleepLearningContent: Sendable, Equatable {
    public let nights: Int
    public let required: Int
    /// "3 of 5 nights".
    public let text: String
}

public nonisolated struct SleepDayContent: Sendable, Equatable {
    public let night: SleepNightKey
    /// "LAST NIGHT" or "TUE, SEP 22".
    public let caption: String
    public let duration: NoctisMetricValue
    /// Minutes asleep, for the count-up.
    public let minutes: Int
    /// "11:02 PM – 7:27 AM".
    public let timeRange: String
    /// The ring, once there's a score to show (not while learning).
    public let ring: SleepQualityRingContent?
    /// While fewer than 5 nights are recorded, dots in place of the ring.
    public let learning: SleepLearningContent?
    /// The landscape; its caption says when stages aren't available.
    public let chart: NightChartContent
    public let stages: SleepStageCardContent?
    public let quality: SleepQualityCardContent?
    public let details: [SleepDetailTile]
    public let accessibilityLabel: String
}

/// What the tab shows instead of the nights when there's nothing to show.
public nonisolated enum SleepStateContent: Sendable, Equatable {
    /// Health access never requested, or no Health on this device.
    case connect(title: String, message: String, showsButton: Bool)
    /// Access asked for, but no sleep in Health.
    case noSleepData(title: String, message: String)
    case failed(message: String)
}

/// A night in the picker with nothing recorded.
public nonisolated struct SleepNoNightContent: Sendable, Equatable {
    public let night: SleepNightKey
    public let title: String
    public let detail: String?
}

public nonisolated struct SleepBanner: Sendable, Equatable {
    public let title: String
    public let detail: String
}

public nonisolated struct SleepScreen: Sendable, Equatable {
    /// "TUESDAY, SEPTEMBER 29".
    public let dateCaption: String
    public let picker: [SleepPickerItem]
    public let selection: SleepSelection
    public let state: SleepStateContent?
    public let banner: SleepBanner?
    public let day: SleepDayContent?
    public let noNight: SleepNoNightContent?
    public let week: SleepWeekContent?
    public let month: SleepMonthContent?
    /// The selected range's title for VoiceOver ("Day", "Week", "Month").
    public var rangeTitle: String { selection.range.title }
}

// MARK: - Builder

public nonisolated enum SleepScreenBuilder {
    public typealias Model = SleepQualityModelV1

    public static func build(
        _ snapshot: SleepSnapshot,
        model: SleepRenderModel?,
        selection: SleepSelection,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> SleepScreen {
        let format = HomeFormat(calendar: calendar, locale: locale)
        let state = stateContent(snapshot.dataState)
        let showsNights = state == nil
        let record = snapshot.record(selection.night)

        var day: SleepDayContent?
        var noNight: SleepNoNightContent?
        var week: SleepWeekContent?
        var month: SleepMonthContent?
        if showsNights {
            switch selection.range {
            case .day:
                if let record, let dayModel = model?.day, model?.selection == selection {
                    day = dayContent(record, snapshot: snapshot, render: dayModel, format: format)
                } else if record == nil {
                    noNight = noNightContent(selection.night, snapshot: snapshot, format: format)
                }
            case .week:
                if let model, model.selection == selection, model.week != nil {
                    week = weekContent(snapshot, model: model, format: format)
                }
            case .month:
                if let model, model.selection == selection, model.month != nil {
                    month = monthContent(snapshot, model: model, format: format)
                }
            }
        }
        return SleepScreen(
            dateCaption: format.longDate(now).uppercased(),
            picker: showsNights ? picker(snapshot, selected: selection.night, format: format) : [],
            selection: selection,
            state: state,
            banner: banner(snapshot, format: format),
            day: day,
            noNight: noNight,
            week: week,
            month: month
        )
    }

    // MARK: State

    static func stateContent(_ state: HomeDataState) -> SleepStateContent? {
        switch state {
        case .healthDataUnavailable:
            .connect(title: "Your first night starts here.", message: "Apple Health isn't available on this device.", showsButton: false)
        case .permissionRequired:
            .connect(title: "Your first night starts here.", message: "Connect Apple Health so NOCTIS can read your nights.", showsButton: true)
        case .empty:
            .noSleepData(
                title: "No sleep data yet",
                message: "NOCTIS reads sleep from Apple Health. Track sleep with Apple Watch or set up Sleep in the Health app."
            )
        case .failed:
            .failed(message: "We couldn't read your latest sleep data.")
        case .stale, .learning, .noSleepLastNight, .ready:
            nil
        }
    }

    static func banner(_ snapshot: SleepSnapshot, format: HomeFormat) -> SleepBanner? {
        guard case .stale(let newest) = snapshot.dataState else { return nil }
        return SleepBanner(
            title: "Apple Health hasn't updated since \(format.dayAndTime(newest)).",
            detail: "Open Health or pull to refresh."
        )
    }

    static func noNightContent(_ night: SleepNightKey, snapshot: SleepSnapshot, format: HomeFormat) -> SleepNoNightContent {
        let isLastNight = night == snapshot.anchorNight
        let detail = snapshot.records.last.map { "Last recorded night ended \(format.shortDate($0.session.wakeTime, in: $0.session.timeZone))." }
        return SleepNoNightContent(
            night: night,
            title: isLastNight ? "No sleep recorded last night." : "No sleep recorded this night.",
            detail: detail
        )
    }

    // MARK: Picker

    /// The last 14 nights ending on the newest night the tab can show.
    static func picker(_ snapshot: SleepSnapshot, selected: SleepNightKey, format: HomeFormat) -> [SleepPickerItem] {
        let end = max(snapshot.defaultNight, selected)
        return snapshot.nights(endingAt: end, count: 14).map { entry in
            let wake = entry.night.adding(days: 1)
            let dayName = format.weekday(wake, width: .wide)
            let dayNumber = String(wake.day)
            let slept = entry.record.map { HomeFormat.spokenDuration(Int($0.metrics.asleepMinutes.rounded())) }
            return SleepPickerItem(
                night: entry.night,
                initial: format.weekday(wake, width: .narrow),
                day: dayNumber,
                hasData: entry.record != nil,
                accessibilityLabel: "\(dayName) \(dayNumber), " + (slept.map { "slept \($0)" } ?? "no sleep recorded")
            )
        }
    }

    // MARK: Day

    static func dayContent(_ record: SleepNightRecord, snapshot: SleepSnapshot, render: SleepDayRender, format: HomeFormat) -> SleepDayContent {
        let session = record.session
        let metrics = record.metrics
        let minutes = Int(metrics.asleepMinutes.rounded())
        let bedtime = format.clock(session.bedtime, in: session.timeZone)
        let wake = format.clock(session.wakeTime, in: session.timeZone)
        let isLastNight = record.night == snapshot.defaultNight
        let caption = isLastNight ? "LAST NIGHT" : format.shortDate(session.wakeTime, in: session.timeZone).uppercased()
        let learning: SleepLearningContent? = {
            guard case .learning(let nights) = snapshot.dataState else { return nil }
            return SleepLearningContent(nights: nights, required: RecoveryModelV1.learningNights, text: "\(nights) of \(RecoveryModelV1.learningNights) nights")
        }()
        let chart = HomeScreenBuilder.nightChart(session, heart: record.heart, render: render.night, format: format)
        let ring = learning == nil ? ringContent(record.quality, render: render) : nil
        let stages = stageCard(metrics, render: render)
        let quality = learning == nil ? qualityCard(record, snapshot: snapshot, format: format) : nil

        var label = "\(caption.capitalized), slept \(HomeFormat.spokenDuration(minutes)), \(bedtime) to \(wake)."
        if let ring { label += " " + ring.accessibilityLabel + "." }
        return SleepDayContent(
            night: record.night,
            caption: caption,
            duration: HomeFormat.durationMetric(minutes),
            minutes: minutes,
            timeRange: "\(bedtime) – \(wake)",
            ring: ring,
            learning: learning,
            chart: chart,
            stages: stages,
            quality: quality,
            details: detailTiles(record, format: format),
            accessibilityLabel: label
        )
    }

    static func ringContent(_ quality: SleepQualityResult, render: SleepDayRender) -> SleepQualityRingContent? {
        guard let ring = render.ring else { return nil }
        let typical = quality.usual.map { Int($0.rounded()) }
        var label = "Sleep quality \(quality.score)"
        if let typical { label += ", typical \(typical)" }
        label += ", \(quality.confidence.rawValue) confidence"
        return SleepQualityRingContent(
            score: quality.score, fraction: ring.fraction, usual: ring.usual, arc: ring.arc,
            typicalText: typical.map { "typical \($0)" }, accessibilityLabel: label
        )
    }

    static func stageCard(_ metrics: SleepMetrics, render: SleepDayRender) -> SleepStageCardContent? {
        guard !render.stageRows.isEmpty else { return nil }
        let rows = render.stageRows.map { row -> SleepStageRowContent in
            let minutes = Int(row.minutes.rounded())
            let percent = Int((row.share * 100).rounded())
            let usual = row.usual.map { Int(($0 * 100).rounded()) }
            var label = "\(row.stage.name) \(HomeFormat.spokenDuration(minutes)), \(percent) percent"
            if let usual { label += ", usual \(usual) percent" }
            return SleepStageRowContent(
                stage: row.stage,
                name: row.stage.name,
                duration: HomeFormat.durationMetric(minutes),
                shareText: "\(percent)%",
                share: row.share,
                usualText: usual.map { "usual \($0)%" },
                usual: row.usual,
                accessibilityLabel: label
            )
        }
        return SleepStageCardContent(rows: rows, footnote: "Shares of time asleep. Awake is a share of the time recorded.")
    }

    // MARK: Details

    static func detailTiles(_ record: SleepNightRecord, format: HomeFormat) -> [SleepDetailTile] {
        let session = record.session
        let metrics = record.metrics
        var tiles: [SleepDetailTile] = []
        if metrics.timeInBedMinutes > 0 {
            tiles.append(SleepDetailTile(id: "inBed", title: "Time in bed", value: HomeFormat.durationMetric(Int(metrics.timeInBedMinutes.rounded())), note: nil))
        }
        if let efficiency = metrics.efficiency {
            let percent = Int((efficiency * 100).rounded())
            tiles.append(SleepDetailTile(
                id: "efficiency", title: "Efficiency",
                value: NoctisMetricValue(parts: [.number("\(percent)"), .unit("%")], spoken: "\(percent) percent"),
                note: "asleep while in bed"
            ))
        }
        tiles.append(SleepDetailTile(id: "bedtime", title: "Bedtime", value: format.clockMetric(format.clock(session.bedtime, in: session.timeZone)), note: nil))
        tiles.append(SleepDetailTile(id: "wake", title: "Wake time", value: format.clockMetric(format.clock(session.wakeTime, in: session.timeZone)), note: nil))
        // Awakenings and time awake are only known when the source can show wakefulness.
        if metrics.awakeAfterOnsetMinutes != nil {
            tiles.append(SleepDetailTile(
                id: "awakenings", title: "Awakenings",
                value: NoctisMetricValue(parts: [.number("\(metrics.awakenings)")], spoken: "\(metrics.awakenings) \(metrics.awakenings == 1 ? "awakening" : "awakenings")"),
                note: nil
            ))
        }
        if let awake = metrics.awakeAfterOnsetMinutes {
            tiles.append(SleepDetailTile(id: "awake", title: "Time awake", value: HomeFormat.durationMetric(Int(awake.rounded())), note: "after falling asleep"))
        }
        return tiles
    }

    // MARK: Quality card

    static func qualityCard(_ record: SleepNightRecord, snapshot: SleepSnapshot, format: HomeFormat) -> SleepQualityCardContent {
        let quality = record.quality
        let metrics = record.metrics
        let window = snapshot.window(before: record.night)
        let windowMetrics = window.map(\.metrics)
        let need = snapshot.needMinutes

        let rows = quality.factors.map { factor -> SleepFactorRowContent in
            let sentence: String
            switch factor.kind {
            case .duration:
                sentence = durationSentence(asleep: Int(metrics.asleepMinutes.rounded()), need: need)
            case .continuity:
                sentence = continuitySentence(awakenings: metrics.awakenings, awake: Int((metrics.awakeAfterOnsetMinutes ?? 0).rounded()))
            case .consistency:
                sentence = consistencySentence(metrics, window: windowMetrics, format: format)
            case .stages:
                sentence = stagesSentence(quality.stageBalance)
            }
            return SleepFactorRowContent(kind: factor.kind, name: factorName(factor.kind), score: factor.score, fraction: Double(factor.score) / 100, sentence: sentence)
        }
        var omitted: [String] = []
        for kind in SleepQualityFactorKind.allCases {
            guard let gap = quality.missingFactors[kind] else { continue }
            omitted.append(omittedSentence(kind, gap: gap))
        }
        return SleepQualityCardContent(
            factors: rows,
            whatChanged: whatChanged(quality),
            confidence: confidenceLine(quality),
            calculation: calculation(quality, need: need),
            modelVersion: "Model \(quality.modelVersion)",
            omitted: omitted
        )
    }

    static func factorName(_ kind: SleepQualityFactorKind) -> String {
        switch kind {
        case .duration: "Duration"
        case .continuity: "Continuity"
        case .consistency: "Consistency"
        case .stages: "Stages"
        }
    }

    static func durationSentence(asleep: Int, need: Int) -> String {
        asleep >= need
            ? "You met your \(HomeFormat.compactDuration(need)) sleep need."
            : "You slept \(HomeFormat.compactDuration(asleep)) of your \(HomeFormat.compactDuration(need)) need."
    }

    static func continuitySentence(awakenings: Int, awake: Int) -> String {
        if awakenings == 0 && awake == 0 { return "No awakenings recorded." }
        let count = "\(awakenings) \(awakenings == 1 ? "awakening" : "awakenings")"
        return "\(count), \(HomeFormat.compactDuration(awake, minutesWord: true)) awake after falling asleep."
    }

    static func consistencySentence(_ metrics: SleepMetrics, window: [SleepMetrics], format: HomeFormat) -> String {
        guard let baseline = BaselineEngine.baseline(window.map(\.bedtimeMinutes)) else { return "Not enough nights yet to compare." }
        let difference = Int((metrics.bedtimeMinutes - baseline.value).rounded())
        let usual = format.clock(minutesAfterNoon: baseline.value)
        if abs(difference) < 10 { return "Bedtime was right around your usual \(usual)." }
        return "Bedtime was \(HomeFormat.compactDuration(abs(difference), minutesWord: true)) \(difference > 0 ? "later" : "earlier") than your usual \(usual)."
    }

    static func stagesSentence(_ balance: StageBalance?) -> String {
        guard let balance else { return "Stages aren't available from your current sources." }
        let percent = { (share: Double) in Int((share * 100).rounded()) }
        let outside = balance.rows.filter { !$0.isWithinRange }
        let rangeWords: String = if case .personal = balance.basis { "your usual range" } else { "the typical range" }
        if outside.isEmpty {
            let parts = [StageBalanceRow.Stage.deep, .core, .rem].compactMap { balance.row($0) }.map { "\(stageName($0.stage)) \(percent($0.share))%" }
            return "\(parts.joined(separator: ", ")): all within \(rangeWords)."
        }
        // The stage furthest outside its range.
        guard let worst = outside.max(by: { distance($0) < distance($1) }) else { return "" }
        let side = worst.share > worst.high ? "above" : "under"
        return "\(stageName(worst.stage)) was \(percent(worst.share))%, \(side) \(rangeWords) of \(percent(worst.low))–\(percent(worst.high))%."
    }

    private static func distance(_ row: StageBalanceRow) -> Double {
        max(row.low - row.share, row.share - row.high, 0)
    }

    static func stageName(_ stage: StageBalanceRow.Stage) -> String {
        switch stage {
        case .deep: "Deep"
        case .core: "Core"
        case .rem: "REM"
        }
    }

    static func omittedSentence(_ kind: SleepQualityFactorKind, gap: SleepQualityGap) -> String {
        switch (kind, gap) {
        case (.duration, _): "Duration isn't counted without a sleep need."
        case (.continuity, _): "Continuity isn't counted: your sources don't show time awake."
        case (.consistency, _): "Consistency joins once there are 5 nights to compare with."
        case (.stages, _): "Stages aren't counted: your sources don't record them."
        }
    }

    /// "What changed?" in one sentence, from the largest deviation from
    /// your usual: the same structure as Recovery's "why" line.
    static func whatChanged(_ quality: SleepQualityResult) -> String {
        guard quality.baselineNights >= BaselineEngine.minimumNights else {
            return "There aren't enough nights yet to compare with your usual."
        }
        guard let top = quality.topContributor else {
            return "Nothing stood out: this night was in line with your usual."
        }
        let minutes = Int(abs(top.difference).rounded())
        let amount = HomeFormat.compactDuration(minutes, minutesWord: true)
        switch top.measure {
        case .duration:
            return "Sleep was \(amount) \(top.isAbove ? "longer" : "shorter") than usual."
        case .bedtime:
            return "Bedtime was \(amount) \(top.isAbove ? "later" : "earlier") than usual."
        case .awakeTime:
            return "You were awake \(amount) \(top.isAbove ? "longer" : "less") than usual after falling asleep."
        case .deepShare:
            return "Deep sleep was a \(top.isAbove ? "larger" : "smaller") share of the night than usual."
        case .remShare:
            return "REM sleep was a \(top.isAbove ? "larger" : "smaller") share of the night than usual."
        }
    }

    static func confidenceLine(_ quality: SleepQualityResult) -> String {
        let word = quality.confidence.rawValue.capitalized
        switch quality.confidence {
        case .high: return "\(word) confidence · built on \(quality.baselineNights) nights of your own sleep"
        case .moderate: return "\(word) confidence · built on \(quality.baselineNights) nights of your own sleep"
        case .low: return "\(word) confidence · it firms up as more nights arrive"
        }
    }

    static func calculation(_ quality: SleepQualityResult, need: Int) -> [String] {
        let weights = Model.weights
        let weight = { (kind: SleepQualityFactorKind) in Int(weights[kind] ?? 0) }
        let used = quality.factorsUsed.map { factorName($0).lowercased() }
        return [
            "Sleep quality describes how a night compared with your sleep need, your own pattern and typical sleep. It isn't a medical measurement, and it says nothing about your health.",
            "It blends four things: duration (\(weight(.duration)) of 100), continuity (\(weight(.continuity))), consistency (\(weight(.consistency))) and stages (\(weight(.stages))). Anything your data can't support is left out, and the rest share its weight. This night used \(used.formatted(.list(type: .and))).",
            "Duration is 100 at or above your \(HomeFormat.compactDuration(need)) need, and falls as you get further under it. Continuity looks at time awake after falling asleep and awakenings. Consistency compares your bedtime with your usual over the last \(BaselineEngine.windowNights) nights. Stages compare Deep, Core and REM shares with your own usual range once you have \(Model.personalStageNights) nights of stages, and with typical ranges before that.",
        ]
    }
}
