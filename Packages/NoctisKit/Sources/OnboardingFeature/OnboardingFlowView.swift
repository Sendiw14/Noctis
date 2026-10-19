import DesignSystem
import NoctisCore
import SwiftUI

enum OnboardingStep: String, CaseIterable {
    case welcome
    /// Only after signing in with Apple (R69).
    case name
    case goal
    case rhythm
    case sample
    case health
    case notifications
    case plan
    case paywall

    /// R7's progress bar covers goal...plan as steps 1...6 (0-indexed here
    /// for `NoctisSegmentedProgress`). Welcome and Paywall have no bar.
    var progressIndex: Int? {
        switch self {
        case .welcome, .name: nil
        case .goal: 0
        case .rhythm: 1
        case .sample: 2
        case .health: 3
        case .notifications: 4
        case .plan: 5
        case .paywall: nil
        }
    }
}

public struct OnboardingFlowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: OnboardingStep
    @State private var draft: UserProfileSnapshot
    /// True once Plan's build phase has already played once this launch —
    /// resuming mid-flow (or coming Back from Paywall) should land on
    /// Plan's results, not replay the loading moment.
    @State private var planAlreadyBuilt: Bool

    private let onFinished: () -> Void
    private let onWelcome: (Bool) -> Void

    /// `onWelcome` says whether Welcome is the step on show (it alone follows the system's appearance).
    public init(onWelcome: @escaping (Bool) -> Void = { _ in }, onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
        self.onWelcome = onWelcome
        let loaded = OnboardingDraftStore.load()
        self._step = State(initialValue: loaded.step)
        self._draft = State(initialValue: loaded.draft)
        self._planAlreadyBuilt = State(initialValue: loaded.step == .paywall)
    }

    public var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeScreen(
                    onContinue: { advance(to: .goal) },
                    onSignedIn: { prefill in
                        if let prefill { draft.name = prefill }
                        advance(to: .name)
                    },
                    existingName: draft.name
                )
                .id(step)
                .transition(.opacity)
            case .name:
                NameScreen(name: $draft.name, onNext: { advance(to: .goal) })
                    .id(step)
                    .transition(.opacity)
            case .goal:
                GoalScreen(
                    selectedGoals: $draft.selectedGoals,
                    onNext: { advance(to: .rhythm) },
                    onBack: { advance(to: .welcome) }
                )
                .id(step)
                .transition(.opacity)
            case .rhythm:
                RhythmScreen(
                    wakeMinutes: $draft.typicalWakeMinutes,
                    needMinutes: $draft.needMinutes,
                    onNext: { advance(to: .sample) },
                    onBack: { advance(to: .goal) }
                )
                .id(step)
                .transition(.opacity)
            case .sample:
                SampleNightScreen(
                    onNext: { advance(to: .health) },
                    onBack: { advance(to: .rhythm) }
                )
                .id(step)
                .transition(.opacity)
            case .health:
                HealthScreen(
                    onNext: { advance(to: .notifications) },
                    onBack: { advance(to: .sample) }
                )
                .id(step)
                .transition(.opacity)
            case .notifications:
                NotificationsScreen(
                    wakeMinutes: draft.typicalWakeMinutes,
                    needMinutes: draft.needMinutes,
                    onNext: { advance(to: .plan) },
                    onBack: { advance(to: .health) }
                )
                .id(step)
                .transition(.opacity)
            case .plan:
                PlanScreen(
                    goals: draft.selectedGoals.isEmpty ? [.betterSleep] : draft.selectedGoals,
                    wakeMinutes: draft.typicalWakeMinutes,
                    needMinutes: draft.needMinutes,
                    startBuilt: planAlreadyBuilt,
                    onNext: {
                        planAlreadyBuilt = true
                        advance(to: .paywall)
                    },
                    onBack: { advance(to: .notifications) }
                )
                .id(step)
                .transition(.opacity)
            case .paywall:
                PaywallScreen(
                    wakeMinutes: draft.typicalWakeMinutes,
                    needMinutes: draft.needMinutes,
                    onFinished: { complete() }
                )
                .id(step)
                .transition(.opacity)
            }
        }
        .animation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion), value: step)
        .onAppear { onWelcome(step == .welcome) }
        .onChange(of: step) { _, new in onWelcome(new == .welcome) }
        .onChange(of: draft) { _, newValue in
            OnboardingDraftStore.save(step: step, draft: newValue)
        }
    }

    private func advance(to next: OnboardingStep) {
        NoctisHaptics.selection()
        step = next
        OnboardingDraftStore.save(step: next, draft: draft)
    }

    private func complete() {
        var finished = draft
        finished.primaryGoal = draft.selectedGoals.first ?? .betterSleep
        finished.secondaryGoal = draft.selectedGoals.count > 1 ? draft.selectedGoals[1] : nil
        finished.sleepGoalHours = Double(draft.needMinutes) / 60
        finished.onboardingComplete = true
        Task {
            await model.completeOnboarding(finished)
            OnboardingDraftStore.clear()
            NoctisAnalytics.log(.onboardingCompleted)
            onFinished()
        }
    }
}
