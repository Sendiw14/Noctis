import Foundation

/// A store that keeps something derived from the person's data on this
/// device. Every such store registers here, so Data Management (ROADMAP.md)
/// can erase all of it with one call, and none can be forgotten.
public nonisolated protocol NoctisErasable: Sendable {
    /// For Data Management's list: "Home snapshot".
    var erasableName: String { get }
    /// Deletes everything the store keeps. Idempotent.
    func erase()
}

/// The stores Data Management erases.
public nonisolated final class NoctisDataRegistry: @unchecked Sendable {
    public static let shared = NoctisDataRegistry()

    private let lock = NSLock()
    private var registered: [any NoctisErasable] = []

    public init() {}

    public func register(_ store: any NoctisErasable) {
        lock.withLock { registered.append(store) }
    }

    /// Forgets every registration, before a restarted app registers its stores again.
    public func reset() {
        lock.withLock { registered = [] }
    }

    public var stores: [any NoctisErasable] {
        lock.withLock { registered }
    }

    /// Erases every registered store.
    public func eraseAll() {
        for store in stores { store.erase() }
    }
}
