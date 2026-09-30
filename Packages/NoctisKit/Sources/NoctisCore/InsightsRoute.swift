import Foundation
import InsightsKit

/// Screens pushed inside the Insights tab's navigation stack.
public nonisolated enum InsightsRoute: Sendable, Hashable {
    /// One insight's page.
    case insight(id: String)
    /// Every insight so far, newest first, filtered by the chips.
    case history
}
