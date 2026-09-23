import DesignSystem
import NoctisCore
import SwiftUI

private struct GoalItem {
    let goal: PrimaryGoal
    let title: String
    let subtitle: String
    let fill: Color
    let glyph: String
}

private let goalItems: [GoalItem] = [
    GoalItem(goal: .betterSleep, title: "Better sleep", subtitle: "Fall asleep easier, wake less", fill: NoctisPaper.lavender, glyph: "moon.stars.fill"),
    GoalItem(goal: .moreEnergy, title: "More energy", subtitle: "Feel sharper through the day", fill: NoctisPaper.orange, glyph: "bolt.fill"),
    GoalItem(goal: .betterRecovery, title: "Faster recovery", subtitle: "Bounce back after hard days", fill: NoctisPaper.sage, glyph: "heart.fill"),
    GoalItem(goal: .betterConsistency, title: "Steady routine", subtitle: "Keep a consistent schedule", fill: NoctisPaper.butter, glyph: "clock.arrow.2.circlepath"),
    GoalItem(goal: .betterFocus, title: "Clearer focus", subtitle: "Stay sharp when it matters", fill: NoctisPaper.cocoa, glyph: "scope"),
]

/// Step 1/6 — a plain vertical list of goal rows (R8: system layout, no
/// `.position()`). Up to two selections; a third tap replaces the oldest.
/// `selectedGoals` is the shared source of truth (an empty array is
/// unambiguous, unlike a non-optional `PrimaryGoal` with a default), so
/// revisiting via Back always shows exactly what was chosen.
struct GoalScreen: View {
    @Binding var selectedGoals: [PrimaryGoal]
    let onNext: () -> Void
    let onBack: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingScaffold(
            step: 0,
            title: "What matters",
            emphasis: "most to you?",
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                Text("Choose up to two.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(NoctisPaper.ink3)
                    .noctisTextBlock()

                VStack(spacing: NoctisSpacing.sm) {
                    ForEach(Array(goalItems.enumerated()), id: \.element.goal) { index, item in
                        goalRow(item)
                            .noctisScrollRow()
                            .noctisRise(index: index)
                    }
                }
            }
        } bottomStack: {
            VStack(spacing: NoctisSpacing.sm) {
                NoctisCTA("Continue", action: onNext)
                    .disabled(selectedGoals.isEmpty)
                NoctisTextButton("Skip for now") {
                    selectedGoals = [.betterSleep]
                    onNext()
                }
            }
        }
    }

    private func goalRow(_ item: GoalItem) -> some View {
        let isSelected = selectedGoals.contains(item.goal)

        return Button {
            select(item.goal)
        } label: {
            NoctisPaperCard(
                padding: NoctisSpacing.lg,
                borderColor: isSelected ? NoctisPaper.cocoa : NoctisPaper.hairline,
                borderWidth: isSelected ? 2 : 1
            ) {
                HStack(spacing: NoctisSpacing.md) {
                    ZStack {
                        Circle().fill(item.fill).frame(width: 48, height: 48)
                        Image(systemName: item.glyph)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(NoctisPaper.bg)
                            .symbolEffect(.bounce, value: isSelected)
                    }
                    .scaleEffect(isSelected ? 1.08 : 1.0)
                    .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion), value: isSelected)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(NoctisPaper.ink)
                        Text(item.subtitle)
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(NoctisPaper.ink2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }

                    Spacer(minLength: NoctisSpacing.xs)

                    selectionCircle(isSelected: isSelected)
                }
                .noctisTextBlock()
            }
            .frame(minHeight: 72)
        }
        .buttonStyle(GoalRowButtonStyle(reduceMotion: reduceMotion))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title). \(item.subtitle)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("\(selectedGoals.count) of 2 selected")
    }

    private func selectionCircle(isSelected: Bool) -> some View {
        ZStack {
            Circle().fill(isSelected ? NoctisPaper.cocoa : Color.clear)
            Circle().stroke(NoctisPaper.hairline, lineWidth: isSelected ? 0 : 1.5)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(NoctisPaper.bg)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 26, height: 26)
        .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion), value: isSelected)
    }

    /// Toggles `goal`: deselects if already chosen; otherwise adds it,
    /// bumping the oldest selection out once two are already chosen.
    private func select(_ goal: PrimaryGoal) {
        if let index = selectedGoals.firstIndex(of: goal) {
            selectedGoals.remove(at: index)
            NoctisHaptics.selectionTick()
            return
        }
        if selectedGoals.count >= 2 {
            selectedGoals.removeFirst()
            NoctisHaptics.softImpact()
        } else {
            NoctisHaptics.selectionTick()
        }
        selectedGoals.append(goal)
    }
}

private struct GoalRowButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(NoctisMotion.adaptive(NoctisMotion.snap, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
