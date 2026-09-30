import CoachKit
import DesignSystem
import NoctisCore
import SwiftUI

/// The Coach tab: its own navigation stack with the hub at its root and a
/// conversation pushed over it.
public struct CoachTabView: View {
    let viewModel: CoachViewModel
    @Environment(AppModel.self) private var appModel

    public init(viewModel: CoachViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        @Bindable var model = appModel
        @Bindable var coach = viewModel
        NavigationStack(path: $model.coachPath) {
            CoachScreen(
                viewModel: viewModel,
                ask: { question in
                    if viewModel.startConversation(asking: question) { open(.conversation) }
                },
                send: {
                    if viewModel.startConversation(asking: viewModel.draft) { open(.conversation) }
                }
            )
            .navigationDestination(for: CoachPage.self) { route in
                switch route {
                case .conversation:
                    CoachConversationScreen(viewModel: viewModel)
                case .history:
                    EmptyView()
                }
            }
        }
        .sheet(isPresented: $coach.showsPrivacy) { CoachPrivacySheet() }
        // A question handed over by a route (a button in Recovery, Sleep or an insight).
        .task { takeDestination() }
        .onChange(of: appModel.coachDestination) { _, destination in
            if destination != nil { takeDestination() }
        }
        .onChange(of: appModel.coachPath) { _, path in
            if path.isEmpty { viewModel.endConversation() }
        }
        // A second press of the Coach tab, inside a conversation: back to the hub.
        .onChange(of: appModel.tabRetap) { _, retap in
            guard retap?.tab == .coach, !appModel.coachPath.isEmpty else { return }
            appModel.coachPath = []
        }
    }

    private func open(_ route: CoachPage) {
        appModel.coachPath = [route]
    }

    private func takeDestination() {
        guard let destination = appModel.takeCoachDestination() else { return }
        if let question = destination.question, viewModel.startConversation(asking: question) {
            appModel.coachPath = [.conversation]
        }
    }
}
