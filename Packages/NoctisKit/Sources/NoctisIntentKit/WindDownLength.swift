import AppIntents
import Foundation

/// The lengths a wind-down can have: 10, 20 or 30 minutes (a test holds this to `WindDownClock.options`).
public enum WindDownLength: String, AppEnum, CaseIterable, Sendable {
    case tenMinutes
    case twentyMinutes
    case thirtyMinutes

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Length")

    public static let caseDisplayRepresentations: [WindDownLength: DisplayRepresentation] = [
        .tenMinutes: "10 minutes", .twentyMinutes: "20 minutes", .thirtyMinutes: "30 minutes",
    ]

    public var minutes: Int {
        switch self {
        case .tenMinutes: 10
        case .twentyMinutes: 20
        case .thirtyMinutes: 30
        }
    }
}
