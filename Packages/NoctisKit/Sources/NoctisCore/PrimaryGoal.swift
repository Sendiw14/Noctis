import Foundation

public enum PrimaryGoal: String, Sendable, CaseIterable, Codable {
    case betterSleep
    case moreEnergy
    case betterRecovery
    case betterConsistency
    case betterFocus

    /// R15: sentence case, matching GoalScreen's own row titles exactly —
    /// the single shared source both Plan's goal chips and Settings read
    /// from, so the two can never drift apart again.
    public var displayName: String {
        switch self {
        case .betterSleep: "Better sleep"
        case .moreEnergy: "More energy"
        case .betterRecovery: "Faster recovery"
        case .betterConsistency: "Steady routine"
        case .betterFocus: "Clearer focus"
        }
    }

    public var systemImage: String {
        switch self {
        case .betterSleep: "moon.stars.fill"
        case .moreEnergy: "bolt.fill"
        case .betterRecovery: "heart.fill"
        case .betterConsistency: "repeat.circle.fill"
        case .betterFocus: "target"
        }
    }
}
