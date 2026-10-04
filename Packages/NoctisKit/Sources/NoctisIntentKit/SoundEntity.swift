import AppIntents
import Foundation
import SoundKit

/// A sleep sound, for Siri and Shortcuts. Made from `SoundKind.allCases`, the one list of the sounds NOCTIS ships (R31), so there is
/// no second list to forget: a sound added there is a sound here.
public struct SoundEntity: AppEntity, Identifiable, Hashable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sleep sound")
    public static let defaultQuery = SoundEntityQuery()

    public var id: String

    public init(_ kind: SoundKind) {
        id = kind.rawValue
    }

    public init(id: String) {
        self.id = id
    }

    /// The sound, if the id is one NOCTIS still has.
    public var kind: SoundKind? { SoundKind(rawValue: id) }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(kind?.title ?? id)")
    }
}

public struct SoundEntityQuery: EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [SoundEntity] {
        identifiers.compactMap { SoundKind(rawValue: $0).map(SoundEntity.init) }
    }

    public func suggestedEntities() async throws -> [SoundEntity] {
        SoundKind.allCases.map(SoundEntity.init)
    }

    /// "Rain", "rain sounds", "brown": by the sound's name.
    public func entities(matching string: String) async throws -> [SoundEntity] {
        let needle = string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return SoundKind.allCases.map(SoundEntity.init) }
        return SoundKind.allCases.filter { kind in
            let title = kind.title.lowercased()
            return title.contains(needle) || needle.contains(kind.rawValue) || needle.contains(title)
        }.map(SoundEntity.init)
    }
}
