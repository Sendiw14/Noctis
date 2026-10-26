import Foundation
import SleepKit

// How a review is kept (APP_RULES.md R39): the library of records on this device, where each stands with the person, and the rules for when one is made, made again
// and left alone. Pure values: `ReviewStore` persists them.

/// Where a review stands with the person. There is no count and no badge anywhere: this only lets a card stop appearing once the review has been opened.
public nonisolated enum ReviewState: String, Sendable, Equatable, Codable {
    case new
    case seen
}

/// A record as it is kept: the derived values, where it stands, and when it was first made (which is when its 24 hours begin).
public nonisolated struct StoredReview: Sendable, Equatable, Codable, Identifiable {
    public let record: ReviewRecord
    public var state: ReviewState
    public let firstGeneratedAt: Date

    public var id: ReviewID { record.id }

    public init(record: ReviewRecord, state: ReviewState = .new, firstGeneratedAt: Date) {
        self.record = record
        self.state = state
        self.firstGeneratedAt = firstGeneratedAt
    }
}

/// What to do about a period when someone asks for its review.
public nonisolated enum ReviewAction: Sendable, Equatable {
    /// Nothing is kept for it yet: make it.
    case generate
    /// It is kept and still inside its 24 hours: make it again, and keep the new one only if a night arrived or left in the meantime.
    case refresh
    /// It is kept and frozen: show it as it is, whatever Health says now.
    case reuse
}

public nonisolated enum ReviewLifecycle {
    /// A review is made the first time its period is asked for after the period ended. For 24 hours after that it is made again when asked for, so a night Apple
    /// Health delivered late is counted; after that it is frozen, so what was read once stays what was read.
    public static let refreshWindow: TimeInterval = 24 * 3600

    public static func action(stored: StoredReview?, now: Date) -> ReviewAction {
        guard let stored else { return .generate }
        return now.timeIntervalSince(stored.firstGeneratedAt) < refreshWindow ? .refresh : .reuse
    }

    /// What is kept after a refresh: the new record only if it counted a different number of nights (or could not be made again, the old one stays), the state and the
    /// first-made time always the old ones.
    public static func refreshed(_ stored: StoredReview, with result: ReviewResult) -> StoredReview {
        guard case .record(let fresh) = result, fresh.nightsRecorded != stored.record.nightsRecorded else { return stored }
        return StoredReview(record: fresh, state: stored.state, firstGeneratedAt: stored.firstGeneratedAt)
    }
}

/// Every review kept on this device. Derived values only: no raw sample, no source or device name, nothing from the Journal or Coach.
public nonisolated struct ReviewLibrary: Sendable, Equatable, Codable {
    public static let schemaVersion = 1
    /// How many of each kind are kept: two years of weeks, three of months. The oldest go first.
    public static let keptWeekly = 104
    public static let keptMonthly = 36

    public private(set) var schema: Int
    public private(set) var entries: [ReviewID: StoredReview]

    public init(entries: [ReviewID: StoredReview] = [:]) {
        schema = Self.schemaVersion
        self.entries = entries
    }

    private enum CodingKeys: String, CodingKey { case schema, reviews }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(Int.self, forKey: .schema)
        let list = try container.decode([StoredReview].self, forKey: .reviews)
        entries = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// A list, not a dictionary keyed by a type JSON cannot key an object by: the file reads the same in any tool.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(all, forKey: .reviews)
    }

    public subscript(id: ReviewID) -> StoredReview? { entries[id] }

    /// Newest first (ties cannot happen: an id is a kind and a last morning).
    public var all: [StoredReview] {
        entries.values.sorted { $0.record.lastMorning != $1.record.lastMorning ? $0.record.lastMorning > $1.record.lastMorning : $0.id > $1.id }
    }

    public func all(of kind: ReviewKind) -> [StoredReview] { all.filter { $0.record.kind == kind } }

    public func latest(of kind: ReviewKind) -> StoredReview? { all(of: kind).first }

    public mutating func put(_ stored: StoredReview) {
        entries[stored.id] = stored
        prune()
    }

    public mutating func markSeen(_ id: ReviewID) {
        entries[id]?.state = .seen
    }

    /// Records of another version, or whose dates are not the dates their id names, are dropped, never half-read: they are made again from Health when asked for.
    public mutating func dropUnreadable() {
        entries = entries.filter {
            $0.value.record.version == ReviewRecord.currentVersion && $0.key == $0.value.record.id && ReviewPeriod.period(for: $0.key) == $0.value.record.period
        }
    }

    private mutating func prune() {
        for (kind, limit) in [(ReviewKind.weekly, Self.keptWeekly), (.monthly, Self.keptMonthly)] {
            for extra in all(of: kind).dropFirst(limit) { entries[extra.id] = nil }
        }
    }
}
