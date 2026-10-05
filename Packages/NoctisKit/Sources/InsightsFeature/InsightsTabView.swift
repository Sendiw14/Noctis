import DesignSystem
import HomeFeature
import InsightsKit
import NoctisCore
import ReviewKit
import SwiftUI

/// The Insights tab: its own navigation stack, with the Insights screen at
/// its root and an insight's page, or History, pushed over it. A card zooms
/// into its page.
public struct InsightsTabView: View {
    let viewModel: InsightsViewModel
    @Environment(AppModel.self) private var appModel
    @Namespace private var zoom

    public init(viewModel: InsightsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        @Bindable var model = appModel
        NavigationStack(path: $model.insightsPath) {
            InsightsScreen(
                viewModel: viewModel,
                zoom: zoom,
                openInsight: { id in
                    viewModel.markSeen(id: id)
                    appModel.insightsPath.append(.insight(id: id))
                },
                openHistory: {
                    viewModel.openHistory()
                    appModel.insightsPath.append(.history)
                },
                openReviews: { appModel.insightsPath.append(.reviews) }
            )
            .navigationDestination(for: InsightsRoute.self) { route in
                switch route {
                case .insight(let id):
                    InsightDetailScreen(viewModel: viewModel, id: id)
                        .navigationTransition(.zoom(sourceID: id, in: zoom))
                case .historyInsight(let id):
                    InsightDetailScreen(viewModel: viewModel, id: id)
                        .navigationTransition(.zoom(sourceID: "history-\(id)", in: zoom))
                case .history:
                    InsightHistoryScreen(viewModel: viewModel, zoom: zoom) { id in
                        viewModel.markSeen(id: id)
                        appModel.insightsPath.append(.historyInsight(id: id))
                    }
                case .reviews:
                    ReviewsListScreen()
                case .review(let kind, let id):
                    ReviewRouteScreen(model: viewModel.reviewRoute(kind: kind, id: id))
                }
            }
        }
    }
}
