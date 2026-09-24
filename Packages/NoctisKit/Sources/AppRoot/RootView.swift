import DesignSystem
import HomeFeature
import NoctisCore
import OnboardingFeature
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
/// The app's one countdown `TimelineView` (every minute) wraps it, so the
/// accessory, Home's header and the evening countdown all tick together.
struct RootTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeViewModel.self) private var home

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            tabs(now: timeline.date)
                .environment(\.homeMinute, timeline.date)
        }
    }

    @ViewBuilder
    private func tabs(now: Date) -> some View {
        @Bindable var model = model
        let tabView = TabView(selection: $model.selectedTab) {
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
                HomeBedtimeAccessory(viewModel: home, now: now) { model.open(.home) }
            }
        } else {
            tabView
        }
    }

    @ViewBuilder
    private func destination(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeTabView(viewModel: home)
        case .sleep, .recovery, .insights, .coach:
            // R19: unbuilt tabs, listed in ROADMAP.md.
            NoctisComingSoonView(title: tab.title, systemImage: tab.systemImage)
        }
    }
}
