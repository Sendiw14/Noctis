import Foundation
import InsightsKit
import ReviewKit

/// Screens pushed inside the Insights tab's navigation stack.
public nonisolated enum InsightsRoute: Sendable, Hashable {
    /// One insight's page, from the tab's cards.
    case insight(id: String)
    /// One insight's page, from History's rows (its own zoom source).
    case historyInsight(id: String)
    /// Every insight so far, newest first, filtered by the chips.
    case history
    /// Every review so far.
    case reviews
    /// One review's page: the one `id` names, or the latest of `kind`.
    case review(kind: ReviewKind, id: ReviewID?)
}
