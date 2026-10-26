import Foundation
import InsightsKit
import RecoveryKit

/// Answers from the person's own data with no model: the same facts, put into
/// sentences the app wrote in advance (the String Catalog). It ships, works
/// offline and without Apple Intelligence, and is what Coach falls back to
/// when a model is unavailable, too slow, or writes something the validator
/// turns away. Deterministic: one intent, one direction, one set of facts, one
/// answer.
///
/// Every number is a `{{fact.id}}` token, and a sentence is only used when
/// every fact it names is in the context: a number the app doesn't have is
/// never written, only an honest "I need more nights".
public struct TemplateCoachProvider: AIProvider {
    /// A difference under this many minutes is "about the same" (Recovery's own floor for a normal range).
    public static let minorMinutes = RecoveryNormalRange.sleepDurationStandardDeviationFloor
    /// Recovery moves this many points before it counts as above or below usual.
    public static let recoveryThreshold = Double(RecoveryModelV1.trendThreshold)

    private let copy: @Sendable (String) -> String
    private let locale: Locale

    public init(locale: Locale = .current, copy: @escaping @Sendable (String) -> String = { CoachCopy.string($0) }) {
        self.locale = locale
        self.copy = copy
    }

    public var kind: CoachSourceKind { .fromYourData }
    public var availability: CoachAvailability { .available }

    public func draft(question: String, intent: CoachIntent, context: CoachContext) async throws -> CoachAnswerDraft {
        compose(intent: intent, context: context)
    }

    /// The draft for `intent`, synchronously.
    public func compose(intent: CoachIntent, context: CoachContext) -> CoachAnswerDraft {
        let composer = Composer(context: context, copy: copy, locale: locale)
        switch context.dataState {
        case .noData: return composer.gap("noData")
        case .learning: return composer.gap(context.has("history.nights") ? "learning" : "sparse")
        case .ready, .stale, .noSleepLastNight: break
        }
        let draft: CoachAnswerDraft? =
            switch intent {
            case .recoveryChange: composer.recoveryChange()
            case .sleepChange: composer.sleepChange()
            case .weekChange: composer.weekChange()
            case .bedtimeAdvice: composer.bedtimeAdvice()
            case .consistencyHelp: composer.consistencyHelp()
            case .todayFocus: composer.todayFocus()
            case .patterns: composer.patterns()
            case .medicalOutOfScope, .crisis, .unknown: nil
            }
        return draft ?? composer.gap(composer.gapKind)
    }
}

// MARK: - Composer

private struct Composer {
    let context: CoachContext
    let copy: @Sendable (String) -> String
    let locale: Locale

    private var minor: Double { TemplateCoachProvider.minorMinutes }
    private var threshold: Double { TemplateCoachProvider.recoveryThreshold }

    /// Which "not enough" copy fits the state.
    var gapKind: String {
        switch context.dataState {
        case .noData: "noData"
        case .learning: "learning"
        case .stale: "stale"
        case .noSleepLastNight: "gap"
        case .ready: "sparse"
        }
    }

    // MARK: Pieces

    func value(_ id: String) -> Double? { context.fact(id)?.value }

    /// The catalog string, only when every fact it names is in the context.
    func text(_ key: String) -> String? {
        let text = copy("coach.tpl.\(key)")
        return CoachTokens.ids(in: text).allSatisfy(context.has) ? text : nil
    }

    func label(_ key: String) -> String { copy("coach.tpl.contrib.\(key)") }

    func contributor(_ labelKey: String, _ factID: String) -> CoachDraftContributor? {
        context.has(factID) ? CoachDraftContributor(label: label(labelKey), factID: factID) : nil
    }

    func join(_ parts: [String]) -> String {
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: parts) ?? parts.joined(separator: ", ")
    }

    /// "Compared with your recent baseline: a, b and c." (or `none`).
    func changed(_ clauses: [String?], none: String) -> String {
        let present = clauses.compactMap { $0 }
        guard !present.isEmpty else { return copy("coach.tpl.\(none)") }
        return copy("coach.tpl.changed.prefix") + join(present) + "."
    }

    var caution: String? { CoachCautions.text(for: context, copy: copy) }

    func draft(
        summary: String, contributors: [CoachDraftContributor?] = [], changed: String, notice: String, tonight: String? = nil,
        pattern: String? = nil, destinations: [String] = [], confidence: CoachConfidence? = nil
    ) -> CoachAnswerDraft {
        let level = min(confidence ?? context.confidenceCeiling, context.confidenceCeiling)
        return CoachAnswerDraft(
            summary: summary,
            contributors: Array(contributors.compactMap { $0 }.prefix(CoachSafetyValidator.maxContributors)),
            whatChanged: changed,
            whatToNotice: notice,
            tonightSuggestion: tonight,
            pattern: pattern,
            confidence: level,
            caution: level == .high ? nil : (caution ?? copy("coach.caution.evidence")),
            destinations: destinations
        )
    }

    /// An honest "not enough": no numbers it doesn't have.
    func gap(_ requested: String) -> CoachAnswerDraft {
        let kind = requested == "learning" && !context.has("history.nights") ? "sparse" : requested
        return draft(
            summary: text("\(kind).summary") ?? copy("coach.tpl.sparse.summary"),
            changed: copy("coach.tpl.\(kind).changed"),
            notice: copy("coach.tpl.\(kind).notice"),
            confidence: .low
        )
    }

    /// Whether the question leaned a way the data doesn't: said in `whatToNotice`.
    func noticed(_ notice: String, dataDirection: CoachDirection?) -> String {
        guard let asked = context.direction, let actual = dataDirection, asked != actual else { return notice }
        return copy("coach.tpl.mismatch") + " " + notice
    }

    func sign(_ value: Double?, minor: Double) -> CoachDirection? {
        guard let value else { return nil }
        return value <= -minor ? .lower : (value >= minor ? .higher : .same)
    }

    // MARK: Shared clauses

    func sleepClause() -> String? {
        guard let delta = value("sleep.deltaVsBaseline"), abs(delta) >= minor else { return nil }
        return text(delta < 0 ? "clause.sleep.shorter" : "clause.sleep.longer")
    }

    func bedtimeClause() -> String? {
        guard let delta = value("bedtime.deltaVsUsual"), abs(delta) >= minor else { return nil }
        return text(delta > 0 ? "clause.bedtime.later" : "clause.bedtime.earlier")
    }

    /// "Behind your sleep need by 2h 42m": which way is in the words, the size in the value.
    func balanceContributor() -> CoachDraftContributor? {
        guard let balance = value("sleep.balance") else { return nil }
        return contributor(balance < 0 ? "balance.behind" : "balance.ahead", "sleep.balance")
    }

    func balanceClause() -> String? {
        guard let balance = value("sleep.balance"), abs(balance) >= minor else { return nil }
        return text(balance < 0 ? "clause.balance.behind" : "clause.balance.ahead")
    }

    // MARK: Intents

    func recoveryChange() -> CoachAnswerDraft? {
        guard context.has("recovery.score") else { return nil }
        let delta = value("recovery.deltaVsUsual")
        let direction = sign(delta, minor: threshold)
        let summary =
            switch direction {
            case .lower?: text("rc.summary.lower")
            case .higher?: text("rc.summary.higher")
            case .same?: text("rc.summary.same")
            case nil: text("rc.summary.noBaseline")
            }
        guard let summary else { return nil }
        let notice = copy("coach.tpl.rc.notice.\(direction?.rawValue ?? "same")")
        return draft(
            summary: summary,
            contributors: [
                value("sleep.deltaVsBaseline").flatMap {
                    abs($0) >= minor ? contributor($0 < 0 ? "sleep.shorter" : "sleep.longer", "sleep.deltaVsBaseline") : nil
                },
                contributor("hrv", "hrv.today"), contributor("rhr", "rhr.today"),
                value("bedtime.deltaVsUsual").flatMap {
                    abs($0) >= minor ? contributor($0 > 0 ? "bedtime.later" : "bedtime.earlier", "bedtime.deltaVsUsual") : nil
                },
            ],
            changed: changed(
                [sleepClause(), text("clause.hrv"), text("clause.rhr"), bedtimeClause()], none: "rc.changed.none"
            ),
            notice: noticed(notice, dataDirection: direction),
            tonight: text("tonight.bedtime"),
            destinations: ["recovery"]
        )
    }

    func sleepChange() -> CoachAnswerDraft? {
        guard context.has("sleep.duration") else { return nil }
        let direction = sign(value("sleep.deltaVsBaseline"), minor: minor)
        let summary =
            switch direction {
            case .lower?: text("sc.summary.lower")
            case .higher?: text("sc.summary.higher")
            case .same?: text("sc.summary.same")
            case nil: text("sc.summary.noBaseline")
            }
        guard let summary else { return nil }
        let quality = text("clause.quality") ?? text("clause.quality.only")
        return draft(
            summary: summary,
            contributors: [
                contributor("duration", "sleep.duration"), contributor("quality", "sleep.quality"), contributor("bedtimeLast", "bedtime.last"),
            ],
            changed: changed([quality, text("clause.deep"), text("clause.rem"), bedtimeClause()], none: "sc.changed.none"),
            notice: noticed(copy("coach.tpl.sc.notice"), dataDirection: direction),
            tonight: text("tonight.bedtime"),
            destinations: ["sleep"]
        )
    }

    func weekChange() -> CoachAnswerDraft? {
        guard context.has("week.avgSleep") else { return nil }
        let direction = sign(value("week.avgSleepDelta"), minor: minor)
        let summary =
            switch direction {
            case .lower?: text("wc.summary.less")
            case .higher?: text("wc.summary.more")
            case .same?: text("wc.summary.same")
            case nil: text("wc.summary.noPrior")
            }
        guard let summary else { return nil }
        let trend = value("week.recoveryTrend").flatMap { abs($0) >= RecoveryHistoryModel.trendPointsPerWeek ? $0 : nil }
        return draft(
            summary: summary,
            contributors: [
                contributor("weekSleep", "week.avgSleep"), contributor("weekRecovery", "week.avgRecovery"),
                balanceContributor(), contributor("spread", "consistency.bedtimeVarMin"),
            ],
            changed: changed(
                [
                    balanceClause(), trend.flatMap { text($0 > 0 ? "clause.recoveryTrend.up" : "clause.recoveryTrend.down") },
                    text("clause.bedtimeSpread"),
                ],
                none: "wc.changed.none"
            ),
            notice: noticed(copy("coach.tpl.wc.notice"), dataDirection: direction),
            tonight: text("tonight.bedtime"),
            destinations: ["sleep:week"]
        )
    }

    func bedtimeAdvice() -> CoachAnswerDraft? {
        guard let summary = text("ba.summary") else { return nil }
        return draft(
            summary: summary,
            contributors: [
                contributor("bedtimeSuggested", "bedtime.suggested"), contributor("need", "sleep.need"), contributor("bedtimeUsual", "bedtime.usual"),
            ],
            changed: text("ba.changed.usual") ?? copy("coach.tpl.ba.changed.none"),
            notice: copy("coach.tpl.ba.notice"),
            tonight: text("ba.tonight"),
            destinations: ["sleep"]
        )
    }

    func consistencyHelp() -> CoachAnswerDraft? {
        let brief = context.insights.first { [.consistencyChange, .weekendShift, .consistentBedtime].contains($0.type) }
        guard let summary = text("ch.summary") ?? text("ch.summary.noUsual") else {
            return draft(
                summary: copy("coach.tpl.ch.summary.noSpread"), changed: copy("coach.tpl.sparse.changed"),
                notice: copy("coach.tpl.sparse.notice"), confidence: .low
            )
        }
        return draft(
            summary: summary,
            contributors: [contributor("spread", "consistency.bedtimeVarMin"), contributor("bedtimeUsual", "bedtime.usual")],
            changed: brief.flatMap { insightSentence($0) } ?? copy("coach.tpl.ch.changed.none"),
            notice: copy("coach.tpl.ch.notice"),
            tonight: text("ch.tonight"),
            destinations: ["sleep:week"],
            confidence: brief.map { CoachConfidence($0.confidence) }
        )
    }

    func todayFocus() -> CoachAnswerDraft? {
        let recoveryDirection = sign(value("recovery.deltaVsUsual"), minor: threshold)
        let balance = value("sleep.balance").map { $0 <= -minor }
        var contributors: [CoachDraftContributor?] = []
        let summary: String?
        if let heart = text("tf.summary.heart") {
            summary = heart
            contributors = [contributor("hrvBelow", "insight.hrvBelowRange.value")]
        } else if let heart = text("tf.summary.rhr") {
            summary = heart
            contributors = [contributor("rhrAbove", "insight.restingHeartRateAboveRange.value")]
        } else if balance == true, let text = text("tf.summary.balance") {
            summary = text
            contributors = [balanceContributor()]
        } else if recoveryDirection == .lower, let text = text("tf.summary.recovery") {
            summary = text
            contributors = [contributor("recovery", "recovery.score")]
        } else if context.has("recovery.score") {
            summary = copy("coach.tpl.tf.summary.steady")
            contributors = [contributor("recovery", "recovery.score")]
        } else {
            summary = text("tf.summary.sparse")
        }
        guard let summary else { return nil }
        return draft(
            summary: summary,
            contributors: contributors,
            changed: changed([sleepClause(), balanceClause(), bedtimeClause()], none: "tf.changed.none"),
            notice: copy("coach.tpl.tf.notice"),
            tonight: text("tf.tonight"),
            destinations: ["recovery"]
        )
    }

    func patterns() -> CoachAnswerDraft? {
        let sentences = context.insights.compactMap { brief in insightSentence(brief).map { (brief, $0) } }
        guard !sentences.isEmpty else {
            return draft(
                summary: copy("coach.tpl.pt.summary.none"), contributors: [contributor("nights", "history.nights")],
                changed: copy("coach.tpl.pt.changed.none"), notice: copy("coach.tpl.pt.notice"), destinations: ["insights"]
            )
        }
        let facts = Dictionary(context.facts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pattern = sentences.first { $0.0.type.isPattern }?.1
        // As many of the other sentences as fit in a field, most confident first.
        var changed = ""
        for (brief, sentence) in sentences where !brief.type.isPattern {
            let next = changed.isEmpty ? sentence : changed + " " + sentence
            if CoachTokens.visibleLength(next, facts: facts) > CoachSafetyValidator.fieldLimit { break }
            changed = next
        }
        let confidence = sentences.map { CoachConfidence($0.0.confidence) }.min()
        return draft(
            summary: copy("coach.tpl.pt.summary.some"),
            contributors: [contributor("nights", "history.nights")],
            changed: changed.isEmpty ? (pattern ?? copy("coach.tpl.pt.changed.none")) : changed,
            notice: copy("coach.tpl.pt.notice"),
            pattern: pattern,
            destinations: ["insights"] + sentences.prefix(1).map { "insight:\($0.0.id)" },
            confidence: confidence
        )
    }

    // MARK: Insights

    /// One hedged sentence for an insight, by its type and which way its numbers point.
    func insightSentence(_ brief: CoachInsightBrief) -> String? {
        let type = brief.type
        let prefix = "insight.\(type.rawValue)"
        func signed(_ name: String) -> Double? { value("\(prefix).\(name)") }
        let key: String
        switch type {
        case .sleepDurationShift:
            guard let delta = signed("delta") else { return nil }
            key = delta < 0 ? "insight.sleepDurationShift.shorter" : "insight.sleepDurationShift.longer"
        case .bedtimeShift:
            guard let delta = signed("delta") else { return nil }
            key = delta > 0 ? "insight.bedtimeShift.later" : "insight.bedtimeShift.earlier"
        case .recoveryDirection:
            guard let slope = signed("perWeek") else { return nil }
            key = slope >= 0 ? "insight.recoveryDirection.up" : "insight.recoveryDirection.down"
        case .sleepBalance:
            guard let minutes = signed("minutes") else { return nil }
            key = minutes < 0 ? "insight.sleepBalance.behind" : "insight.sleepBalance.ahead"
        case .weekendShift:
            guard let delta = signed("delta") else { return nil }
            key = delta > 0 ? "insight.weekendShift.later" : "insight.weekendShift.earlier"
        case .stageShare:
            let stage = brief.factIDs.first { $0.contains(".rem.") } != nil ? "rem" : "deep"
            guard let share = value("\(prefix).\(stage).share"), let usual = value("\(prefix).\(stage).usual") else { return nil }
            key = "insight.stageShare.\(stage).\(share >= usual ? "more" : "less")"
        default:
            key = "insight.\(type.rawValue)"
        }
        return text(key)
    }
}
