import DesignSystem
import HomeFeature
import InsightsKit
import NoctisCore
import SwiftUI

/// The Insights tab: its own navigation stack, with the Insights screen at
/// its root and an insight's page, or History, pushed over it.
public struct InsightsTabView: View {
    let viewModel: InsightsViewModel
    @Environment(AppModel.self) private var appModel

    public init(viewModel: InsightsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        @Bindable var model = appModel
        NavigationStack(path: $model.insightsPath) {
            InsightsScreen(
                viewModel: viewModel,
                openInsight: { id in
                    viewModel.markSeen(id: id)
                    appModel.insightsPath.append(.insight(id: id))
                },
                openHistory: { appModel.insightsPath.append(.history) }
            )
            .navigationDestination(for: InsightsRoute.self) { route in
                switch route {
                case .insight:
                    // R19: built in the next part, listed in ROADMAP.md.
                    NoctisTabPlaceholder(.insights, title: "Insight", presentation: .pushed)
                case .history:
                    NoctisTabPlaceholder(.insights, title: "History", presentation: .pushed)
                }
            }
        }
    }
}
