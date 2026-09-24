import Foundation
import SleepKit

/// What the person has seen and said about insights, for fatigue: the
/// last insight shown, the nights they dismissed one ("Not useful"), and
/// the kinds they hid ("Hide insights like this"). Stored by
/// `InsightHistoryStore`; applied by `InsightEngine`.
///
/// Rules (`pick`):
/// - A hidden kind is never shown again.
/// - The kind shown for the night before isn't shown two nights in a row;
///   the next candidate takes its place. The same night keeps its insight.
/// - Once an insight is dismissed, that night shows no insight at all (the
///   card collapses and the gap closes); the next night starts fresh.
public struct InsightHistory: Sendable, Equatable, Codable {
    public struct Shown: Sendable, Equatable, Codable {
        public let kind: InsightKind
        public let night: SleepNightKey

        public init(kind: InsightKind, night: SleepNightKey) {
            self.kind = kind
            self.night = night
        }
    }

    public private(set) var lastShown: Shown?
    /// Each "Not useful", oldest first.
    public private(set) var dismissals: [Shown]
    public private(set) var hiddenKinds: Set<InsightKind>

    public init(lastShown: Shown? = nil, dismissals: [Shown] = [], hiddenKinds: Set<InsightKind> = []) {
        self.lastShown = lastShown
        self.dismissals = dismissals
        self.hiddenKinds = hiddenKinds
    }

    /// The first of `candidates` (best first, all about the same night)
    /// these rules allow, or nil.
    public func pick(from candidates: [Insight]) -> Insight? {
        guard let night = candidates.first?.evidence.night else { return nil }
        if dismissals.contains(where: { $0.night == night }) { return nil }
        return candidates.first { insight in
            guard !hiddenKinds.contains(insight.kind) else { return false }
            if let lastShown, lastShown.night == night.adding(days: -1), lastShown.kind == insight.kind { return false }
            return true
        }
    }

    public mutating func recordShown(_ insight: Insight) {
        lastShown = Shown(kind: insight.kind, night: insight.evidence.night)
    }

    /// "Not useful": gone for the rest of this night.
    public mutating func recordDismissal(_ insight: Insight) {
        dismissals.append(Shown(kind: insight.kind, night: insight.evidence.night))
        // Only the nights still in play matter; keep the file small.
        if dismissals.count > Self.maxDismissals { dismissals.removeFirst(dismissals.count - Self.maxDismissals) }
    }

    /// "Hide insights like this".
    public mutating func hide(_ kind: InsightKind) {
        hiddenKinds.insert(kind)
    }

    static let maxDismissals = 30
}
