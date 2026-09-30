import Foundation
import InsightsKit

/// What the on-device model is told. The instructions carry the rules and the
/// allowed facts; the prompt carries the question. The model sees display
/// values so it can tell which way a number points, and is told never to write
/// one: it points at a fact by its token and the app writes the number in.
public enum CoachPrompt {
    /// The routes a draft may point to.
    public static let destinationNames = ["recovery", "sleep", "sleep:week", "insights"]

    public static func instructions(context: CoachContext) -> String {
        let example = context.facts.first?.id ?? "fact.id"
        var lines = [
            "You are Coach, a calm assistant inside a sleep and recovery app.",
            "Explain patterns in the person's own data. Never diagnose, never say what caused something, and never give medical advice.",
            "Use hedged wording such as \"your data suggests\", \"has coincided with\" or \"compared with your recent baseline\".",
            "Never write digits, percent signs or number words. To mention a number, write its token exactly as listed, like {{\(example)}}. Use only tokens from the allowed list.",
            "Never use these words or word parts: \(BannedLanguage.coach.joined(separator: ", ")).",
            "Write one short paragraph per field. Keep the summary under \(CoachSafetyValidator.summaryLimit) characters and every other field under \(CoachSafetyValidator.fieldLimit).",
            "List at most \(CoachSafetyValidator.maxContributors) contributors, each a short label and the id of an allowed fact.",
            "Set confidence to high, moderate or low. It can't be higher than \(context.confidenceCeiling.rawValue). Add a caution whenever confidence isn't high.",
            "A pattern must use hedged wording. Leave the pattern out unless the data shows one.",
            "Destinations may only be: \(destinationNames.joined(separator: ", ")).",
        ]
        if context.facts.isEmpty {
            lines.append("There are no allowed facts: say plainly that you need more nights, and use no tokens.")
        } else {
            lines.append("Allowed facts (token: label = value):")
            for fact in context.facts { lines.append("- {{\(fact.id)}}: \(fact.label) = \(fact.display)") }
        }
        return lines.joined(separator: "\n")
    }

    public static func prompt(question: String, intent: CoachIntent, context: CoachContext) -> String {
        var lines: [String] = []
        if !context.recentTurns.isEmpty {
            lines.append("Earlier in this conversation:")
            for turn in context.recentTurns.suffix(CoachContext.maxTurns) {
                lines.append("Question: \(turn.question)")
                lines.append("Answer: \(turn.answerSummary)")
            }
            lines.append("")
        }
        lines.append("Question: \(question)")
        lines.append("Topic: \(intent.rawValue)" + (context.direction.map { ". The question asks about it being \($0.rawValue)." } ?? "."))
        lines.append("Data: \(context.dataState.rawValue), \(context.nightsOfHistory) nights recorded, sleep need \(context.sleepNeedMinutes / 60) hours.")
        if !context.missingFactors.isEmpty {
            lines.append("Not available: " + context.missingFactors.map { "\($0.factor) (\($0.reason.rawValue))" }.joined(separator: ", "))
        }
        if !context.insights.isEmpty {
            lines.append("Patterns found in the data:")
            for brief in context.insights {
                lines.append("- \(brief.type.rawValue), confidence \(brief.confidence.rawValue), facts \(brief.factIDs.joined(separator: ", "))")
            }
        }
        return lines.joined(separator: "\n")
    }

    public static let classifierInstructions = """
        You sort questions for a sleep and recovery app into one topic. Choose the topic that fits best, and unknown when none does. \
        Choose medicalOutOfScope for any question about diagnosis, conditions, symptoms, medicine or treatment, and crisis for any \
        mention of harming oneself. Never answer the question.
        """
}
