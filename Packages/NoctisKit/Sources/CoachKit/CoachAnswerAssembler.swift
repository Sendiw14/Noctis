import Foundation
import NoctisCore

/// Why an answer is less than certain, in the app's own words. Written by the
/// app, so a draft that claims too much is corrected and one that hedges is
/// never contradicted.
public enum CoachCautions {
    /// The caution that goes with `context`'s ceiling; nil when the data supports high confidence.
    public static func text(for context: CoachContext, copy: (String) -> String = { CoachCopy.string($0) }) -> String? {
        guard context.confidenceCeiling != .high else { return nil }
        switch context.dataState {
        case .stale: return copy("coach.caution.stale")
        case .noSleepLastNight: return copy("coach.caution.gap")
        case .noData: return copy("coach.caution.noData")
        case .learning: return copy("coach.caution.limited")
        case .ready:
            let heart = context.availableFactors.contains("hrv") || context.availableFactors.contains("restingHeartRate")
            if !heart { return copy("coach.caution.noHeart") }
            return copy(context.nightsOfHistory < CoachContextBuilder.moderateNights ? "coach.caution.limited" : "coach.caution.building")
        }
    }
}

/// Turns a draft that passed validation into what a person sees: every token
/// replaced by its fact's display, the confidence held to what the data
/// supports, and the lines only the app writes (the confidence line, the
/// pattern note, the footer).
public enum CoachAnswerAssembler {
    /// nil when a token can't be resolved: the validator should have caught it, and a draft that gets here anyway is not shown.
    public static func assemble(
        _ draft: CoachAnswerDraft, context: CoachContext, source: CoachSourceKind, locale: Locale = .current,
        copy: (String) -> String = { CoachCopy.string($0) }
    ) -> CoachAnswer? {
        let facts = Dictionary(context.facts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func resolve(_ text: String) -> String? { CoachTokens.resolve(text, facts: facts) }
        func resolveOptional(_ text: String?) -> String?? {
            guard let text else { return .some(nil) }
            return resolve(text).map { .some($0) }
        }

        guard let summary = resolve(draft.summary), let changed = resolve(draft.whatChanged), let notice = resolve(draft.whatToNotice),
              let tonight = resolveOptional(draft.tonightSuggestion), let pattern = resolveOptional(draft.pattern),
              let draftCaution = resolveOptional(draft.caution) else { return nil }

        var contributors: [CoachContributor] = []
        for item in draft.contributors {
            guard let label = resolve(item.label), let fact = facts[item.factID] else { return nil }
            contributors.append(CoachContributor(label: label, value: fact.display, spoken: fact.spoken, factID: fact.id))
        }
        // The number the summary is about: only when its sentence names it.
        var keyNumber: CoachContributor?
        if let keyID = keyFactID(for: context.intent), CoachTokens.ids(in: draft.summary).contains(keyID), let fact = facts[keyID] {
            keyNumber = CoachContributor(label: fact.label, value: fact.display, spoken: fact.spoken, factID: fact.id)
        }

        // Never more confident than the data allows.
        let confidence = min(draft.confidence ?? .low, context.confidenceCeiling)
        var caution = draftCaution
        if confidence != .high && caution == nil { caution = CoachCautions.text(for: context, copy: copy) }

        return CoachAnswer(
            sourceKind: source,
            intent: context.intent,
            summary: summary,
            contributors: contributors,
            keyNumber: keyNumber,
            whatChanged: changed,
            whatToNotice: notice,
            tonightSuggestion: tonight,
            pattern: pattern,
            patternNote: pattern == nil ? nil : copy("coach.pattern.note"),
            confidence: confidence,
            confidenceLine: confidenceLine(confidence, nights: context.nightsOfHistory, locale: locale, copy: copy),
            caution: caution,
            destinations: draft.destinations.compactMap { AppRoute.coachDestination(named: $0) },
            footer: copy("coach.footer")
        )
    }

    /// The fact an intent's answer is about, when it is about one number.
    static func keyFactID(for intent: CoachIntent) -> String? {
        switch intent {
        case .recoveryChange, .todayFocus: "recovery.score"
        case .sleepChange: "sleep.duration"
        case .weekChange: "week.avgSleep"
        case .bedtimeAdvice: "bedtime.suggested"
        case .consistencyHelp: "consistency.bedtimeVarMin"
        case .patterns, .medicalOutOfScope, .crisis, .unknown: nil
        }
    }

    /// "Moderate confidence · based on 9 nights".
    public static func confidenceLine(
        _ confidence: CoachConfidence, nights: Int, locale: Locale, copy: (String) -> String = { CoachCopy.string($0) }
    ) -> String {
        let level = copy("coach.confidence.\(confidence.rawValue)")
        guard nights > 0 else { return level }
        let template = copy(nights == 1 ? "coach.confidence.line.one" : "coach.confidence.line.other")
        return template
            .replacingOccurrences(of: "{level}", with: level)
            .replacingOccurrences(of: "{nights}", with: nights.formatted(.number.locale(locale)))
    }
}
