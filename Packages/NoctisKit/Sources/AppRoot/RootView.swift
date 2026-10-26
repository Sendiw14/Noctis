import AuthenticationServices
import CoachFeature
import DesignSystem
import HomeFeature
import InsightsFeature
import NightFeature
import NoctisCore
import OnboardingFeature
import ProfileFeature
import RecoveryFeature
import SleepFeature
import SwiftUI

/// Onboarding until it's complete, then the main app — on every later
/// launch too. Onboarding is light-only; the main app follows the person's
/// choice (System, Light or Dark: APP_RULES.md R5, R38), at once.
public struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppPreferences.self) private var preferences
    @Environment(AccountStore.self) private var account
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showMain: Bool
    /// The onboarding steps in the band style follow the system's appearance; the others are light (`AppAppearance.scheme`).
    @State private var followsSystem = true

    public init(initiallyOnboarded: Bool) {
        _showMain = State(initialValue: initiallyOnboarded)
    }

    public var body: some View {
        Group {
            if showMain {
                RootTabView()
                    .transition(.opacity)
            } else {
                OnboardingFlowView(onFollowsSystem: { followsSystem = $0 }) {
                    model.open(.home)
                    withAnimation(NoctisMotion.adaptive(NoctisMotion.reveal, reduceMotion: reduceMotion)) {
                        showMain = true
                    }
                }
                .transition(.opacity)
            }
        }
        // Sign in with Apple, optional (R69): at launch Apple says whether the identifier is still good, and a revocation signs out here. Neither
        // ever blocks anything or shows a wall; the local data stays.
        .task { await account.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in account.credentialRevoked() }
        .preferredColorScheme(AppAppearance.scheme(showingMain: showMain, followsSystem: followsSystem, appearance: preferences.values.appearance))
        // The paywall, over whatever opened it: a locked thing was tapped (R58). Closing it, or cancelling a purchase, changes nothing; a purchase unlocks the
        // screens in place (they read the feature gate).
        .sheet(item: Bindable(model).paywall) { context in
            UpgradePaywall(wakeMinutes: model.profile.typicalWakeMinutes, needMinutes: model.profile.needMinutes, context: context) {
                model.dismissPaywall()
            }
        }
        .onOpenURL { url in
            // A URL from outside: only NOCTIS's own links open anything (WidgetURLRouter, R44): a screen, or the paywall sheet (R62).
            if let destination = WidgetURLRouter.destination(for: url) { model.open(destination) }
        }
    }
}

/// The main app's tab bar (R7): a system `TabView` on the `Tab` API, in
/// Liquid Glass. Home is the default tab. The bar minimizes as content
/// scrolls down; in the evening a bedtime accessory sits on it on every
/// tab.
///
/// The minute clock (`HomeClock`) is in the environment: the accessory,
/// Home's header summary and the evening countdown each read it in their
/// own body, and nothing above them does, so a minute passing re-evaluates
/// those and no more.
struct RootTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeViewModel.self) private var home
    @Environment(SleepViewModel.self) private var sleep
    @Environment(RecoveryViewModel.self) private var recovery
    @Environment(InsightsViewModel.self) private var insights
    @Environment(CoachViewModel.self) private var coach
    @Environment(TonightViewModel.self) private var tonight
    @Environment(SoundsViewModel.self) private var sounds
    @Environment(WindDownViewModel.self) private var windDown
    @Environment(BreathingViewModel.self) private var breathing
    @Environment(MeditationViewModel.self) private var meditation
    @Environment(JournalViewModel.self) private var journal
    @Environment(ProfileViewModel.self) private var profile
    @Environment(SettingsViewModel.self) private var settings
    @Environment(NotificationCoordinator.self) private var notifications
    @Environment(\.scenePhase) private var scenePhase
    @State private var clock = HomeClock()

    var body: some View {
        tabs
            .environment(\.homeClock, clock)
            .task {
                // The reminders match the preferences, the wake time and the bedtime engine from the start.
                await notifications.refreshAuthorization()
                notifications.reschedule()
            }
            .task {
                clock.start()
                // A deep link that arrived before this view existed.
                if let destination = model.takeSleepDestination() { sleep.open(destination) }
                if let destination = model.takeRecoveryDestination() { open(destination) }
                if let destination = model.takeInsightsDestination() { insights.select(filter: destination.category) }
            }
            .onChange(of: model.sleepDestination) { _, destination in
                guard destination != nil, let taken = model.takeSleepDestination() else { return }
                sleep.open(taken)
            }
            .onChange(of: model.recoveryDestination) { _, destination in
                guard destination != nil, let taken = model.takeRecoveryDestination() else { return }
                open(taken)
            }
            .onChange(of: model.insightsDestination) { _, destination in
                guard destination != nil, let taken = model.takeInsightsDestination() else { return }
                insights.select(filter: taken.category)
            }
            .onChange(of: scenePhase) { _, phase in
                // Ticks only while the app is up; catches up on return.
                if phase == .active { clock.start() } else { clock.stop() }
                // Back at the front: the system's answer may have changed in Settings, and the bedtime's
                // centre moves a little as nights come in.
                if phase == .active {
                    Task {
                        await notifications.refreshAuthorization()
                        notifications.reschedule()
                    }
                }
            }
            .onChange(of: model.selectedTab) {
                // A tab switch runs until the first frame after the new
                // tab's content appears (or a second, if it never does).
                NoctisSignpost.begin(.tabSwitch)
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    NoctisSignpost.end(.tabSwitch)
                }
            }
    }

    private func open(_ destination: RecoveryDestination) {
        recovery.open(segment: destination.segment, factor: destination.factor, factorRange: destination.segment.factorRange)
    }

    /// The selected glyph takes its section's ink (Home apricot, Sleep sage,
    /// Recovery lavender, Insights butter, Coach rose). Unselected glyphs
    /// stay neutral.
    private var tabTint: Color {
        switch model.selectedTab {
        case .home: NoctisSection.home.ink
        case .sleep: NoctisSection.sleep.ink
        case .recovery: NoctisSection.recovery.ink
        case .insights: NoctisSection.insights.ink
        case .coach: NoctisSection.coach.ink
        }
    }

    @ViewBuilder
    private var tabs: some View {
        // Pressing the tab that's showing is a re-tap, not a change.
        let selection = Binding<AppTab>(
            get: { model.selectedTab },
            set: { tab in
                if tab == model.selectedTab {
                    model.retap(tab)
                } else {
                    model.selectedTab = tab
                }
            }
        )
        let tabView = TabView(selection: selection) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    destination(for: tab)
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(tabTint)
        // `tabViewBottomAccessory(isEnabled:)` is iOS 26.1, the app's minimum (QA_LEDGER.md), so it can hide by day. It is also off while the wind-down is
        // showing: that screen is full-screen and dark, and the bedtime pill would float over it.
        tabView.tabViewBottomAccessory(isEnabled: HomeBedtimeAccessory.isShown(for: home) && !model.isWindDownShowing && !model.isReviewStoryShowing) {
            HomeBedtimeAccessory(viewModel: home, clock: clock) { model.open(.tonight) }
        }
    }

    @ViewBuilder
    private func destination(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeTabView(
                viewModel: home,
                recoveryScreen: { focus in AnyView(RecoveryPushedScreen(viewModel: recovery, focus: focus)) },
                recoveryFactor: { kind, range in AnyView(RecoveryPushedFactorScreen(viewModel: recovery, kind: kind, range: range)) },
                tonightScreen: { AnyView(TonightScreen(viewModel: tonight, breathing: breathing, journal: journal)) },
                soundsScreen: { AnyView(SoundsScreen(viewModel: sounds)) },
                windDownScreen: { autostart in
                    AnyView(
                        WindDownScreen(
                            autostart: autostart, viewModel: windDown, sounds: sounds, breathing: breathing, meditation: meditation, journal: journal))
                },
                profileScreen: { AnyView(ProfileScreen(viewModel: profile)) },
                settingsScreen: { page in AnyView(SettingsScreen(page: page, viewModel: settings)) },
                dataCategoryScreen: { id in AnyView(PrivacyCategoryView(id: id, viewModel: settings)) }
            )
            .onAppear { NoctisSignpost.endAfterNextFrame(.tabSwitch) }
        case .sleep:
            SleepTabView(viewModel: sleep)
                .onAppear { NoctisSignpost.endAfterNextFrame(.tabSwitch) }
        case .recovery:
            RecoveryTabView(viewModel: recovery)
                .onAppear { NoctisSignpost.endAfterNextFrame(.tabSwitch) }
        case .insights:
            InsightsTabView(viewModel: insights)
                .onAppear { NoctisSignpost.endAfterNextFrame(.tabSwitch) }
        case .coach:
            CoachTabView(viewModel: coach)
                .onAppear { NoctisSignpost.endAfterNextFrame(.tabSwitch) }
        }
    }
}
