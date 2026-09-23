import Foundation

public nonisolated struct UserProfileSnapshot: Sendable, Equatable {
    public var name: String
    public var primaryGoal: PrimaryGoal
    /// An optional second goal (GoalScreen allows picking up to two) —
    /// every other screen that reads `primaryGoal` for its own tint is
    /// unaffected by this being set.
    public var secondaryGoal: PrimaryGoal?
    /// GoalScreen's own selection state, 0-2 goals in selection order
    /// (oldest first) — the source of truth while onboarding, since unlike
    /// `primaryGoal` an empty array is unambiguous ("nothing chosen yet").
    /// `primaryGoal`/`secondaryGoal` are derived from this once onboarding
    /// actually completes.
    public var selectedGoals: [PrimaryGoal]
    public var typicalWakeMinutes: Int
    /// RhythmScreen's own sleep-need value, in minutes — the draft source
    /// of truth while onboarding (mirrors `selectedGoals`'s reasoning).
    /// `sleepGoalHours` is derived from this once onboarding completes;
    /// it stays a separate field because `AppModel`/Settings read it after
    /// completion as a plain `Double` of hours.
    public var needMinutes: Int
    public var sleepGoalHours: Double
    public var onboardingComplete: Bool
    public var healthAuthorizationRequested: Bool

    public init(
        name: String = "",
        primaryGoal: PrimaryGoal = .betterSleep,
        secondaryGoal: PrimaryGoal? = nil,
        selectedGoals: [PrimaryGoal] = [],
        typicalWakeMinutes: Int = 7 * 60,
        needMinutes: Int = 8 * 60,
        sleepGoalHours: Double = 8.0,
        onboardingComplete: Bool = false,
        healthAuthorizationRequested: Bool = false
    ) {
        self.name = name
        self.primaryGoal = primaryGoal
        self.secondaryGoal = secondaryGoal
        self.selectedGoals = selectedGoals
        self.typicalWakeMinutes = typicalWakeMinutes
        self.needMinutes = needMinutes
        self.sleepGoalHours = sleepGoalHours
        self.onboardingComplete = onboardingComplete
        self.healthAuthorizationRequested = healthAuthorizationRequested
    }

    public var typicalWakeTimeDescription: String {
        let hour24 = typicalWakeMinutes / 60
        let minute = typicalWakeMinutes % 60
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        let period = hour24 < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", hour12, minute, period)
    }
}
