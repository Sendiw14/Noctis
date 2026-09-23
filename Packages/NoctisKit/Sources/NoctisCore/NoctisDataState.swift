import Foundation

/// Every screen renders one of these instead of assuming happy-path data.
public enum NoctisDataState: Sendable, Equatable {
    case loading
    case ready
    case noData
    case partial(String)
    case error(String)
    case healthKitUnavailable
    case permissionRequired
}
