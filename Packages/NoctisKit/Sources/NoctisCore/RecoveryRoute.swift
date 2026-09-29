import Foundation
import RecoveryKit

/// Screens pushed inside the Recovery tab's navigation stack.
public nonisolated enum RecoveryRoute: Sendable, Hashable {
    /// One factor's detail over `range` nights.
    case factor(RecoveryFactorKind, range: RecoveryFactorRange = .fortnight)
}
