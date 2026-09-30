import Foundation
import SleepKit

/// What the person has seen and said about insights, for fatigue, kept
/// inside `InsightLibrary`. The rules, as `mayFeature` and `featured` apply
/// them:
/// - A hidden type is never featured, listed or counted again.
/// - A dismissed insight never returns for the same evidence (its id).
/// - The same type isn't featured again within `fatigueNights` nights unless
///   its evidence changed by `fatigueChange` or more.
/// - Once a night's featured insight is dismissed, nothing replaces it that
///   night; the next night starts fresh.
public struct InsightHistory: Sendable, Equatable, Codable {
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
    static let maxDismissedIDs = 400
    static let maxFeaturedNights = 120

    /// The last time each type was featured, by `InsightType.rawValue`.
    public private(set) var featuredTypes: [String: Featured]
    /// The insight featured on each night, by the night's "yyyy-MM-dd", so
    /// the night's featured insight never changes once chosen.
    public private(set) var featuredByNight: [String: String]
    /// Every dismissed insight, oldest first.
    public private(set) var dismissedIDs: [String]
    public private(set) var hiddenTypes: Set<InsightType>

    public init(
        featuredTypes: [String: Featured] = [:], featuredByNight: [String: String] = [:],
        dismissedIDs: [String] = [], hiddenTypes: Set<InsightType> = []
    ) {
        self.featuredTypes = featuredTypes
        self.featuredByNight = featuredByNight
        self.dismissedIDs = dismissedIDs
        self.hiddenTypes = hiddenTypes
    }

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
    /// insight was dismissed has none (nothing steps in for it); one whose
    /// featured kind was hidden moves on to the next.
    public func featured(from ranked: [InsightRecord], on night: SleepNightKey) -> InsightRecord? {
        if let chosen = featuredByNight[night.description] {
            if isDismissed(id: chosen) { return nil }
            if let record = ranked.first(where: { $0.id == chosen }), !isHidden(record.type) { return record }
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
