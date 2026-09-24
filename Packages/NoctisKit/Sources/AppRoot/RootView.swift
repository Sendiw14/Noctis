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

/// The main app's tab bar (R7): a system `TabView` on the iOS 18 `Tab`
/// API, so iOS 26 draws it in Liquid Glass. Home is the default tab.
struct RootTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(HomeViewModel.self) private var home

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    destination(for: tab)
                }
            }
        }
        .tint(NoctisAppColor.ink)
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
