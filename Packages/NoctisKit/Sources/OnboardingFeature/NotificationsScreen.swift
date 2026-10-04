import DesignSystem
import NoctisCore
import SwiftUI
import UserNotifications

private enum NotificationKind: Int, CaseIterable, Identifiable {
    case morningSummary
    case windDown
    case weeklyReview

    var id: Int { rawValue }

    /// Doubles as the scheduled notification's body — one source of truth
    /// so the example card can never drift from what actually gets sent.
    /// Generic only (R13): no streak counts, no scores, no biometric values.
    var previewBody: String {
        switch self {
        case .morningSummary: "Your morning summary is ready."
        case .windDown: "Your wind-down starts in 20 minutes."
        case .weeklyReview: "Your weekly review is ready."
        }
    }

    var toggleTitle: String {
        switch self {
        case .morningSummary: "Morning summary"
        case .windDown: "Wind-down reminder"
        case .weeklyReview: "Weekly review"
        }
    }

    var toggleSubtitle: String? {
        self == .windDown ? "20 minutes before your bedtime" : nil
    }

    var identifier: String {
        switch self {
        case .morningSummary: NoctisNotification.morningSummary
        case .windDown: NoctisNotification.windDown
        case .weeklyReview: NoctisNotification.weeklyReview
        }
    }
}

private enum PermissionOutcome: Equatable {
    case idle
    case requesting
    case granted
    case denied
}

/// Step 5/6 — three static example notifications, a toggle for each, and a
/// real `UNUserNotificationCenter` permission request that schedules only
/// what's still enabled. iOS never lets an app re-show its own system
/// prompt after the first answer, so `.denied` here reads "the user just
/// said no" (or authorization otherwise failed) and is handled with a
/// plain reassurance, never a nag or a retry button (R13).
struct NotificationsScreen: View {
    let wakeMinutes: Int
    let needMinutes: Int
    let onNext: () -> Void
    let onBack: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Where the choices are kept, and what keeps the reminders matching them (R38). Nil in a preview.
    @Environment(\.appPreferences) private var preferences
    @Environment(\.notificationCoordinator) private var coordinator

    @State private var enabledStates: [Bool] = NotificationKind.allCases.map { _ in true }
    @State private var cardsAppeared = false
    @State private var cardsSettling = false
    @State private var checkmarkDrawn = false
    @State private var dismissing = false
    @State private var outcome: PermissionOutcome = .idle
    @State private var heroHeight: CGFloat = 700

    private var compact: Bool { heroHeight < 700 }

    var body: some View {
        OnboardingScaffold(
            step: 4,
            title: "Stay",
            emphasis: "gently informed.",
            caption: outcome == .denied ? "You can turn this on in Settings anytime." : nil,
            onBack: onBack
        ) {
            VStack(spacing: NoctisSpacing.sm) {
                previewStack(compact: compact)
                toggleCard(compact: compact)
            }
            .opacity(dismissing ? 0 : 1)
            .offset(y: dismissing ? -40 : 0)
            .padding(.bottom, NoctisSpacing.xs)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { heroHeight = geometry.size.height }
                        .onChange(of: geometry.size.height) { _, newHeight in heroHeight = newHeight }
                }
            )
        } bottomStack: {
            bottomStack
        }
        .onAppear { runEntranceIfNeeded() }
    }

    // MARK: - Preview cards (the one hero animation)

    /// R15's compact cards, so the screen fits iPhone 17 Pro unscrolled (R16).
    private func previewStack(compact: Bool) -> some View {
        VStack(spacing: NoctisCardDensity.compact.stackSpacing) {
            ForEach(NotificationKind.allCases) { kind in
                previewCard(kind, compact: compact)
                    .noctisScrollRow()
                    .noctisDropIn(index: kind.rawValue, appeared: cardsAppeared, reduceMotion: reduceMotion)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Examples of NOCTIS notifications")
    }

    private func previewCard(_ kind: NotificationKind, compact: Bool) -> some View {
        let isEnabled = enabledStates[kind.rawValue]
        return NoctisPaperCard(density: .compact) {
            HStack(alignment: .top, spacing: NoctisSpacing.sm) {
                NotificationAppTile(showCheckmark: checkmarkDrawn)
                VStack(alignment: .leading, spacing: 3) {
                    // One header row; at accessibility sizes the "Example"
                    // badge drops to its own line.
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 4) {
                            previewSender
                            exampleBadge
                        }
                    } else {
                        HStack(spacing: 6) {
                            previewSender
                            Spacer(minLength: 0)
                            exampleBadge
                        }
                    }
                    Text(kind.previewBody)
                        .noctisFont(14, relativeTo: .subheadline)
                        .foregroundStyle(NoctisPaper.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .noctisTextBlock()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isEnabled ? 1 : 0.4)
        .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion), value: isEnabled)
        .scaleEffect((isEnabled ? 1.0 : 0.97) * (cardsSettling ? 1.03 : 1.0))
        .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion), value: isEnabled)
        .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion), value: cardsSettling)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }

    private var previewSender: some View {
        HStack(spacing: 6) {
            Text("NOCTIS")
                .noctisFont(13, .semibold, relativeTo: .footnote)
                .foregroundStyle(NoctisPaper.ink)
            Text("now")
                .noctisFont(13, relativeTo: .footnote)
                .foregroundStyle(NoctisPaper.ink3)
        }
    }

    private var exampleBadge: some View {
        Text("Example")
            .noctisFont(12, .medium, relativeTo: .caption)
            .foregroundStyle(NoctisPaper.cocoa)
            .padding(.horizontal, NoctisSpacing.xs)
            .padding(.vertical, 3)
            .background(Capsule(style: .continuous).fill(NoctisPaper.butter))
            .fixedSize()
    }

    private func runEntranceIfNeeded() {
        guard !cardsAppeared else { return }
        cardsAppeared = true
    }

    // MARK: - Toggle card

    private func toggleCard(compact: Bool) -> some View {
        NoctisPaperCard(padding: NoctisSpacing.lg) {
            VStack(spacing: 0) {
                ForEach(NotificationKind.allCases) { kind in
                    toggleRow(kind)
                        .noctisTextBlock()
                    if kind != NotificationKind.allCases.last {
                        Rectangle()
                            .fill(NoctisPaper.hairline)
                            .frame(height: 1)
                            .padding(.vertical, NoctisScrollEdges.blockGap(compact ? NoctisSpacing.xs : NoctisSpacing.sm, dynamicTypeSize) / 2)
                    }
                }
            }
        }
        .noctisScrollRow()
        .noctisRise(index: NotificationKind.allCases.count)
    }

    private func toggleRow(_ kind: NotificationKind) -> some View {
        HStack(alignment: .center, spacing: NoctisSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.toggleTitle)
                    .noctisFont(17, .semibold, relativeTo: .body)
                    .foregroundStyle(NoctisPaper.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = kind.toggleSubtitle {
                    Text(subtitle)
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(NoctisPaper.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Toggle(kind.toggleTitle, isOn: binding(for: kind))
                .labelsHidden()
                .tint(NoctisPaper.cocoa)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(kind.toggleSubtitle.map { "\(kind.toggleTitle). \($0)" } ?? kind.toggleTitle)
    }

    private func binding(for kind: NotificationKind) -> Binding<Bool> {
        Binding(
            get: { enabledStates[kind.rawValue] },
            set: { newValue in
                NoctisHaptics.softImpact()
                enabledStates[kind.rawValue] = newValue
            }
        )
    }

    // MARK: - Bottom stack

    @ViewBuilder
    private var bottomStack: some View {
        if outcome != .denied {
            VStack(spacing: NoctisSpacing.sm) {
                NoctisCTA("Allow Notifications", isLoading: outcome == .requesting, action: requestPermission)
                NoctisTextButton("Not now", action: dismissWithoutAsking)
            }
        }
    }

    // MARK: - Permission + scheduling

    private func requestPermission() {
        NoctisHaptics.softImpact()
        outcome = .requesting
        rememberChoices()
        Task {
            let granted: Bool
            if let coordinator {
                granted = await coordinator.requestAuthorization()
            } else {
                granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            }
            guard granted else {
                outcome = .denied
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { onNext() }
                return
            }
            // The profile doesn't hold this wake time and need yet; the reminders are built from these.
            coordinator?.reschedule(wakeMinutes: wakeMinutes, needMinutes: needMinutes)
            outcome = .granted
            withAnimation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion)) {
                cardsSettling = true
                checkmarkDrawn = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion)) {
                    cardsSettling = false
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { onNext() }
        }
    }

    /// The three switches, kept as the person left them: they are what Settings shows and what the
    /// reminders are built from, whenever (and if ever) the system allows them.
    private func rememberChoices() {
        preferences?.update { values in
            values.notifications.morningIsOn = enabledStates[NotificationKind.morningSummary.rawValue]
            values.notifications.windDownIsOn = enabledStates[NotificationKind.windDown.rawValue]
            values.notifications.weeklyIsOn = enabledStates[NotificationKind.weeklyReview.rawValue]
        }
    }

    // MARK: - Not now

    private func dismissWithoutAsking() {
        guard !dismissing else { return }
        // Nobody opted in: nothing is on until they turn it on in Settings.
        preferences?.update { $0.notifications = .allOff }
        withAnimation(NoctisMotion.adaptive(.easeIn(duration: 0.3), reduceMotion: reduceMotion)) {
            dismissing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.2 : 0.3)) {
            onNext()
        }
    }
}

// MARK: - App tile

/// The 38pt cocoa app-icon stand-in shown on each example card. Owns its
/// own checkmark-draw progress so all three tiles animate identically off
/// one shared `showCheckmark` flip from the parent.
private struct NotificationAppTile: View {
    let showCheckmark: Bool

    @State private var checkmarkProgress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// R4: grows with the preview text beside it.
    @NoctisScaledLength(relativeTo: .subheadline) private var size: CGFloat = 38

    var body: some View {
        RoundedRectangle(cornerRadius: NoctisRadius.sm, style: .continuous)
            .fill(NoctisPaper.cocoa)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "moon.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(NoctisPaper.ivory)
                    .opacity(showCheckmark ? 0 : 1)
                NoctisCheckmarkShape()
                    .trim(from: 0, to: checkmarkProgress)
                    .stroke(NoctisPaper.ivory, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .frame(width: size * 0.44, height: size * 0.44)
            }
            .accessibilityHidden(true)
            .onChange(of: showCheckmark) { _, newValue in
                guard newValue else { checkmarkProgress = 0; return }
                if reduceMotion {
                    checkmarkProgress = 1
                } else {
                    withAnimation(.easeOut(duration: 0.35)) { checkmarkProgress = 1 }
                }
            }
    }
}

private struct NoctisCheckmarkShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

// MARK: - Hero drop-in

/// The screen's one hero animation (R9): cards drop from y -80 with a
/// -2 degree rotation, spring(response: .5, dampingFraction: .75),
/// staggered 0.25s per card. Reduce Motion collapses this to the cards
/// already in their stacked resting position with a plain 0.2s fade.
private struct NoctisDropInModifier: ViewModifier {
    let index: Int
    let appeared: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : -80)
            .rotationEffect(.degrees(appeared || reduceMotion ? 0 : -2))
            .animation(
                reduceMotion
                    ? .easeInOut(duration: 0.2)
                    : .spring(response: 0.5, dampingFraction: 0.75).delay(Double(index) * 0.25),
                value: appeared
            )
    }
}

private extension View {
    func noctisDropIn(index: Int, appeared: Bool, reduceMotion: Bool) -> some View {
        modifier(NoctisDropInModifier(index: index, appeared: appeared, reduceMotion: reduceMotion))
    }
}
