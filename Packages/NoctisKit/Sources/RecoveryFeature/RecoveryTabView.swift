import DesignSystem
import HomeFeature
import NoctisCore
import RecoveryKit
import SwiftUI

/// The Recovery tab: its own navigation stack, with the Recovery screen at
/// its root and a factor's detail pushed over it.
public struct RecoveryTabView: View {
    let viewModel: RecoveryViewModel
    @Environment(AppModel.self) private var appModel

    public init(viewModel: RecoveryViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        @Bindable var model = appModel
        NavigationStack(path: $model.recoveryPath) {
            RecoveryTabRoot(viewModel: viewModel) { kind in
                appModel.recoveryPath.append(.factor(kind, range: .fortnight))
            }
            .navigationDestination(for: RecoveryRoute.self) { route in
                switch route {
                case .factor(let kind, let range):
                    RecoveryFactorScreen(viewModel: viewModel, kind: kind, range: range)
                }
            }
        }
    }
}

/// The root screen, scrolling to the top on a second press of the tab.
private struct RecoveryTabRoot: View {
    let viewModel: RecoveryViewModel
    let openFactor: (RecoveryFactorKind) -> Void
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var retaps = 0

    var body: some View {
        RecoveryScreen(viewModel: viewModel, presentation: .tab, openFactor: openFactor)
            .id(retaps)
            .onChange(of: appModel.tabRetap) { _, retap in
                guard retap?.tab == .recovery else { return }
                if appModel.recoveryPath.isEmpty {
                    // Back to the top: a fresh scroll position.
                    withAnimation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion)) { retaps += 1 }
                } else {
                    appModel.recoveryPath = []
                }
            }
    }
}

/// A factor's detail: arrives with its own commit.
struct RecoveryFactorScreen: View {
    let viewModel: RecoveryViewModel
    let kind: RecoveryFactorKind
    let range: RecoveryFactorRange

    var body: some View {
        DormantTextView(title: "\(HomeScreenBuilder.shortName(kind)) detail is on its way", detail: nil)
            .navigationTitle(HomeScreenBuilder.shortName(kind))
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// The Recovery screen pushed over Home when the ring is tapped (with the
/// zoom), and a factor's detail pushed over Home from a capsule: the same
/// components as the tab, in Home's stack.
public struct RecoveryPushedScreen: View {
    let viewModel: RecoveryViewModel
    let focus: RecoveryFactorKind?
    @Environment(AppModel.self) private var appModel

    public init(viewModel: RecoveryViewModel, focus: RecoveryFactorKind?) {
        self.viewModel = viewModel
        self.focus = focus
    }

    public var body: some View {
        RecoveryScreen(viewModel: viewModel, presentation: .pushed, focus: focus) { kind in
            appModel.homePath.append(.recoveryFactor(kind, range: .fortnight))
        }
        // Home's ring opens Today.
        .onAppear {
            if viewModel.selection != RecoverySelection() { viewModel.open(segment: .today) }
        }
    }
}

public struct RecoveryPushedFactorScreen: View {
    let viewModel: RecoveryViewModel
    let kind: RecoveryFactorKind
    let range: RecoveryFactorRange

    public init(viewModel: RecoveryViewModel, kind: RecoveryFactorKind, range: RecoveryFactorRange) {
        self.viewModel = viewModel
        self.kind = kind
        self.range = range
    }

    public var body: some View {
        RecoveryFactorScreen(viewModel: viewModel, kind: kind, range: range)
    }
}
