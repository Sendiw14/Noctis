import Foundation
import SleepKit

/// Where a stored insight stands with the person.
public enum InsightState: String, Sendable, Codable, Hashable {
    /// Generated, not yet opened.
    case new
    /// Opened.
    case seen
    /// "Not useful": kept in History, muted, never featured or counted.
    case dismissed
}

/// One insight as stored: derived numbers and where it stands. The words are
/// written from the numbers each time, the same way, so they never change
/// between opens.
public struct StoredInsight: Sendable, Equatable, Codable, Identifiable {
    public let record: InsightRecord
    public var state: InsightState

    public var id: String { record.id }

    public init(record: InsightRecord, state: InsightState = .new) {
        self.record = record
        self.state = state
    }
}

/// Every insight ever generated for the person, with their history of
/// featured, dismissed and hidden. A pure value: `InsightStore` persists it
/// and every screen reads it, so the tab, History and Home can't disagree.
public struct InsightLibrary: Sendable, Equatable, Codable {
    public static let schemaVersion = 1
    /// Insights older than this many nights are dropped from the file.
    public static let keptNights = 400
    /// "New this week" and Recent look back this many nights.
    public static let recentNights = 14
    public static let weekNights = 7

    public private(set) var schema: Int
    /// By id.
    public private(set) var entries: [String: StoredInsight]
    public private(set) var history: InsightHistory

    public init(entries: [String: StoredInsight] = [:], history: InsightHistory = InsightHistory()) {
        schema = Self.schemaVersion
        self.entries = entries
        self.history = history
    }

    // MARK: Reading

    /// Everything not hidden by the person, newest night first (ties by id).
    public var visible: [StoredInsight] {
        entries.values
            .filter { !history.isHidden($0.record.type) }
            .sorted { $0.record.night != $1.record.night ? $0.record.night > $1.record.night : $0.id < $1.id }
    }

    public func entry(id: String) -> StoredInsight? {
        entries[id].flatMap { history.isHidden($0.record.type) ? nil : $0 }
    }

    /// Insights that count toward "N new this week": new, not hidden, from
    /// the last week.
    public func newThisWeek(on night: SleepNightKey) -> [StoredInsight] {
        visible.filter { $0.state == .new && night.days(from: $0.record.night) < Self.weekNights && !$0.record.type.isInformational }
    }

    /// The insight to feature for `night`: the top-ranked one about that
    /// night the fatigue rules allow (or the one already chosen for it).
    /// Does not record anything (`recordFeatured`).
    public func featured(on night: SleepNightKey) -> InsightRecord? {
        let candidates = entries.values.filter { $0.record.night == night }.map(\.record)
        // The stored record itself, so it reads the same however often it is asked.
        return history.featured(from: InsightRanking.ranked(candidates, on: night, history: history), on: night).flatMap { entries[$0.id]?.record }
    }

    /// The Recent list: the latest insight of each type from the last
    /// `recentNights` nights, best first. Dismissed and hidden ones are out.
    public func recent(on night: SleepNightKey) -> [StoredInsight] {
        var latest: [String: StoredInsight] = [:]
        for entry in visible where entry.state != .dismissed && night.days(from: entry.record.night) < Self.recentNights && entry.record.night <= night {
            if latest[entry.record.kindKey] == nil { latest[entry.record.kindKey] = entry }
        }
        let records = InsightRanking.ranked(latest.values.map(\.record), on: night, history: history)
        let order = Dictionary(uniqueKeysWithValues: records.enumerated().map { ($1.id, $0) })
        // Newest night first, then the ranking within a night.
        return latest.values.sorted {
            $0.record.night != $1.record.night ? $0.record.night > $1.record.night : (order[$0.id] ?? 0) < (order[$1.id] ?? 0)
        }
    }

    // MARK: Writing

    /// Adds the insights not stored yet. One per slot (type, night and
    /// stage): the first one generated for a slot is the one that stays, so
    /// an insight's numbers never change after it's been made. Hidden types
    /// aren't stored at all. Returns the ids added.
    @discardableResult
    public mutating func merge(_ generated: [InsightRecord]) -> [String] {
        let slots = Set(entries.values.map(\.record.slot))
        var known = slots
        var added: [String] = []
        for record in generated.sorted(by: { $0.id < $1.id }) {
            guard !history.isHidden(record.type), !history.isDismissed(id: record.id), known.insert(record.slot).inserted else { continue }
            entries[record.id] = StoredInsight(record: record)
            added.append(record.id)
        }
        if let newest = entries.values.map(\.record.night).max() {
            entries = entries.filter { newest.days(from: $0.value.record.night) < Self.keptNights }
        }
        return added
    }

    public mutating func markSeen(id: String) {
        guard var entry = entries[id], entry.state == .new else { return }
        entry.state = .seen
        entries[id] = entry
    }

    /// "Not useful": muted, and never featured again for this evidence.
    public mutating func dismiss(id: String) {
        guard var entry = entries[id] else { return }
        entry.state = .dismissed
        entries[id] = entry
        history.dismiss(entry.record)
    }

    /// "Hide insights like this": the type disappears everywhere.
    public mutating func hide(_ type: InsightType) {
        history.hide(type: type)
    }

    /// The night's featured insight, chosen once and remembered so Home and
    /// the tab show the same one.
    @discardableResult
    public mutating func chooseFeatured(on night: SleepNightKey) -> InsightRecord? {
        guard let record = featured(on: night) else { return nil }
        if history.featuredByNight[night.description] != record.id { history.recordFeatured(record, on: night) }
        return record
    }
}
