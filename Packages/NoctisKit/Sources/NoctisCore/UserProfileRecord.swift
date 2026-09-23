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

    public var snapshot: UserProfileSnapshot {
        UserProfileSnapshot(
            name: name,
            primaryGoal: PrimaryGoal(rawValue: primaryGoalRaw) ?? .betterSleep,
            secondaryGoal: secondaryGoalRaw.flatMap(PrimaryGoal.init(rawValue:)),
            typicalWakeMinutes: typicalWakeMinutes,
            sleepGoalHours: sleepGoalHours,
            onboardingComplete: onboardingComplete,
            healthAuthorizationRequested: healthAuthorizationRequested
        )
    }
}
