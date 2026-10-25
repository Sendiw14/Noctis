import Testing

@testable import NoctisCore
@testable import OnboardingFeature

// Onboarding step 1: up to two goals; a third tap changes nothing; a chosen one is let go by tapping it again; Continue needs one.
struct GoalSelectionTests {
    @Test func aFirstAndASecondGoalAreAdded() {
        #expect(GoalSelection.toggle(.betterSleep, in: []) == .added([.betterSleep]))
        #expect(GoalSelection.toggle(.moreEnergy, in: [.betterSleep]) == .added([.betterSleep, .moreEnergy]))
    }

    @Test func aThirdTapDeselectsNothingAndChangesNothing() {
        let two: [PrimaryGoal] = [.betterSleep, .moreEnergy]
        #expect(GoalSelection.toggle(.betterRecovery, in: two) == .limit)
        #expect(GoalSelection.toggle(.betterFocus, in: two) == .limit)
    }

    @Test func aChosenGoalIsLetGoByTappingItAndRoomOpensAgain() {
        let two: [PrimaryGoal] = [.betterSleep, .moreEnergy]
        #expect(GoalSelection.toggle(.betterSleep, in: two) == .removed([.moreEnergy]))
        #expect(GoalSelection.toggle(.betterRecovery, in: [.moreEnergy]) == .added([.moreEnergy, .betterRecovery]))
    }

    @Test func everyGoalCanBeChosenAlone() {
        for goal in PrimaryGoal.allCases { #expect(GoalSelection.toggle(goal, in: []) == .added([goal])) }
    }
}
