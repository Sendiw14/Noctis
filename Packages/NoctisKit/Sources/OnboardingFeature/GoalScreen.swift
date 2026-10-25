import DesignSystem
import NoctisCore
import SwiftUI

private struct GoalItem {
    let goal: PrimaryGoal
    let title: String
    /// The line on the tile, and (lowercased) what VoiceOver says after the title.
    let subtitle: String
    let fill: Color
    let glyph: String
    let isWide: Bool
}

private let goalItems: [GoalItem] = [
    GoalItem(goal: .betterSleep, title: "Better sleep", subtitle: "Calmer wind-down", fill: NoctisPaper.lavender, glyph: "moon.stars.fill", isWide: false),
    GoalItem(goal: .moreEnergy, title: "More energy", subtitle: "Sharper all day", fill: NoctisPaper.orange, glyph: "bolt.fill", isWide: false),
    GoalItem(goal: .betterRecovery, title: "Faster recovery", subtitle: "Bounce back", fill: NoctisPaper.sage, glyph: "heart.fill", isWide: false),
    GoalItem(goal: .betterConsistency, title: "Steady routine", subtitle: "Consistent days", fill: NoctisPaper.butter, glyph: "clock.arrow.2.circlepath", isWide: false),
    GoalItem(goal: .betterFocus, title: "Clearer focus", subtitle: "Stay sharp when it matters", fill: NoctisPaper.cocoa, glyph: "scope", isWide: true),
]

/// How a goal looks: on the goal step's tiles, and on the plan's chips (its colour, its glyph, its title).
enum GoalPresentation {
    static func title(_ goal: PrimaryGoal) -> String { item(goal).title }
    static func glyph(_ goal: PrimaryGoal) -> String { item(goal).glyph }
    static func fill(_ goal: PrimaryGoal) -> Color { item(goal).fill }

    private static func item(_ goal: PrimaryGoal) -> GoalItem {
        goalItems.first { $0.goal == goal } ?? goalItems[0]
    }
}

/// Step 1/6, in the band style (APP_RULES.md R6, R69): five colour tiles, up to two chosen. A third tap changes nothing and says so (a shake, a light
/// haptic, "Pick up to two."); a chosen tile is tapped again to let it go. `selectedGoals` is the shared source of truth (an empty array is
/// unambiguous), so revisiting via Back shows exactly what was chosen.
struct GoalScreen: View {
    @Binding var selectedGoals: [PrimaryGoal]
    let onNext: () -> Void
    let onBack: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var popped: PrimaryGoal?
    @State private var shakes: [PrimaryGoal: Int] = [:]
    @State private var showsLimit = false
    @State private var appeared = false

    var body: some View {
        OnboardingStepScaffold(
            section: .home, step: 0, title: ["What matters", "most to you?"], subtitle: showsLimit ? "Pick up to two." : "Choose up to two.", onBack: onBack
        ) {
            GoalTiles(
                items: goalItems, selected: selectedGoals, popped: popped, shakes: shakes, appeared: appeared || reduceMotion,
                singleColumn: dynamicTypeSize.isAccessibilitySize, dark: colorScheme == .dark, reduceMotion: reduceMotion, tap: tap
            )
        } actions: {
            VStack(spacing: 0) {
                OnboardingPrimaryButton("Continue", isEnabled: !selectedGoals.isEmpty, identifier: "goal.continue", action: onNext)
                OnboardingSecondaryButton("Skip for now", identifier: "goal.skip") {
                    selectedGoals = [.betterSleep]
                    onNext()
                }
                .padding(.top, 4)
            }
        }
        .onAppear {
            guard !appeared else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { appeared = true }
        }
    }

    /// Toggles `goal` by the one rule (`GoalSelection`): a chosen one is let go; one more is added while there is room; a third changes nothing and says so.
    private func tap(_ goal: PrimaryGoal) {
        switch GoalSelection.toggle(goal, in: selectedGoals) {
        case .removed(let goals):
            selectedGoals = goals
            NoctisHaptics.selectionTick()
        case .added(let goals):
            selectedGoals = goals
            NoctisHaptics.softImpact()
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { popped = goal }
            Task {
                try? await Task.sleep(for: .seconds(0.18))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { popped = nil }
            }
        case .limit:
            NoctisHaptics.snapLight()
            withAnimation(.linear(duration: 0.4)) { shakes[goal, default: 0] += 1 }
            withAnimation(.easeOut(duration: 0.15)) { showsLimit = true }
            AccessibilityNotification.Announcement("You can pick up to two.").post()
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.easeOut(duration: 0.15)) { showsLimit = false }
            }
        }
    }
}

/// What a tap on a goal does: the rule, apart from the view, so it is a unit test.
enum GoalSelection {
    static let limit = 2

    enum Outcome: Equatable {
        case removed([PrimaryGoal])
        case added([PrimaryGoal])
        /// Two are already chosen: nothing changes.
        case limit
    }

    static func toggle(_ goal: PrimaryGoal, in selected: [PrimaryGoal]) -> Outcome {
        if let index = selected.firstIndex(of: goal) {
            var goals = selected
            goals.remove(at: index)
            return .removed(goals)
        }
        guard selected.count < limit else { return .limit }
        return .added(selected + [goal])
    }
}

/// The tiles: two columns of squares and one wide tile, or (at accessibility sizes) one column of wide tiles.
private struct GoalTiles: View {
    let items: [GoalItem]
    let selected: [PrimaryGoal]
    let popped: PrimaryGoal?
    let shakes: [PrimaryGoal: Int]
    let appeared: Bool
    let singleColumn: Bool
    let dark: Bool
    let reduceMotion: Bool
    let tap: (PrimaryGoal) -> Void

    @Environment(\.onboardingScale) private var scale

    var body: some View {
        let squareHeight = 140 * min(max(scale, 0.72), 1)
        let wideHeight = 84 * min(max(scale, 0.72), 1)
        let compact = scale < 0.85
        VStack(spacing: 12) {
            if singleColumn {
                ForEach(Array(items.enumerated()), id: \.element.goal) { index, item in tile(item, index: index, wide: true, height: nil, compact: false) }
            } else {
                let squares = items.filter { !$0.isWide }
                ForEach(0..<(squares.count / 2), id: \.self) { row in
                    HStack(spacing: 12) {
                        tile(squares[row * 2], index: row * 2, wide: false, height: squareHeight, compact: compact)
                        tile(squares[row * 2 + 1], index: row * 2 + 1, wide: false, height: squareHeight, compact: compact)
                    }
                }
                ForEach(Array(items.enumerated()).filter { $0.element.isWide }, id: \.element.goal) { index, item in
                    tile(item, index: index, wide: true, height: wideHeight, compact: compact)
                }
            }
        }
    }

    private func tile(_ item: GoalItem, index: Int, wide: Bool, height: CGFloat?, compact: Bool) -> some View {
        let isOn = selected.contains(item.goal)
        return GoalTileView(item: item, isOn: isOn, wide: wide, height: height, dark: dark, count: selected.count, compact: compact)
            .scaleEffect(popped == item.goal ? 1.03 : (appeared ? 1 : 0.9))
            .opacity(appeared ? 1 : 0)
            .modifier(GoalShake(travel: 8, shakes: CGFloat(shakes[item.goal] ?? 0)))
            .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.78).delay(Double(index) * 0.05), value: appeared)
            .onTapGesture { tap(item.goal) }
    }
}

private struct GoalTileView: View {
    let item: GoalItem
    let isOn: Bool
    let wide: Bool
    let height: CGFloat?
    let dark: Bool
    let count: Int
    /// A short screen (an SE): the icon and the padding give a little back so the words are whole.
    let compact: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var onCocoa: Bool { item.fill == NoctisPaper.cocoa }
    private var ink: Color { onCocoa ? NoctisPaper.ivory : NoctisPaper.ink }
    private var outline: Color { dark ? NoctisPaper.ivory : NoctisPaper.ink }

    var body: some View {
        Group {
            if wide {
                HStack(spacing: 14) {
                    icon
                    VStack(alignment: .leading, spacing: 2) { words }
                    Spacer(minLength: 36)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, compact ? 12 : 16)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    icon
                    Spacer(minLength: 6)
                    VStack(alignment: .leading, spacing: 2) { words }
                }
                .padding(compact ? 12 : 16)
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(item.fill))
        .overlay(alignment: .topTrailing) { indicator.padding(wide ? 20 : (compact ? 12 : 16)) }
        .overlay { if isOn { RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(outline, lineWidth: 4) } }
        .shadow(color: isOn ? NoctisPaper.ink.opacity(dark ? 0.5 : 0.22) : .clear, radius: 12, x: 0, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: isOn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title), \(item.subtitle.prefix(1).lowercased() + item.subtitle.dropFirst())")
        .accessibilityHint("\(count) of 2 selected")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("goal.\(item.goal.rawValue)")
    }

    private var icon: some View {
        ZStack {
            Circle().fill(onCocoa ? NoctisPaper.ivory.opacity(0.16) : NoctisPaper.ivory)
            Image(systemName: item.glyph)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(onCocoa ? NoctisPaper.ivory : NoctisPaper.ink)
        }
        .frame(width: compact ? 36 : 44, height: compact ? 36 : 44)
    }

    @ViewBuilder
    private var words: some View {
        Text(item.title)
            .noctisFont(19, .heavy, relativeTo: .headline, maxScale: 1.25)
            .foregroundStyle(ink)
            // One line that shrinks a little at the default size ("Faster recovery" is 150 pt in a 138 pt column); wraps only at the larger sizes.
            .lineLimit(dynamicTypeSize > .large ? 2 : 1)
            .minimumScaleFactor(dynamicTypeSize > .large ? 0.75 : 0.8)
            .fixedSize(horizontal: false, vertical: true)
        Text(item.subtitle)
            .noctisFont(13, relativeTo: .footnote, maxScale: 1.25)
            .foregroundStyle(ink.opacity(0.8))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var indicator: some View {
        ZStack {
            if isOn {
                Circle().fill(NoctisPaper.ivory)
                Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(NoctisPaper.ink)
            } else {
                Circle().strokeBorder(NoctisPaper.ivory, lineWidth: 2.5)
            }
        }
        .frame(width: 28, height: 28)
    }
}

/// A short sideways shake, one per increase of `shakes`.
private struct GoalShake: GeometryEffect {
    var travel: CGFloat
    var shakes: CGFloat

    nonisolated var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    nonisolated func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(shakes * .pi * 4), y: 0))
    }
}
