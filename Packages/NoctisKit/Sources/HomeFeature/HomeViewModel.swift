import Foundation
import NoctisCore
import Observation

/// Home's view model: holds the latest `HomeSnapshot` and decides when to
/// rebuild it — on appear, on pull-to-refresh, and whenever Health data
/// changes (`HKObserverQuery` via `HomeRepository.changes()`). Views read
/// `snapshot` and nothing else (APP_RULES.md R20).
@Observable
public final class HomeViewModel {
    public private(set) var snapshot: HomeSnapshot?
    public private(set) var isRefreshing = false

    private let repository: HomeRepository
    private let profile: () -> UserProfileSnapshot
    private var observation: Task<Void, Never>?

    #if DEBUG
    /// DEBUG: print every new snapshot (`-noctisLogHomeSnapshot`).
    public var debugLogsSnapshots = false
    #endif

    public init(repository: HomeRepository, profile: @escaping () -> UserProfileSnapshot) {
        self.repository = repository
        self.profile = profile
    }

    /// Shows the cached snapshot at once, starts watching Health for
    /// changes (once), then rebuilds.
    public func onAppear() async {
        if snapshot == nil {
            snapshot = await repository.cachedSnapshot
        }
        startObserving()
        await refresh()
    }

    /// Pull-to-refresh, and every Health change.
    public func refresh() async {
        isRefreshing = true
        snapshot = await repository.refresh(profile: profile())
        isRefreshing = false
        #if DEBUG
        if debugLogsSnapshots, let snapshot { print(snapshot.debugSummary) }
        #endif
    }

    private func startObserving() {
        guard observation == nil else { return }
        observation = Task { [weak self, repository] in
            for await _ in await repository.changes() {
                guard let self else { return }
                await self.refresh()
            }
        }
    }

    /// Stops watching Health (tests and teardown).
    public func stopObserving() {
        observation?.cancel()
        observation = nil
    }
}
