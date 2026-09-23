import CoachFeature
import DesignSystem
import HomeFeature
import InsightsFeature
import NoctisCore
import OnboardingFeature
import RecoveryFeature
import SleepFeature
import SwiftUI

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
                MainTabView()
                    .transition(.opacity)
            } else {
                OnboardingFlowView {
                    withAnimation(NoctisMotion.adaptive(NoctisMotion.reveal, reduceMotion: reduceMotion)) {
                        showMain = true
                    }
                }
                .transition(.opacity)
            }
        }
        .task(id: showMain) {
            if showMain { await model.refresh() }
        }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    destination(for: tab)
                }
            }
        }
        .tint(NoctisColor.textPrimary)
    }

    @ViewBuilder
    private func destination(for tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .sleep: SleepView()
        case .recovery: RecoveryView()
        case .insights: InsightsView()
        case .coach: CoachView()
        }
    }
}
