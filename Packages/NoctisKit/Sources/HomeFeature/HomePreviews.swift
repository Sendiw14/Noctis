#if DEBUG
import DesignSystem
import HealthProviding
import NoctisCore
import SwiftData
import SwiftUI

/// Home on the DEBUG mock, one preview per state, each built through the
/// real pipeline: mock provider → HomeRepository → HomeViewModel.
enum HomePreview {
    static func tab(
        _ scenario: MockScenario,
        authorized: Bool = true,
        fails: Bool = false,
        latency: Duration = .zero,
        mode: HomeMode? = .day
    ) -> some View {
        let provider = MockHealthKitProvider(scenario: scenario, startAuthorized: authorized, failsQueries: fails, latency: latency)
        let model = makeModel(provider)
        let defaults = UserDefaults(suiteName: "noctis.preview") ?? .standard
        defaults.removeObject(forKey: HomeIntroGate.defaultsKey)
        let viewModel = HomeViewModel(
            repository: HomeRepository(provider: provider),
            profile: { model.profile },
            connectHealth: { await model.requestHealthAuthorization() },
            introGate: HomeIntroGate(defaults: defaults),
            modeOverride: mode
        )
        return HomeTabView(viewModel: viewModel, recoveryScreen: { _ in AnyView(EmptyView()) }, recoveryFactor: { _, _ in AnyView(EmptyView()) }).environment(model)
    }

    private static func makeModel(_ provider: MockHealthKitProvider) -> AppModel {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: UserProfileRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        } catch {
            fatalError("Preview store: \(error)")
        }
        return AppModel(healthProvider: provider, profileStore: ProfileStore(context: ModelContext(container)))
    }
}

#Preview("Full") { HomePreview.tab(.full) }
#Preview("Full · Dark") { HomePreview.tab(.full).preferredColorScheme(.dark) }
#Preview("Evening") { HomePreview.tab(.full, mode: .evening) }
#Preview("Evening · Dark") { HomePreview.tab(.full, mode: .evening).preferredColorScheme(.dark) }
#Preview("Sleep only") { HomePreview.tab(.sleepOnly) }
#Preview("Learning") { HomePreview.tab(.learning) }
#Preview("Gap") { HomePreview.tab(.gap) }
#Preview("Stale") { HomePreview.tab(.stale) }
#Preview("Empty") { HomePreview.tab(.empty) }
#Preview("No permission") { HomePreview.tab(.full, authorized: false) }
#Preview("Loading") { HomePreview.tab(.full, latency: .seconds(3600)) }
#Preview("Error") { HomePreview.tab(.full, fails: true) }
#endif
