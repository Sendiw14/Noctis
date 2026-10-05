import DesignSystem
import HealthProviding
import NightKit
import NoctisCore
import OnboardingFeature
import SoundKit
import StoreKit
import SwiftUI

// MARK: - A row that picks from a few

/// A row whose value is chosen from a menu: the whole row opens the system's menu.
struct SettingsMenuRow<Value: Hashable>: View {
    let systemImage: String
    let fill: Color
    let title: String
    let options: [Value]
    let selection: Value
    let label: (Value) -> String
    let identifier: String
    let choose: (Value) -> Void
    var isEnabled = true

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    NoctisHaptics.selection()
                    choose(option)
                } label: {
                    if option == selection { Label(label(option), systemImage: "checkmark") } else { Text(label(option)) }
                }
            }
        } label: {
            NoctisRow(systemImage: systemImage, fill: fill, title: title, value: label(selection)) {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.noctisInk3)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("\(title), \(label(selection))")
        .accessibilityHint("Opens a menu of choices.")
        .accessibilityIdentifier(identifier)
    }
}

/// A row with a switch.
struct SettingsToggleRow: View {
    let systemImage: String
    let fill: Color
    let title: String
    var detail: String?
    @Binding var isOn: Bool
    let identifier: String
    var isEnabled = true

    var body: some View {
        NoctisRow(systemImage: systemImage, fill: fill, title: title, detail: detail) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(NoctisAppColor.cocoa)
                .disabled(!isEnabled)
                .accessibilityIdentifier(identifier)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Notifications

struct NotificationsSettingsView: View {
    let viewModel: SettingsViewModel

    private var preferences: AppPreferences { viewModel.preferences }
    private var values: NotificationPreferences { viewModel.values.notifications }
    private var enabled: Bool { NotificationsCopy.switchesAreEnabled(viewModel.authorization) }

    var body: some View {
        SettingsPageScaffold(.notifications, summary: "Choose which reminders NOCTIS sends, and when.") {
            banner.noctisRise(index: 0)
            morning.noctisRise(index: 1)
            windDown.noctisRise(index: 2)
            weekly.noctisRise(index: 3)
            SettingsNote("\(NotificationsCopy.privacyNote) Turning a reminder off removes it from the schedule.")
                .noctisRise(index: 4)
        }
        .task { await viewModel.onAppear() }
    }

    private var banner: some View {
        let banner = viewModel.banner
        return NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                Text(banner.title)
                    .noctisFont(17, .semibold, relativeTo: .body)
                    .foregroundStyle(NoctisAppColor.ink)
                Text(banner.detail)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                    .fixedSize(horizontal: false, vertical: true)
                if let action = banner.action {
                    NoctisCTA(action.title, icon: action == .allow ? "bell" : "gearshape", adaptive: true) {
                        Task { await viewModel.performBannerAction(action) }
                    }
                    .padding(.top, NoctisSpacing.xs)
                    .accessibilityIdentifier("settings.notifications.action")
                }
            }
        }
        .accessibilityIdentifier("settings.notifications.banner")
    }

    private var morning: some View {
        NoctisRowCard {
            SettingsToggleRow(
                systemImage: "sun.max", fill: NoctisAppColor.blockButter, title: "Morning summary",
                detail: "Says \"\(NotificationsCopy.morningSays)\"",
                isOn: binding(\.morningIsOn), identifier: "settings.notifications.morning", isEnabled: enabled
            )
            if values.morningIsOn {
                NoctisRowDivider()
                SettingsMenuRow(
                    systemImage: "clock", fill: NoctisAppColor.blockButter, title: "When", options: NotificationPreferences.morningOffsets,
                    selection: values.morningMinutesAfterWake, label: NotificationsCopy.minutesAfterWake, identifier: "settings.notifications.morning.when",
                    choose: { minutes in preferences.update { $0.notifications.morningMinutesAfterWake = minutes } }, isEnabled: enabled
                )
            }
        }
    }

    private var windDown: some View {
        NoctisRowCard {
            SettingsToggleRow(
                systemImage: "moon.stars", fill: NoctisAppColor.blockLavender, title: "Wind-down reminder",
                detail: "Says \"\(NotificationsCopy.windDownSays(leadMinutes: values.windDownLeadMinutes))\"",
                isOn: binding(\.windDownIsOn), identifier: "settings.notifications.windDown", isEnabled: enabled
            )
            if values.windDownIsOn {
                NoctisRowDivider()
                SettingsMenuRow(
                    systemImage: "clock", fill: NoctisAppColor.blockLavender, title: "When", options: NotificationPreferences.windDownLeads,
                    selection: values.windDownLeadMinutes, label: NotificationsCopy.minutesBeforeBed, identifier: "settings.notifications.windDown.when",
                    choose: { minutes in preferences.update { $0.notifications.windDownLeadMinutes = minutes } }, isEnabled: enabled
                )
            }
        }
    }

    private var weekly: some View {
        NoctisRowCard {
            SettingsToggleRow(
                systemImage: "calendar", fill: NoctisAppColor.blockSage, title: "Weekly review",
                detail: "Says \"\(NotificationsCopy.weeklySays)\"",
                isOn: binding(\.weeklyIsOn), identifier: "settings.notifications.weekly", isEnabled: enabled
            )
            if values.weeklyIsOn {
                NoctisRowDivider()
                SettingsMenuRow(
                    systemImage: "calendar.day.timeline.left", fill: NoctisAppColor.blockSage, title: "Day", options: Array(1...7),
                    selection: values.weeklyWeekday, label: { NotificationsCopy.weekdayName($0) }, identifier: "settings.notifications.weekly.day",
                    choose: { day in preferences.update { $0.notifications.weeklyWeekday = day } }, isEnabled: enabled
                )
                NoctisRowDivider()
                NoctisRow(systemImage: "clock", fill: NoctisAppColor.blockSage, title: "Time") {
                    DatePicker("Time", selection: weeklyTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .disabled(!enabled)
                        .accessibilityLabel("Weekly review time")
                        .accessibilityIdentifier("settings.notifications.weekly.time")
                }
            }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<NotificationPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { preferences.values.notifications[keyPath: keyPath] },
            set: { value in preferences.update { $0.notifications[keyPath: keyPath] = value } }
        )
    }

    /// The weekly time as a date today, for the system's time picker (only its hour and minute are used).
    private var weeklyTime: Binding<Date> {
        Binding(
            get: {
                let minutes = preferences.values.notifications.weeklyMinutesSinceMidnight
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                let minutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
                preferences.update { $0.notifications.weeklyMinutesSinceMidnight = minutes }
            }
        )
    }
}

// MARK: - Health data

struct HealthDataSettingsView: View {
    let viewModel: SettingsViewModel

    var body: some View {
        SettingsPageScaffold(.healthData, summary: "What NOCTIS can find in Apple Health.") {
            if let health = viewModel.health {
                if health.isUnavailable {
                    state(title: "Apple Health isn't available", detail: HealthCopy.unavailableDetail, health: health).noctisRise(index: 0)
                } else {
                    if !health.hasAnyData { state(title: HealthCopy.noDataTitle, detail: HealthCopy.noDataDetail, health: health).noctisRise(index: 0) }
                    kinds(health).noctisRise(index: 1)
                    notes(health).noctisRise(index: 2)
                    buttons(health).noctisRise(index: 3)
                }
            } else {
                NoctisAppCard {
                    Text("Looking in Apple Health")
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(.noctisInk2)
                }
                .accessibilityIdentifier("settings.health.loading")
            }
        }
        .task { await viewModel.refreshHealth() }
        .sheet(isPresented: Bindable(viewModel).showsHowAccessWorks) { HowAccessWorksSheet() }
    }

    /// No data at all: why, and the way back to the Connect flow where the system's question is still to be asked.
    private func state(title: String, detail: String, health: HealthDataStatus) -> some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                Text(title)
                    .noctisFont(17, .semibold, relativeTo: .body)
                    .foregroundStyle(NoctisAppColor.ink)
                Text(detail)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                    .fixedSize(horizontal: false, vertical: true)
                if health.canRequestAccess && !health.isUnavailable {
                    NoctisCTA(HealthCopy.connectButton, isLoading: viewModel.isConnectingHealth, icon: "heart.text.square", adaptive: true) {
                        Task { await viewModel.connectHealth() }
                    }
                    .padding(.top, NoctisSpacing.xs)
                    .accessibilityIdentifier("settings.health.connect")
                }
            }
        }
        .accessibilityIdentifier("settings.health.state")
    }

    private func kinds(_ health: HealthDataStatus) -> some View {
        SettingsGroup("WHAT NOCTIS CAN READ") {
            NoctisRowCard {
                ForEach(Array(health.kinds.enumerated()), id: \.element.id) { index, status in
                    if index > 0 { NoctisRowDivider() }
                    HealthKindRow(status: status)
                }
            }
        }
    }

    @ViewBuilder
    private func notes(_ health: HealthDataStatus) -> some View {
        if let source = HealthCopy.sourceLine(health.lastNightSource) {
            SettingsNote(source).accessibilityIdentifier("settings.health.source")
        }
        if !health.missing.isEmpty && health.hasAnyData {
            SettingsNote(HealthCopy.emptyExplanation).accessibilityIdentifier("settings.health.explanation")
        }
    }

    private func buttons(_ health: HealthDataStatus) -> some View {
        VStack(spacing: NoctisSpacing.xs) {
            NoctisCTA(HealthCopy.openHealthButton, icon: "arrow.up.right", adaptive: true) { viewModel.openHealth() }
                .accessibilityIdentifier("settings.health.open")
                .accessibilityHint("Opens the Health app.")
            if health.canRequestAccess && health.hasAnyData {
                NoctisTextButton(HealthCopy.connectButton, adaptive: true) { Task { await viewModel.connectHealth() } }
                    .accessibilityIdentifier("settings.health.connect")
            }
            NoctisTextButton(HealthCopy.howAccessWorksButton, adaptive: true) { viewModel.showsHowAccessWorks = true }
                .accessibilityIdentifier("settings.health.howAccessWorks")
        }
    }
}

/// One kind of Health data: its name, what was found, and what it is for.
struct HealthKindRow: View {
    let status: HealthKindStatus

    var body: some View {
        HStack(alignment: .top, spacing: NoctisSpacing.sm) {
            NoctisIconTile(
                systemImage: status.hasData ? "checkmark" : "minus", fill: status.hasData ? NoctisAppColor.blockSage : NoctisAppColor.track,
                foreground: status.hasData ? NoctisAppColor.blockInk : NoctisAppColor.ink2, size: NoctisRow<EmptyView>.tile
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(status.kind.displayName)
                    .noctisFont(17, .semibold, relativeTo: .body)
                    .foregroundStyle(NoctisAppColor.ink)
                Text(HealthCopy.line(status))
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                Text(HealthCopy.purpose(status.kind))
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(.noctisInk3)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, NoctisSpacing.xs)
        .frame(minHeight: 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(status.kind.displayName). \(HealthCopy.line(status)). \(HealthCopy.purpose(status.kind))")
        .accessibilityIdentifier("settings.health.kind.\(status.kind.rawValue)")
    }
}

struct HowAccessWorksSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                    ForEach(HealthCopy.howAccessWorks, id: \.self) { paragraph in
                        Text(paragraph)
                            .noctisFont(17, relativeTo: .body)
                            .foregroundStyle(NoctisAppColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(NoctisSpacing.lg)
            }
            .background(PaperBackground(adaptive: true).ignoresSafeArea())
            .navigationTitle("How access works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("settings.health.howSheet")
    }
}

// MARK: - Appearance

struct AppearanceSettingsView: View {
    let viewModel: SettingsViewModel
    private var preferences: AppPreferences { viewModel.preferences }

    var body: some View {
        SettingsPageScaffold(.appearance, summary: viewModel.offersHaptics ? "How NOCTIS looks, and how it feels." : "How NOCTIS looks.") {
            SettingsGroup("LOOK") {
                NoctisRowCard {
                    ForEach(Array(AppAppearance.allCases.enumerated()), id: \.element) { index, appearance in
                        if index > 0 { NoctisRowDivider() }
                        choice(appearance)
                    }
                }
            }
            .noctisRise(index: 0)
            if viewModel.offersHaptics {
                SettingsGroup("FEEL") {
                    NoctisRowCard {
                        SettingsToggleRow(
                            systemImage: "hand.tap", fill: NoctisAppColor.blockButter, title: "App haptics", detail: "Follows your system haptics setting.",
                            isOn: Binding(get: { preferences.values.appHaptics }, set: { value in preferences.update { $0.appHaptics = value } }),
                            identifier: "settings.appearance.haptics"
                        )
                    }
                }
                .noctisRise(index: 1)
            }
        }
    }

    private func choice(_ appearance: AppAppearance) -> some View {
        let selected = preferences.values.appearance == appearance
        return Button {
            NoctisHaptics.selection()
            preferences.update { $0.appearance = appearance }
        } label: {
            NoctisRow(systemImage: symbol(appearance), fill: NoctisAppColor.blockLavender, title: appearance.title) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selected ? NoctisAppColor.ink : NoctisAppColor.ink3)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(appearance.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("settings.appearance.\(appearance.rawValue)")
    }

    private func symbol(_ appearance: AppAppearance) -> String {
        switch appearance {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

// MARK: - Subscription

struct SubscriptionSettingsView: View {
    let viewModel: SettingsViewModel
    @State private var scrollTick = 0
    @State private var showsComparison = false

    var body: some View {
        let summary = viewModel.subscription
        SettingsPageScaffold(.subscription, summary: summary.isPremium ? "You have Premium." : "You're on the free plan.") {
            NoctisAppCard {
                VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                    NoctisCaption("YOUR PLAN", style: .noctisInk3)
                    Text(summary.headline)
                        .noctisFont(28, .bold, relativeTo: .title)
                        .foregroundStyle(NoctisAppColor.ink)
                        .accessibilityIdentifier("settings.subscription.headline")
                    Text(summary.detail())
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(.noctisInk2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.subscription.detail")
                }
            }
            .noctisRise(index: 0)
            VStack(spacing: NoctisSpacing.xs) {
                if summary.isPremium {
                    NoctisCTA("Manage subscription", icon: "arrow.up.right", adaptive: true) { viewModel.showsManageSubscription = true }
                        .accessibilityIdentifier("settings.subscription.manage")
                        .accessibilityHint("Opens your subscription in the App Store.")
                } else {
                    NoctisCTA("Upgrade to Premium", icon: "star", adaptive: true) { viewModel.showsPaywall = true }
                        .accessibilityIdentifier("settings.subscription.upgrade")
                }
                NoctisTextButton(viewModel.isRestoring ? "Restoring" : "Restore purchases", adaptive: true) { Task { await viewModel.restore() } }
                    .disabled(viewModel.isRestoring)
                    .accessibilityIdentifier("settings.subscription.restore")
                if let message = viewModel.restoreMessage {
                    Text(message)
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk2)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("settings.subscription.restoreMessage")
                }
            }
            .noctisRise(index: 1)
            // The full list of what is free and what Premium adds, made from the one feature table (R59).
            SettingsGroup("PREMIUM") {
                NoctisRowCard {
                    NoctisLinkRow(
                        systemImage: "list.bullet.rectangle", fill: NoctisAppColor.blockButter, title: "What Premium includes",
                        detail: "Everything on the free plan, and what Premium adds.", hint: "Opens the comparison of free and Premium.",
                        identifier: "settings.subscription.compare"
                    ) { showsComparison = true }
                }
            }
            .noctisRise(index: 2)
            SettingsNote("Payments, renewals and cancellations are handled by the App Store, with your Apple Account.")
                .noctisRise(index: 3)
        }
        .sheet(isPresented: $showsComparison) { PremiumComparisonSheet() }
        .manageSubscriptionsSheet(isPresented: Bindable(viewModel).showsManageSubscription)
        .fullScreenCover(isPresented: Bindable(viewModel).showsPaywall) {
            UpgradePaywall(wakeMinutes: viewModel.wakeMinutes, needMinutes: viewModel.needMinutes) {
                viewModel.showsPaywall = false
                Task { await viewModel.entitlements.refresh() }
            }
        }
        .task { await viewModel.onAppear() }
    }
}

// MARK: - Wind-down defaults

struct WindDownSettingsView: View {
    let viewModel: SettingsViewModel
    private var preferences: AppPreferences { viewModel.preferences }

    var body: some View {
        SettingsPageScaffold(.windDown, summary: "What a wind-down starts with. You can still change it in the session.") {
            NoctisRowCard {
                SettingsMenuRow(
                    systemImage: "timer", fill: NoctisAppColor.blockLavender, title: "Length", options: WindDownClock.options,
                    selection: preferences.values.windDownMinutes, label: { "\($0) min" }, identifier: "settings.windDown.length",
                    choose: { minutes in preferences.update { $0.windDownMinutes = minutes } }
                )
                NoctisRowDivider()
                SettingsMenuRow(
                    systemImage: "speaker.wave.2", fill: NoctisAppColor.blockSage, title: "Sound", options: [SoundKind?.none] + SoundKind.allCases.map { Optional($0) },
                    selection: preferences.values.windDownSound, label: { $0?.title ?? "None" }, identifier: "settings.windDown.sound",
                    choose: { sound in preferences.update { $0.windDownSound = sound } }
                )
            }
            .noctisRise(index: 0)
            SettingsGroup("BREATHING") {
                NoctisRowCard {
                    SettingsMenuRow(
                        systemImage: "wind", fill: NoctisAppColor.blockButter, title: "Pattern", options: BreathingPattern.all.map(\.id),
                        selection: preferences.values.breathingPattern, label: { BreathingPattern.pattern($0).title },
                        identifier: "settings.windDown.pattern", choose: { id in preferences.update { $0.breathingPattern = id } }
                    )
                    NoctisRowDivider()
                    SettingsMenuRow(
                        systemImage: "timer", fill: NoctisAppColor.blockButter, title: "Length", options: BreathingSchedule.durations,
                        selection: preferences.values.breathingMinutes, label: { "\($0) min" }, identifier: "settings.windDown.breathingLength",
                        choose: { minutes in preferences.update { $0.breathingMinutes = minutes } }
                    )
                    if viewModel.offersHaptics {
                        NoctisRowDivider()
                        SettingsToggleRow(
                            systemImage: "hand.tap", fill: NoctisAppColor.blockButter, title: "Haptics", detail: "A soft tap that follows each breath.",
                            isOn: Binding(get: { preferences.values.breathingHaptics }, set: { value in preferences.update { $0.breathingHaptics = value } }),
                            identifier: "settings.windDown.haptics"
                        )
                    }
                }
            }
            .noctisRise(index: 1)
        }
    }
}

// MARK: - Sleep sounds defaults

struct SoundsSettingsView: View {
    let viewModel: SettingsViewModel
    private var preferences: AppPreferences { viewModel.preferences }

    var body: some View {
        SettingsPageScaffold(.sounds, summary: "Where a sleep sound starts. Each sound has its own volume once it plays.") {
            NoctisRowCard {
                VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                    HStack {
                        Text("Starting volume")
                            .noctisFont(17, .semibold, relativeTo: .body)
                            .foregroundStyle(NoctisAppColor.ink)
                        Spacer(minLength: NoctisSpacing.xs)
                        Text("\(preferences.values.soundsGainPercent)%")
                            .noctisFont(15, relativeTo: .subheadline)
                            .foregroundStyle(.noctisInk2)
                            .contentTransition(.numericText())
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { Double(preferences.values.soundsGainPercent) },
                            set: { value in preferences.update { $0.soundsGainPercent = Int(value) } }
                        ),
                        in: 0...100, step: 5
                    )
                    .tint(NoctisAppColor.cocoa)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Starting volume")
                    .accessibilityValue("\(preferences.values.soundsGainPercent) percent")
                    .accessibilityIdentifier("settings.sounds.volume")
                }
                .padding(.vertical, NoctisSpacing.xs)
                NoctisRowDivider()
                SettingsMenuRow(
                    systemImage: "timer", fill: NoctisAppColor.blockLavender, title: "Sleep timer", options: SleepTimerChoice.allCases,
                    selection: preferences.values.soundsTimer, label: \.title, identifier: "settings.sounds.timer",
                    choose: { choice in preferences.update { $0.soundsTimer = choice } }
                )
            }
            .noctisRise(index: 0)
        }
    }
}
