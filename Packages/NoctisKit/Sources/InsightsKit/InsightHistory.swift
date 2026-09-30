import Foundation
import SleepKit

/// What the person has seen and said about insights, for fatigue. Stored by
/// `InsightHistoryStore` (v1) and inside `InsightLibrary` (v2).
///
/// v1 (kinds, `pick`): the last insight shown, the nights they dismissed one
/// ("Not useful") and the kinds they hid.
///
/// v2 (types, `mayFeature`), the rules the featured insight follows:
/// - A hidden type is never featured, listed or counted again.
/// - A dismissed insight never returns for the same evidence (its id).
/// - The same type isn't featured again within `fatigueNights` nights unless
///   its evidence changed by `fatigueChange` or more.
/// - Once a night's featured insight is dismissed, nothing replaces it that
///   night; the next night starts fresh.
public struct InsightHistory: Sendable, Equatable, Codable {
    public struct Shown: Sendable, Equatable, Codable {
        public let kind: InsightKind
        public let night: SleepNightKey

        public init(kind: InsightKind, night: SleepNightKey) {
            self.kind = kind
            self.night = night
        }
    }

    /// The last time a type was featured: when, on what evidence, how big.
    public struct Featured: Sendable, Equatable, Codable {
        public let night: SleepNightKey
        public let id: String
        public let magnitude: Double

        public init(night: SleepNightKey, id: String, magnitude: Double) {
            self.night = night
            self.id = id
            self.magnitude = magnitude
        }
    }

    /// The same type isn't featured again within this many nights...
    public static let fatigueNights = 3
    /// ...unless its evidence changed by at least this fraction.
    public static let fatigueChange = 0.20
    static let maxDismissals = 30
    static let maxDismissedIDs = 400
    static let maxFeaturedNights = 120

    // v1
    public private(set) var lastShown: Shown?
    /// Each "Not useful", oldest first.
    public private(set) var dismissals: [Shown]
    public private(set) var hiddenKinds: Set<InsightKind>
    // v2
    /// The last time each type was featured, by `InsightType.rawValue`.
    public private(set) var featuredTypes: [String: Featured]
    /// The insight featured on each night, by the night's "yyyy-MM-dd", so
    /// the night's featured insight never changes once chosen.
    public private(set) var featuredByNight: [String: String]
    /// Every dismissed insight, oldest first.
    public private(set) var dismissedIDs: [String]
    public private(set) var hiddenTypes: Set<InsightType>

    public init(
        lastShown: Shown? = nil, dismissals: [Shown] = [], hiddenKinds: Set<InsightKind> = [],
        featuredTypes: [String: Featured] = [:], featuredByNight: [String: String] = [:],
        dismissedIDs: [String] = [], hiddenTypes: Set<InsightType> = []
    ) {
        self.lastShown = lastShown
        self.dismissals = dismissals
        self.hiddenKinds = hiddenKinds
        self.featuredTypes = featuredTypes
        self.featuredByNight = featuredByNight
        self.dismissedIDs = dismissedIDs
        self.hiddenTypes = hiddenTypes
    }

    // A file written before v2 has none of the v2 keys.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastShown = try container.decodeIfPresent(Shown.self, forKey: .lastShown)
        dismissals = try container.decodeIfPresent([Shown].self, forKey: .dismissals) ?? []
        hiddenKinds = try container.decodeIfPresent(Set<InsightKind>.self, forKey: .hiddenKinds) ?? []
        featuredTypes = try container.decodeIfPresent([String: Featured].self, forKey: .featuredTypes) ?? [:]
        featuredByNight = try container.decodeIfPresent([String: String].self, forKey: .featuredByNight) ?? [:]
        dismissedIDs = try container.decodeIfPresent([String].self, forKey: .dismissedIDs) ?? []
        hiddenTypes = try container.decodeIfPresent(Set<InsightType>.self, forKey: .hiddenTypes) ?? []
    }

    // MARK: v1

    /// The first of `candidates` (best first, all about the same night)
    /// these rules allow, or nil.
    public func pick(from candidates: [Insight]) -> Insight? {
        guard let night = candidates.first?.evidence.night else { return nil }
        if dismissals.contains(where: { $0.night == night }) { return nil }
        return candidates.first { insight in
            guard !hiddenKinds.contains(insight.kind), !hiddenTypes.contains(insight.kind.type) else { return false }
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
        hiddenTypes.insert(kind.type)
    }

    // MARK: v2

    public func isHidden(_ type: InsightType) -> Bool { hiddenTypes.contains(type) }

    public func isDismissed(id: String) -> Bool { dismissedIDs.contains(id) }

    public func lastFeatured(_ type: InsightType) -> Featured? { featuredTypes[type.rawValue] }

    /// Whether `record` may be featured on `night`: not hidden, not
    /// dismissed and, when its type was featured within the last
    /// `fatigueNights` nights, only with evidence at least `fatigueChange`
    /// different.
    public func mayFeature(_ record: InsightRecord, on night: SleepNightKey) -> Bool {
        guard !isHidden(record.type), !isDismissed(id: record.id) else { return false }
        guard let last = lastFeatured(record.type), last.id != record.id else { return true }
        guard night.days(from: last.night) < Self.fatigueNights else { return true }
        return Self.changed(from: last.magnitude, to: record.magnitude)
    }

    /// Whether `new` is at least `fatigueChange` away from `old`, as a share
    /// of `old` (any change from zero counts). The comparison is on tenths
    /// of a percent, so 20.0% counts as 20%.
    static func changed(from old: Double, to new: Double) -> Bool {
        guard old != 0 else { return new != 0 }
        return (abs(new - old) / abs(old) * 1000).rounded() >= fatigueChange * 1000
    }

    /// The insight to feature on `night`, best first from `ranked` (which is
    /// about that night): the one already chosen for the night if it still
    /// stands, otherwise the first the rules allow. A night whose featured
    /// insight was dismissed or hidden has none.
    public func featured(from ranked: [InsightRecord], on night: SleepNightKey) -> InsightRecord? {
        if let chosen = featuredByNight[night.description] {
            guard let record = ranked.first(where: { $0.id == chosen }), !isHidden(record.type), !isDismissed(id: record.id) else { return nil }
            return record
        }
        return ranked.first { mayFeature($0, on: night) }
    }

    /// Notes that `record` is featured on `night`.
    public mutating func recordFeatured(_ record: InsightRecord, on night: SleepNightKey) {
        featuredByNight[night.description] = record.id
        featuredTypes[record.type.rawValue] = Featured(night: night, id: record.id, magnitude: record.magnitude)
        if featuredByNight.count > Self.maxFeaturedNights {
            for key in featuredByNight.keys.sorted().dropLast(Self.maxFeaturedNights) { featuredByNight[key] = nil }
        }
    }

    /// "Not useful": this evidence never returns.
    public mutating func dismiss(_ record: InsightRecord) {
        guard !dismissedIDs.contains(record.id) else { return }
        dismissedIDs.append(record.id)
        if dismissedIDs.count > Self.maxDismissedIDs { dismissedIDs.removeFirst(dismissedIDs.count - Self.maxDismissedIDs) }
    }

    /// "Hide insights like this".
    public mutating func hide(type: InsightType) {
        hiddenTypes.insert(type)
    }

    /// Undoes a hide.
    public mutating func unhide(_ type: InsightType) {
        hiddenTypes.remove(type)
    }
}
