import DesignSystem
import HomeFeature
import NoctisCore
import OnboardingFeature
import RecoveryFeature
import SleepFeature
import SwiftUI

/// Onboarding until it's complete, then the main app — on every later
/// launch too. Onboarding is light-only; the main app follows the system
/// Light/Dark setting (APP_RULES.md R5).
public struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showMain: Bool

    public init(initiallyOnboarded: Bool) {
        _showMain = State(initialValue: initiallyOnboarded)
    }

    public var body: some View {
        Group {
            if showMain {
                RootTabView()
                    .transition(.opacity)
            } else {
                OnboardingFlowView {
                    model.open(.home)
                    withAnimation(NoctisMotion.adaptive(NoctisMotion.reveal, reduceMotion: reduceMotion)) {
                        showMain = true
                    }
                }
                .transition(.opacity)
            }
        }
        .preferredColorScheme(showMain ? nil : .light)
        .onOpenURL { url in
            if let route = AppRoute(url: url) { model.open(route) }
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var clock = HomeClock()

    var body: some View {
        tabs
            .environment(\.homeClock, clock)
            .task {
                clock.start()
                // A deep link that arrived before this view existed.
                if let destination = model.takeSleepDestination() { sleep.open(destination) }
                if let destination = model.takeRecoveryDestination() { open(destination) }
            }
            .onChange(of: model.sleepDestination) { _, destination in
                guard destination != nil, let taken = model.takeSleepDestination() else { return }
                sleep.open(taken)
            }
            .onChange(of: model.recoveryDestination) { _, destination in
                guard destination != nil, let taken = model.takeRecoveryDestination() else { return }
                open(taken)
            }
            .onChange(of: scenePhase) { _, phase in
                // Ticks only while the app is up; catches up on return.
                if phase == .active { clock.start() } else { clock.stop() }
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
        .tint(NoctisAppColor.ink)
        // `tabViewBottomAccessory(isEnabled:)` is iOS 26.1; on 26.0 there's
        // no accessory rather than one that can't hide by day.
        if #available(iOS 26.1, *) {
            tabView.tabViewBottomAccessory(isEnabled: HomeBedtimeAccessory.isShown(for: home)) {
                HomeBedtimeAccessory(viewModel: home, clock: clock) { model.open(.home) }
            }
        } else {
            tabView
        }
    }

    @ViewBuilder
    private func destination(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeTabView(
                viewModel: home,
                recoveryScreen: { focus in AnyView(RecoveryPushedScreen(viewModel: recovery, focus: focus)) },
                recoveryFactor: { kind, range in AnyView(RecoveryPushedFactorScreen(viewModel: recovery, kind: kind, range: range)) }
            )
            .onAppear { NoctisSignpost.endAfterNextFrame(.tabSwitch) }
        case .sleep:
            SleepTabView(viewModel: sleep)
                .onAppear { NoctisSignpost.endAfterNextFrame(.tabSwitch) }
        case .recovery:
            RecoveryTabView(viewModel: recovery)
                .onAppear { NoctisSignpost.endAfterNextFrame(.tabSwitch) }
        case .insights, .coach:
            // R19: unbuilt tabs, listed in ROADMAP.md.
            NoctisComingSoonView(title: tab.title, systemImage: tab.systemImage)
                .onAppear { NoctisSignpost.endAfterNextFrame(.tabSwitch) }
        }
    }
}
