import DesignSystem
import NoctisCore
import SwiftUI
import UserNotifications

/// The three reminders the step offers, in the order shown. The example text is the notification's own words (R13: generic only, no streak counts, no
/// scores, no biometric values); the row's colour and glyph are the step's.
enum NotificationKind: Int, CaseIterable, Identifiable {
    case morningSummary
    case windDown
    case weeklyReview

    var id: Int { rawValue }

    /// Doubles as the scheduled notification's body: one source of truth so the example can never drift from what actually gets sent.
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

    var toggleSubtitle: String {
        switch self {
        case .morningSummary: "Your night and recovery, ready when you wake"
        case .windDown: "20 minutes before your bedtime"
        case .weeklyReview: "A calm look back, once a week"
        }
    }

    var glyph: String {
        switch self {
        case .morningSummary: "sun.max"
        case .windDown: "moon.fill"
        case .weeklyReview: "calendar"
        }
    }

    var color: Color {
        switch self {
        case .morningSummary: NoctisSection.home.fill
        case .windDown: NoctisPaper.lavender
        case .weeklyReview: NoctisPaper.sage
        }
    }

    var identifier: String {
        switch self {
        case .morningSummary: NoctisNotification.morningSummary
        case .windDown: NoctisNotification.windDown
        case .weeklyReview: NoctisNotification.weeklyReview
        }
    }

    /// What VoiceOver reads for the stack: "Example notification: your morning summary is ready".
    var spokenExample: String {
        let body = previewBody.hasSuffix(".") ? String(previewBody.dropLast()) : previewBody
        return "Example notification: \(body.prefix(1).lowercased() + body.dropFirst())"
    }

    /// The example after this one, wrapping round.
    var next: NotificationKind { NotificationKind(rawValue: (rawValue + 1) % NotificationKind.allCases.count) ?? .morningSummary }

    /// "Morning summary. Your night and recovery, ready when you wake": the switch's label for VoiceOver.
    var spokenSwitch: String { "\(toggleTitle). \(toggleSubtitle)" }
}

private enum PermissionOutcome: Equatable {
    case idle
    case requesting
    case granted
    case denied
}

/// Step 5/6, in the band style (APP_RULES.md R6, R69): a stack of one example notification (tap for the next), a switch for each of the three reminders,
/// and a real `UNUserNotificationCenter` permission request that schedules only what is still on. iOS never lets an app re-show its own system prompt after
/// the first answer, so `.denied` here reads "the user just said no" (or authorization otherwise failed) and is handled with a plain reassurance, never a
/// nag or a retry button (R13).
struct NotificationsScreen: View {
    let wakeMinutes: Int
    let needMinutes: Int
    let onNext: () -> Void
    let onBack: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where the choices are kept, and what keeps the reminders matching them (R38). Nil in a preview.
    @Environment(\.appPreferences) private var preferences
    @Environment(\.notificationCoordinator) private var coordinator

    @State private var enabledStates: [Bool] = NotificationKind.allCases.map { _ in true }
    @State private var shown: NotificationKind = .morningSummary
    @State private var appeared = false
    @State private var cardsSettling = false
    @State private var checkmarkDrawn = false
    @State private var dismissing = false
    @State private var outcome: PermissionOutcome = .idle

    var body: some View {
        OnboardingStepScaffold(
            section: .insights,
            step: 4,
            title: ["Stay", "gently informed."],
            subtitle: outcome == .denied ? "You can turn this on in Settings anytime." : nil,
            topTrailingSymbol: "bell.fill",
            titleSize: 42,
            titleLeading: -7,
            onBack: onBack
        ) {
            NotificationsContent(
                enabled: enabledStates, shown: shown, appeared: appeared || reduceMotion, settling: cardsSettling, checkmarkDrawn: checkmarkDrawn,
                cycle: cycle, set: set
            )
            .opacity(dismissing ? 0 : 1)
            .offset(y: dismissing ? -40 : 0)
        } actions: {
            bottomStack
        }
        .onAppear {
            guard !appeared else { return }
            appeared = true
        }
    }

    /// A tap on the example: the next of the three, with a soft crossfade.
    private func cycle() {
        NoctisHaptics.selectionTick()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { shown = shown.next }
    }

    /// A switch changed: kept, and the example turns to that reminder so the change is seen where it is made.
    private func set(_ kind: NotificationKind, _ isOn: Bool) {
        NoctisHaptics.softImpact()
        enabledStates[kind.rawValue] = isOn
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { shown = kind }
    }

    // MARK: - Bottom stack

    @ViewBuilder
    private var bottomStack: some View {
        if outcome != .denied {
            VStack(spacing: 4) {
                OnboardingPrimaryButton("Allow Notifications", isEnabled: outcome != .requesting, identifier: "notifications.allow", action: requestPermission)
                OnboardingSecondaryButton("Not now", identifier: "notifications.notNow", action: dismissWithoutAsking)
            }
        }
    }

    // MARK: - Permission + scheduling

    private func requestPermission() {
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

// MARK: - The content

private let notificationCardDark = noctisHexColor("3A271C")

/// The example stack (with its caption) and the settings card. Reads the scaffold's scale, so on a short screen (an SE) the cards give a little height back.
private struct NotificationsContent: View {
    let enabled: [Bool]
    let shown: NotificationKind
    let appeared: Bool
    let settling: Bool
    let checkmarkDrawn: Bool
    let cycle: () -> Void
    let set: (NotificationKind, Bool) -> Void

    @Environment(\.onboardingScale) private var scale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dark: Bool { colorScheme == .dark }
    private var compact: Bool { scale < 0.85 }
    private var ink: Color { dark ? NoctisPaper.ivory : NoctisPaper.ink }
    private var cardFill: Color { dark ? notificationCardDark : NoctisPaper.surface }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("EXAMPLE")
                .noctisFont(11, .bold, relativeTo: .caption2, maxScale: 1.3)
                .tracking(1.3)
                .foregroundStyle(ink.opacity(0.65))
                .padding(.leading, 8)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            ExampleStack(
                kind: shown, isOn: enabled[shown.rawValue], fanned: appeared, settling: settling, checkmarkDrawn: checkmarkDrawn, compact: compact, tap: cycle
            )
            .padding(.bottom, compact ? 20 : 26)
            settingsCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            ForEach(NotificationKind.allCases) { kind in
                row(kind)
                    .slideUp(index: kind.rawValue, appeared: appeared, reduceMotion: reduceMotion, stagger: 0.06)
                if kind != NotificationKind.allCases.last {
                    Rectangle().fill(ink.opacity(0.10)).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, compact ? 2 : 6)
        .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(cardFill))
        .shadow(color: dark ? .clear : NoctisPaper.ink.opacity(0.10), radius: 12, x: 0, y: 5)
    }

    private func row(_ kind: NotificationKind) -> some View {
        let isOn = Binding(get: { enabled[kind.rawValue] }, set: { set(kind, $0) })
        return HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle().fill(kind.color)
                Image(systemName: kind.glyph).font(.system(size: 17, weight: .semibold)).foregroundStyle(NoctisPaper.ink)
            }
            .frame(width: compact ? 34 : 40, height: compact ? 34 : 40)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.toggleTitle)
                    .noctisFont(compact ? 16 : 17, .bold, relativeTo: .body, maxScale: 1.25)
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(kind.toggleSubtitle)
                    .noctisFont(compact ? 12 : 13, relativeTo: .footnote, maxScale: 1.25)
                    .foregroundStyle(ink.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Toggle(kind.toggleTitle, isOn: isOn)
                .labelsHidden()
                .tint(kind.color)
        }
        .padding(.vertical, compact ? 7 : 13)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(kind.spokenSwitch)
        .accessibilityIdentifier("notifications.toggle.\(kind.rawValue)")
    }
}

// MARK: - The example stack

/// One notification in front and two behind it, fanned 14 pt apart and scaled .94 and .88 with less opacity. Tapping it shows the next example.
private struct ExampleStack: View {
    let kind: NotificationKind
    let isOn: Bool
    let fanned: Bool
    let settling: Bool
    let checkmarkDrawn: Bool
    let compact: Bool
    let tap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dark: Bool { colorScheme == .dark }
    private var ink: Color { dark ? NoctisPaper.ivory : NoctisPaper.ink }
    private var fill: Color { dark ? notificationCardDark : NoctisPaper.surface }

    var body: some View {
        let step: CGFloat = compact ? 12 : 14
        front
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    backCard(scale: 0.88, depth: 2, opacity: 0.5, step: step)
                    backCard(scale: 0.94, depth: 1, opacity: 0.75, step: step)
                }
            }
            .opacity(isOn ? 1 : 0.4)
            .scaleEffect((isOn ? 1 : 0.97) * (settling ? 1.03 : 1), anchor: .top)
            .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion), value: isOn)
            .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion), value: settling)
            .contentShape(Rectangle())
            .onTapGesture(perform: tap)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(kind.spokenExample)
            .accessibilityHint("Shows the next example")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, tap)
            .accessibilityIdentifier("notifications.example")
    }

    private var front: some View {
        HStack(alignment: .center, spacing: 12) {
            NotificationAppTile(showCheckmark: checkmarkDrawn, compact: compact, dark: dark)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("NOCTIS").noctisFont(13, .bold, relativeTo: .footnote, maxScale: 1.25).foregroundStyle(ink)
                    Text("now").noctisFont(13, relativeTo: .footnote, maxScale: 1.25).foregroundStyle(dark ? NoctisPaper.ivory.opacity(0.6) : NoctisPaper.ink3)
                }
                Text(kind.previewBody)
                    .noctisFont(14, relativeTo: .subheadline, maxScale: 1.25)
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(kind)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: compact ? 66 : 74, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(fill))
        .shadow(color: dark ? .black.opacity(0.25) : NoctisPaper.ink.opacity(0.12), radius: 10, x: 0, y: 4)
    }

    private func backCard(scale: CGFloat, depth: CGFloat, opacity: Double, step: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(fill.opacity(opacity))
            .shadow(color: dark ? .clear : NoctisPaper.ink.opacity(0.08), radius: 6, x: 0, y: 2)
            .scaleEffect(fanned ? scale : 1, anchor: .top)
            .offset(y: fanned ? step * depth : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.75).delay(0.15 * Double(depth)), value: fanned)
    }
}

// MARK: - App tile

/// The app-icon stand-in on the example: cocoa with an ivory crescent in Light, ivory with a cocoa one in Dark. On a grant the crescent becomes a drawn
/// check (one flip from the parent).
private struct NotificationAppTile: View {
    let showCheckmark: Bool
    let compact: Bool
    let dark: Bool

    @State private var checkmarkProgress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// R4: grows with the text beside it.
    @NoctisScaledLength(relativeTo: .subheadline) private var base: CGFloat = 46

    private var size: CGFloat { compact ? base * 0.84 : base }
    private var glyph: Color { dark ? NoctisPaper.cocoa : NoctisPaper.ivory }

    var body: some View {
        RoundedRectangle(cornerRadius: NoctisRadius.sm, style: .continuous)
            .fill(dark ? NoctisPaper.ivory : NoctisPaper.cocoa)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "moon.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(glyph)
                    .opacity(showCheckmark ? 0 : 1)
                NoctisCheckmarkShape()
                    .trim(from: 0, to: checkmarkProgress)
                    .stroke(glyph, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .frame(width: size * 0.44, height: size * 0.44)
            }
            .accessibilityHidden(true)
            .onChange(of: showCheckmark) { _, newValue in
                guard newValue else {
                    checkmarkProgress = 0
                    return
                }
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
