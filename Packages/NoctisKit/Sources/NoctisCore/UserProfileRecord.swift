import Foundation
import SwiftData

@Model
public final class UserProfileRecord {
    public var name: String = ""
    public var primaryGoalRaw: String = PrimaryGoal.betterSleep.rawValue
    public var secondaryGoalRaw: String?
    public var typicalWakeMinutes: Int = 7 * 60
    public var sleepGoalHours: Double = 8.0
    public var onboardingComplete: Bool = false
    public var healthAuthorizationRequested: Bool = false
    public var createdAt: Date = Date.now

    public init() {}

    public func apply(_ snapshot: UserProfileSnapshot) {
        name = snapshot.name
        primaryGoalRaw = snapshot.primaryGoal.rawValue
        secondaryGoalRaw = snapshot.secondaryGoal?.rawValue
        typicalWakeMinutes = snapshot.typicalWakeMinutes
        sleepGoalHours = snapshot.sleepGoalHours
        onboardingComplete = snapshot.onboardingComplete
        healthAuthorizationRequested = snapshot.healthAuthorizationRequested
    }

    /// The record keeps the sleep need as hours and the goals as a primary and a secondary; the snapshot's
    /// `needMinutes` and `selectedGoals` are derived from them here, so what Tonight and the reminders read
    /// after a relaunch is what was chosen (they used to come back as 8 hours and no goals).
    public var snapshot: UserProfileSnapshot {
        let primary = PrimaryGoal(rawValue: primaryGoalRaw) ?? .betterSleep
        let secondary = secondaryGoalRaw.flatMap(PrimaryGoal.init(rawValue:))
        return UserProfileSnapshot(
            name: name,
            primaryGoal: primary,
            secondaryGoal: secondary,
            selectedGoals: [primary] + (secondary.map { [$0] } ?? []),
            typicalWakeMinutes: typicalWakeMinutes,
            needMinutes: Int((sleepGoalHours * 60).rounded()),
            sleepGoalHours: sleepGoalHours,
            onboardingComplete: onboardingComplete,
            healthAuthorizationRequested: healthAuthorizationRequested
        )
    }
}
