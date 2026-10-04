import Foundation
import NoctisCore

/// Persists in-progress onboarding (current step + answers so far) to
/// `UserDefaults`, separate from the `SwiftData` `UserProfileRecord` that
/// only gets written once onboarding actually completes. Lets a relaunch
/// mid-flow resume exactly where the user left off instead of restarting
/// at Welcome.
enum OnboardingDraftStore {
    private static let stepKey = "noctis.onboarding.step"
    private static let selectedGoalsKey = "noctis.onboarding.selectedGoals"
    private static let wakeKey = "noctis.onboarding.wakeMinutes"
    private static let needKey = "noctis.onboarding.needMinutes"
    private static let sleepHoursKey = "noctis.onboarding.sleepGoalHours"

    static func load() -> (step: OnboardingStep, draft: UserProfileSnapshot) {
        let defaults = NoctisUserDefaults.standard
        var draft = UserProfileSnapshot()
        if let goalsRaw = defaults.string(forKey: selectedGoalsKey) {
            draft.selectedGoals = goalsRaw.split(separator: ",").compactMap { PrimaryGoal(rawValue: String($0)) }
        }
        if defaults.object(forKey: wakeKey) != nil {
            draft.typicalWakeMinutes = defaults.integer(forKey: wakeKey)
        }
        if defaults.object(forKey: needKey) != nil {
            draft.needMinutes = defaults.integer(forKey: needKey)
        }
        if defaults.object(forKey: sleepHoursKey) != nil {
            draft.sleepGoalHours = defaults.double(forKey: sleepHoursKey)
        }
        let step: OnboardingStep
        if let stepRaw = defaults.string(forKey: stepKey), let saved = OnboardingStep(rawValue: stepRaw) {
            step = saved
        } else {
            step = .welcome
        }
        return (step, draft)
    }

    static func save(step: OnboardingStep, draft: UserProfileSnapshot) {
        let defaults = NoctisUserDefaults.standard
        defaults.set(step.rawValue, forKey: stepKey)
        defaults.set(draft.selectedGoals.map(\.rawValue).joined(separator: ","), forKey: selectedGoalsKey)
        defaults.set(draft.typicalWakeMinutes, forKey: wakeKey)
        defaults.set(draft.needMinutes, forKey: needKey)
        defaults.set(draft.sleepGoalHours, forKey: sleepHoursKey)
    }

    /// Called once onboarding actually completes — the draft is no longer
    /// meaningful once the real `UserProfileRecord` exists.
    static func clear() {
        let defaults = NoctisUserDefaults.standard
        [stepKey, selectedGoalsKey, wakeKey, needKey, sleepHoursKey].forEach { defaults.removeObject(forKey: $0) }
    }
}
