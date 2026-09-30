import Foundation
import HomeFeature
import InsightsKit
import NoctisCore
import RecoveryKit
import SleepAnalysisKit
import SleepKit

/// The app's four snapshots, as Coach reads them. Coach reads the same
/// derived values the tabs show (R20) and never touches Health itself.
public struct CoachSnapshots: Sendable {
    public var home: HomeSnapshot?
    public var sleep: SleepSnapshot?
    public var recovery: RecoverySnapshot?
    public var insights: InsightsSnapshot?

    public init(home: HomeSnapshot? = nil, sleep: SleepSnapshot? = nil, recovery: RecoverySnapshot? = nil, insights: InsightsSnapshot? = nil) {
        self.home = home
        self.sleep = sleep
        self.recovery = recovery
        self.insights = insights
    }
}

/// Builds the slice of the person's data one question may use.
///
/// What goes in: derived numbers with a label and an engine's name. What
/// never does: the person's name, an account id, a raw HealthKit sample, the
/// time of any one sample, journal text, or the name of the app or device a
/// sample came from. A number that isn't there is a fact that is absent:
/// never zero, never a guess.
public struct CoachContextBuilder: Sendable {
    /// Under this many nights Home is still learning the baseline.
    public static let learningNights = RecoveryModelV1.learningNights
    /// Nights for a moderate, and for a high, confidence ceiling.
    public static let moderateNights = RecoveryModelV1.moderateConfidenceNights
    public static let highNights = RecoveryModelV1.highConfidenceNights
    /// Nights a week's average needs, and a baseline of stage shares.
    public static let minimumWeekNights = 4
    /// "Within this many minutes" of a usual bedtime: the Insights streak's.
    public static let bedtimeToleranceMinutes = InsightEngine.streakToleranceMinutes

    private let formatter: CoachFactFormatter

    public init(format: HomeFormat) {
        formatter = CoachFactFormatter(format: format)
    }

    /// Every fact the snapshots support (no insights): what the hub reads to
    /// decide which questions are worth asking.
    public func allFacts(snapshots: CoachSnapshots, profile: UserProfileSnapshot) -> [CoachFact] {
        let state = Self.dataState(snapshots)
        return allFacts(snapshots, state: state, profile: profile, nights: Self.nightsOfHistory(snapshots))
    }

    public func build(
        intent: CoachIntent, direction: CoachDirection?, snapshots: CoachSnapshots, profile: UserProfileSnapshot
    ) -> CoachContext {
        let state = Self.dataState(snapshots)
        let nights = Self.nightsOfHistory(snapshots)
        let chosen = Self.chosenInsights(for: intent, snapshots.insights)
        var facts = allFacts(snapshots, state: state, profile: profile, nights: nights)
        var briefs: [CoachInsightBrief] = []
        for record in chosen {
            let insightFacts = insightFacts(record)
            facts += insightFacts
            briefs.append(CoachInsightBrief(id: record.id, type: record.type, confidence: record.confidence, factIDs: insightFacts.map(\.id)))
        }
        let (available, missing) = Self.factors(snapshots, state: state)
        return CoachContext(
            intent: intent,
            direction: direction,
            facts: Self.slice(facts, for: intent),
            insights: briefs,
            availableFactors: available,
            missingFactors: missing,
            nightsOfHistory: nights,
            dataState: state,
            goalIDs: Self.goalIDs(profile),
            sleepNeedMinutes: profile.needMinutes,
            confidenceCeiling: Self.ceiling(state: state, result: snapshots.recovery?.result ?? Self.result(snapshots.home), nights: nights)
        )
    }

    // MARK: - State

    public static func dataState(_ snapshots: CoachSnapshots) -> CoachDataState {
        let state = snapshots.home?.dataState ?? snapshots.recovery?.dataState ?? snapshots.sleep?.dataState
        switch state {
        case .ready?: return .ready
        case .learning?: return .learning
        case .noSleepLastNight?: return .noSleepLastNight
        case .stale?: return .stale
        case .empty?, .permissionRequired?, .healthDataUnavailable?, .failed?, nil: return .noData
        }
    }

    /// Nights recorded, as far as any snapshot knows.
    public static func nightsOfHistory(_ snapshots: CoachSnapshots) -> Int {
        var counts = [
            snapshots.insights?.nightsRecorded ?? 0,
            snapshots.sleep?.records.count ?? 0,
            snapshots.home?.recentNights.filter { $0.asleepMinutes != nil }.count ?? 0,
        ]
        if case .learning(let so)? = snapshots.home?.dataState { counts.append(so) }
        return counts.max() ?? 0
    }

    /// The most confidence an answer may claim: the data's, never more.
    public static func ceiling(state: CoachDataState, result: RecoveryResult?, nights: Int) -> CoachConfidence {
        guard state == .ready else { return .low }
        var ceiling: CoachConfidence = nights >= highNights ? .high : (nights >= moderateNights ? .moderate : .low)
        if let result, let recovery = CoachConfidence(rawValue: result.confidence.rawValue) { ceiling = min(ceiling, recovery) }
        return ceiling
    }

    static func result(_ home: HomeSnapshot?) -> RecoveryResult? {
        if case .scored(let result)? = home?.recovery { return result }
        return nil
    }

    static func goalIDs(_ profile: UserProfileSnapshot) -> [String] {
        var goals = profile.selectedGoals.isEmpty ? [profile.primaryGoal] : profile.selectedGoals
        if let secondary = profile.secondaryGoal, !goals.contains(secondary) { goals.append(secondary) }
        return goals.map(\.rawValue)
    }

    // MARK: - Factors

    static func factors(_ snapshots: CoachSnapshots, state: CoachDataState) -> (available: [String], missing: [CoachMissingFactor]) {
        let all = RecoveryFactorKind.allCases
        if let result = snapshots.recovery?.result ?? result(snapshots.home) {
            let used = result.factorsUsed
            let missing = all.compactMap { kind -> CoachMissingFactor? in
                guard !used.contains(kind) else { return nil }
                let reason: CoachMissingReason = switch result.missingFactors[kind] {
                case .unavailable?: .notProvided
                case .notRecorded?: .notRecorded
                case .buildingBaseline?: .needsMoreNights
                case nil: .notRecorded
                }
                return CoachMissingFactor(factor: kind.rawValue, reason: reason)
            }
            return (all.filter(used.contains).map(\.rawValue), missing)
        }
        switch state {
        case .learning: return ([], all.map { CoachMissingFactor(factor: $0.rawValue, reason: .needsMoreNights) })
        case .noSleepLastNight, .stale: return ([], all.map { CoachMissingFactor(factor: $0.rawValue, reason: .notRecorded) })
        case .ready, .noData: return ([], [])
        }
    }

    // MARK: - Facts

    private func allFacts(_ s: CoachSnapshots, state: CoachDataState, profile: UserProfileSnapshot, nights: Int) -> [CoachFact] {
        var facts: [CoachFact] = []
        func add(_ id: String, _ label: String, _ value: Double?, _ unit: CoachUnit, _ source: String, magnitude: Bool = false) {
            guard let value, value.isFinite else { return }
            facts.append(formatter.fact(id, label, value, unit, source: source, magnitude: magnitude))
        }

        let result = s.recovery?.result ?? Self.result(s.home)

        // Last night: only while there is one.
        let lastNight = state == .ready || state == .learning ? Self.lastNightKey(s) : nil
        let record = lastNight.flatMap { s.sleep?.record($0) }
        let session = record?.session ?? s.home?.lastNight
        let metrics = record?.metrics ?? session.map { SleepMetricsEngine.metrics(for: $0) }
        let window = lastNight.flatMap { s.sleep?.window(before: $0) } ?? []

        if let metrics {
            add("sleep.duration", "Time asleep last night", metrics.asleepMinutes, .duration, "SleepMetricsEngine")
            let usual = result?.baselines.sleepDuration?.value
                ?? BaselineEngine.baseline(window.map(\.metrics.asleepMinutes))?.value
            add("sleep.baseline", "Usual time asleep", usual, .duration, "BaselineEngine")
            add("sleep.deltaVsBaseline", "Time asleep against usual", usual.map { metrics.asleepMinutes - $0 }, .duration, "BaselineEngine", magnitude: true)

            add("bedtime.last", "Bedtime last night", metrics.bedtimeMinutes, .clock, "SleepMetricsEngine")
            if let typical = s.sleep?.timing?.typicalBedtime {
                add("bedtime.deltaVsUsual", "Bedtime against usual", metrics.bedtimeMinutes - typical, .duration, "SleepTimingEngine", magnitude: true)
            }

            if let shares = metrics.stages?.asleepShares {
                add("deep.share", "Deep sleep, share of the night", shares.deep * 100, .percent, "SleepMetricsEngine")
                add("rem.share", "REM sleep, share of the night", shares.rem * 100, .percent, "SleepMetricsEngine")
                let staged = window.compactMap { $0.metrics.stages?.asleepShares }
                if staged.count >= BaselineEngine.minimumNights {
                    add("deep.usual", "Usual deep sleep share", staged.map(\.deep).reduce(0, +) / Double(staged.count) * 100, .percent, "SleepMetricsEngine")
                    add("rem.usual", "Usual REM sleep share", staged.map(\.rem).reduce(0, +) / Double(staged.count) * 100, .percent, "SleepMetricsEngine")
                }
            }
        }
        if lastNight != nil {
            let quality = record?.quality
            let score = quality.flatMap { $0.isScored ? Double($0.score) : nil } ?? s.home?.lastNightSleepQuality.map(Double.init)
            add("sleep.quality", "Sleep quality last night", score, .points, "SleepQualityEngine")
            add("sleep.qualityUsual", "Usual sleep quality", quality?.usual, .points, "SleepQualityEngine")
        }

        // Your usual bedtime doesn't wait for last night.
        add("bedtime.usual", "Usual bedtime", s.sleep?.timing?.typicalBedtime, .clock, "SleepTimingEngine")
        add("sleep.need", "Your sleep need", Double(profile.needMinutes), .duration, "Profile")
        add("wake.typical", "Your usual wake time", CoachFactFormatter.afterNoon(sinceMidnight: profile.typicalWakeMinutes), .clock, "Profile")
        let plan = s.home?.tonight ?? TonightPlan(profile: profile)
        add("bedtime.suggested", "Bedtime that fits your sleep need", CoachFactFormatter.afterNoon(sinceMidnight: plan.bedtimeMinutes), .clock, "Profile")
        if let balance = s.sleep?.balance?.minutes {
            add("sleep.balance", "Sleep against your need, past week", balance, .duration, "SleepBalanceEngine", magnitude: true)
        }

        // Recovery: today's score and what it was built from.
        if let result {
            add("recovery.score", "Recovery today", Double(result.score), .points, "RecoveryEngine")
            add("recovery.usual", "Usual recovery", result.comparison.baseline, .points, "RecoveryEngine")
            add("recovery.deltaVsUsual", "Recovery against usual", result.comparison.delta.map(Double.init), .points, "RecoveryEngine", magnitude: true)
            if let hrv = result.factor(.hrv) {
                add("hrv.today", "HRV last night", hrv.value, .milliseconds, "RecoveryEngine")
                add("hrv.baseline", "Usual HRV", hrv.baseline, .milliseconds, "BaselineEngine")
            }
            if let rhr = result.factor(.restingHeartRate) {
                add("rhr.today", "Resting heart rate last night", rhr.value, .beatsPerMinute, "RecoveryEngine")
                add("rhr.baseline", "Usual resting heart rate", rhr.baseline, .beatsPerMinute, "BaselineEngine")
            }
        }

        // The week.
        let week = Self.weekAverages(s)
        add("week.avgSleep", "Average night, past week", s.home?.weekAverageMinutes ?? week.recent, .duration, "HomeSnapshotBuilder")
        add("week.avgSleepDelta", "Average night against the week before", week.change, .duration, "CoachContextBuilder", magnitude: true)
        if let history = s.recovery?.history(.week) {
            add("week.avgRecovery", "Average recovery, past week", history.stats.average, .points, "RecoveryHistoryEngine")
            add("week.recoveryTrend", "Recovery trend, points a week", history.stats.trend?.pointsPerWeek, .points, "RecoveryHistoryEngine", magnitude: true)
        }

        // Consistency.
        if let consistency = s.sleep?.consistency, let window = consistency.window(days: 7) ?? consistency.window(days: 14) {
            add("consistency.bedtimeVarMin", "How much your bedtime varies", window.bedtimeSD, .minutes, "ConsistencyEngine")
            add("consistency.toleranceMin", "A steady bedtime, within", Self.bedtimeToleranceMinutes, .minutes, "InsightEngine")
        }

        if nights > 0 { add("history.nights", "Nights recorded", Double(nights), .count, "InsightsSnapshot") }
        return facts
    }

    /// The night that is "last night": Home's, else the newest Sleep has when
    /// Sleep's data is current.
    static func lastNightKey(_ s: CoachSnapshots) -> SleepNightKey? {
        if let night = s.home?.lastNight?.night { return night }
        if s.home == nil, s.sleep?.dataState == .ready { return s.sleep?.records.last?.night }
        return nil
    }

    /// The last 7 nights' mean minutes asleep, and how it changed from the 7
    /// before; each needs `minimumWeekNights` recorded nights.
    static func weekAverages(_ s: CoachSnapshots) -> (recent: Double?, change: Double?) {
        guard let sleep = s.sleep, let end = lastNightKey(s) ?? sleep.records.last?.night else { return (nil, nil) }
        let minutes = sleep.nights(endingAt: end, count: 14).map { $0.record?.metrics.asleepMinutes }
        func mean(_ values: ArraySlice<Double?>) -> Double? {
            let present = values.compactMap { $0 }
            return present.count >= minimumWeekNights ? present.reduce(0, +) / Double(present.count) : nil
        }
        let recent = mean(minutes[7...])
        let prior = mean(minutes[..<7])
        let change: Double? = if let recent, let prior { recent - prior } else { nil }
        return (recent, change)
    }

    // MARK: - Insights

    /// The insights a question may lean on: at most `CoachContext.maxInsights`,
    /// the most confident first.
    static func chosenInsights(for intent: CoachIntent, _ snapshot: InsightsSnapshot?) -> [InsightRecord] {
        guard intent.usesData, let snapshot else { return [] }
        let categories: Set<InsightCategory> = switch intent {
        case .recoveryChange: [.recovery, .heart, .sleep]
        case .sleepChange: [.sleep, .timing]
        case .bedtimeAdvice: [.timing, .consistency]
        case .consistencyHelp: [.consistency, .timing]
        default: Set(InsightCategory.allCases)
        }
        var seen = Set<String>()
        let pool = ([snapshot.featured].compactMap { $0 } + snapshot.recent.map(\.record)).filter { seen.insert($0.id).inserted }
        return pool
            .filter { categories.contains($0.category) }
            .sorted { ($0.confidence, $0.relevance) > ($1.confidence, $1.relevance) }
            .prefix(CoachContext.maxInsights).map { $0 }
    }

    /// One insight's numbers, as facts: "insight.<type>.<name>".
    func insightFacts(_ record: InsightRecord) -> [CoachFact] {
        let type = record.type.rawValue
        var facts: [CoachFact] = []
        func add(_ name: String, _ label: String, _ value: Double, _ unit: CoachUnit, magnitude: Bool = false) {
            facts.append(formatter.fact("insight.\(type).\(name)", label, value, unit, source: "InsightEngineV2", magnitude: magnitude))
        }
        switch record.evidence {
        case .baseline(let e):
            if record.type == .consistentBedtime {
                add("streak", "Nights in a row near your usual bedtime", Double(e.streakNights ?? 0), .count)
                add("usual", "Your usual bedtime", e.baseline, .clock)
            } else {
                add("delta", record.type == .bedtimeShift ? "Bedtime against usual" : "Time asleep against usual", e.delta, .duration, magnitude: true)
            }
        case .pattern(let e):
            add("earlyMean", "Average on nights with an earlier bedtime", e.earlyMean, .points)
            add("lateMean", "Average on nights with a later bedtime", e.lateMean, .points)
        case .recoveryDirection(let e):
            add("perWeek", "Recovery change, points a week", e.pointsPerWeek, .points, magnitude: true)
        case .heartSignal(let e):
            let unit: CoachUnit = e.signal == .hrv ? .milliseconds : .beatsPerMinute
            add("value", e.signal == .hrv ? "HRV last night" : "Resting heart rate last night", e.value, unit)
            add("baseline", e.signal == .hrv ? "Usual HRV" : "Usual resting heart rate", e.baseline, unit)
        case .consistencyChange(let e):
            add("recentSD", "Bedtime spread, recent nights", e.recentSD, .minutes)
            add("previousSD", "Bedtime spread, the nights before", e.previousSD, .minutes)
        case .balance(let e):
            add("minutes", "Sleep against your need, past week", e.minutes, .duration, magnitude: true)
        case .weekend(let e):
            add("delta", "Weekend bedtime against weekdays", e.delta, .duration, magnitude: true)
        case .stageShare(let e):
            add("\(e.stage.rawValue).share", "\(e.stage == .deep ? "Deep" : "REM") sleep, share of the night", e.share * 100, .percent)
            add("\(e.stage.rawValue).usual", "Usual \(e.stage == .deep ? "deep" : "REM") sleep share", e.usual * 100, .percent)
        case .record(let e):
            switch record.type {
            case .recordLongestNight: add("value", "Longest night", e.value, .duration)
            case .recordBestConsistency: add("value", "Steadiest week, bedtime spread", e.value, .minutes)
            case .recordHighestRecovery: add("value", "Highest recovery", e.value, .points)
            default: add("value", "Lowest resting heart rate", e.value, .beatsPerMinute)
            }
        case .milestone(let e):
            add("nights", "Nights recorded", Double(e.nightsRecorded), .count)
        }
        return facts
    }

    // MARK: - Slices

    /// The id prefixes a question may see, most useful first.
    static func prefixes(for intent: CoachIntent) -> [String] {
        switch intent {
        case .recoveryChange:
            ["recovery.", "hrv.", "rhr.", "sleep.duration", "sleep.deltaVsBaseline", "sleep.baseline", "sleep.quality", "bedtime.last", "bedtime.usual", "bedtime.deltaVsUsual", "insight.", "history."]
        case .sleepChange:
            ["sleep.duration", "sleep.deltaVsBaseline", "sleep.baseline", "sleep.quality", "deep.", "rem.", "bedtime.last", "bedtime.usual", "bedtime.deltaVsUsual", "sleep.balance", "insight.", "history."]
        case .weekChange:
            ["week.", "sleep.balance", "consistency.", "recovery.score", "recovery.usual", "insight.", "history."]
        case .bedtimeAdvice:
            ["bedtime.", "wake.", "sleep.need", "sleep.balance", "consistency.", "insight.", "history."]
        case .consistencyHelp:
            ["consistency.", "bedtime.", "insight.", "history."]
        case .todayFocus:
            ["recovery.", "hrv.", "rhr.", "sleep.balance", "bedtime.suggested", "sleep.duration", "sleep.deltaVsBaseline", "insight.", "history."]
        case .patterns:
            ["insight.", "week.", "history."]
        case .medicalOutOfScope, .crisis, .unknown:
            []
        }
    }

    /// The facts whose ids start with one of `intent`'s prefixes, in prefix
    /// order, at most `CoachContext.maxFacts`.
    static func slice(_ facts: [CoachFact], for intent: CoachIntent) -> [CoachFact] {
        var out: [CoachFact] = []
        var taken = Set<String>()
        for prefix in prefixes(for: intent) {
            for fact in facts where fact.id.hasPrefix(prefix) && taken.insert(fact.id).inserted { out.append(fact) }
        }
        return Array(out.prefix(CoachContext.maxFacts))
    }
}

extension CoachConfidence {
    init(_ insight: InsightConfidence) {
        self = CoachConfidence(rawValue: insight.rawValue) ?? .low
    }
}
