import DesignSystem
import NoctisCore
import SwiftUI

/// The Home tab. Home's screen isn't built yet (ROADMAP.md), so it shows
/// "Coming soon" — but it already drives `HomeViewModel`'s refresh
/// triggers: on appear and on pull-to-refresh.
public struct HomeTabView: View {
    private let viewModel: HomeViewModel

    public init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NoctisComingSoonView(title: AppTab.home.title, systemImage: AppTab.home.systemImage)
            .refreshable { await viewModel.refresh() }
            .task { await viewModel.onAppear() }
    }
}
