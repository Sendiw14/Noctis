import Foundation
import InsightsKit

/// Keeps `InsightHistory` (insight fatigue) across launches in
/// UserDefaults under `noctis.`, so `-noctisResetState` clears it. With no
/// defaults it lives in memory only (tests, previews).
public nonisolated final class InsightHistoryStore: NoctisErasable, @unchecked Sendable {
    public static let defaultsKey = "noctis.insights.history"

    private let defaults: UserDefaults?
    private let lock = NSLock()
    private var cached: InsightHistory

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        let stored = defaults?.data(forKey: Self.defaultsKey).flatMap { try? JSONDecoder().decode(InsightHistory.self, from: $0) }
        cached = stored ?? InsightHistory()
    }

    public var history: InsightHistory {
        lock.withLock { cached }
    }

    public var erasableName: String { "Insight history" }

    /// Forgets which insights were shown, dismissed or hidden.
    public func erase() {
        lock.withLock {
            cached = InsightHistory()
            defaults?.removeObject(forKey: Self.defaultsKey)
        }
    }

    public func update(_ change: (inout InsightHistory) -> Void) {
        lock.withLock {
            var history = cached
            change(&history)
            guard history != cached else { return }
            cached = history
            if let defaults, let data = try? JSONEncoder().encode(history) {
                defaults.set(data, forKey: Self.defaultsKey)
            }
        }
    }
}
