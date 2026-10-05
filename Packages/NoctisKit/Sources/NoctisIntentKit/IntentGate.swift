import Foundation
import NoctisWidgetKit
import SoundCatalog

// What Siri, Shortcuts and Control Center do with the person's plan (APP_RULES.md R62). Pure: a plan, a request and what the app last did in, a decision and the words out, so every
// branch and every spoken sentence is a unit test (and goes through the banned-language lint). The plan is the one word in the App Group's snapshot (an intent never calls
// StoreKit), a missing snapshot is free, and what a plan includes is the one feature table's and `SoundAccess`'s (R59).

/// What happened when an intent asked Coach a question.
public enum AskCoachOutcome: Sendable, Equatable {
    /// Coach was opened on the question.
    case asked
    /// Today's free questions are used up: Coach was opened on its card, and the question was not asked and not kept.
    case limitReached
}

/// What a request for a sleep sound turns into.
public enum SleepSoundChoice: Sendable, Equatable {
    /// This sound plays.
    case play(SoundKind)
    /// The sound asked for is Premium and the plan is free: nothing plays, and the intent says so.
    case premiumNeeded(SoundKind)
}

public enum IntentGate {
    /// Whether the plan includes starting a wind-down by voice (the wind-down itself is Premium).
    public static func includesStartWindDown(in tier: Tier) -> Bool {
        FeatureTable.isIncluded(.siriStartWindDown, in: tier)
    }

    /// The sound a request turns into. A sound named is played if the plan includes it and is a Premium one otherwise (nothing plays). With none named (the control, or "play
    /// sleep sounds") the last sound played, Rain before any, plays if the plan still includes it, and Brown noise if it does not.
    public static func soundChoice(requested: SoundKind?, last: SoundKind?, tier: Tier) -> SleepSoundChoice {
        if let requested {
            return SoundAccess.isIncluded(requested, in: tier) ? .play(requested) : .premiumNeeded(requested)
        }
        let candidate = last ?? .rain
        return .play(SoundAccess.isIncluded(candidate, in: tier) ? candidate : SoundAccess.fallback)
    }

    // MARK: What is said

    /// "Wind is part of NOCTIS Premium. Rain, Brown noise and Ocean are free." The free ones are made from the one list.
    public static func premiumSoundDialog(_ kind: SoundKind) -> String {
        let free = SoundAccess.spokenFreeOrder.map(\.title)
        let list = free.dropLast().joined(separator: ", ") + " and " + (free.last ?? "")
        return "\(kind.title) is part of NOCTIS Premium. \(list) are free."
    }

    /// Starting a wind-down is Premium; the app was opened on what Premium includes and nothing was started.
    public static let startWindDownLocked = "Wind-down sessions are part of NOCTIS Premium. I've opened NOCTIS."

    /// Today's free questions are used up (Coach's own words), and Coach was opened on its card.
    public static let coachLimitReached = "You've used today's free questions. They reset at midnight. I've opened Coach."
}
