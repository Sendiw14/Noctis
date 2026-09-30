import CoachKit
import DesignSystem
import Foundation
import NoctisCore

/// A fact's display ("6h 42m", "48 ms", "11:00 PM", "31%") as `NoctisMetric`
/// parts, so a number in Coach sets its unit the way every other number in the
/// app does (APP_RULES.md R4). The words a person hears are the fact's own.
public nonisolated enum CoachMetric {
    public static func value(display: String, spoken: String) -> NoctisMetricValue {
        var parts: [NoctisMetricValue.Part] = []
        var pendingSpace = false
        let characters = Array(display)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                pendingSpace = true
                index += 1
            } else if character.isNumber {
                var text = String(character)
                index += 1
                while index < characters.count {
                    let next = characters[index]
                    let joins = ":,.".contains(next) && index + 1 < characters.count && characters[index + 1].isNumber
                    guard next.isNumber || joins else { break }
                    text.append(next)
                    index += 1
                }
                // "6h 42m": a gap after a unit and before the next number.
                if pendingSpace, case .unit? = parts.last { parts.append(.space) }
                pendingSpace = false
                parts.append(.number(text))
            } else {
                var text = String(character)
                index += 1
                while index < characters.count, !characters[index].isNumber, !characters[index].isWhitespace {
                    text.append(characters[index])
                    index += 1
                }
                pendingSpace = false
                parts.append(.unit(text))
            }
        }
        return NoctisMetricValue(parts: parts, spoken: spoken)
    }

    public static func value(_ contributor: CoachContributor) -> NoctisMetricValue {
        value(display: contributor.value, spoken: contributor.spoken)
    }
}

/// The tile a contributor wears, by the fact it points at.
public nonisolated struct CoachContributorTile: Sendable, Equatable {
    public let symbol: String
    public let tile: CoachTile

    public static func of(factID: String) -> CoachContributorTile {
        switch true {
        case factID.hasPrefix("hrv."): CoachContributorTile(symbol: "waveform.path.ecg", tile: .lavender)
        case factID.hasPrefix("rhr."): CoachContributorTile(symbol: "heart.fill", tile: .apricot)
        case factID.hasPrefix("recovery."): CoachContributorTile(symbol: "heart", tile: .lavender)
        case factID.hasPrefix("sleep."), factID.hasPrefix("deep."), factID.hasPrefix("rem."): CoachContributorTile(symbol: "moon.zzz", tile: .sage)
        case factID.hasPrefix("bedtime."), factID.hasPrefix("wake."): CoachContributorTile(symbol: "bed.double", tile: .apricot)
        case factID.hasPrefix("week."): CoachContributorTile(symbol: "calendar", tile: .butter)
        case factID.hasPrefix("consistency."): CoachContributorTile(symbol: "repeat", tile: .butter)
        case factID.hasPrefix("history."): CoachContributorTile(symbol: "moon.stars", tile: .sage)
        default: CoachContributorTile(symbol: "lightbulb", tile: .butter)
        }
    }
}

/// The words on the buttons that take a person from an answer to the screen it
/// is about.
public nonisolated enum CoachDestinationText {
    public static func title(_ route: AppRoute, intent: CoachIntent) -> String {
        switch route {
        case .recovery: "Open Recovery"
        case .sleep: intent == .bedtimeAdvice ? "See bedtime" : "Open Sleep"
        case .insights: "Open Insights"
        case .insight: "Open this insight"
        case .home: "Open Home"
        case .coach: "Open Coach"
        case .profile: "Open Profile"
        }
    }
}

/// The two lines under an answer.
public nonisolated enum CoachSourceText {
    public static let appleIntelligence = "Answered on your iPhone with Apple Intelligence"
    public static let fromYourData = "Answered from your data"

    /// The source label; nil for a fixed reply (which carries none).
    public static func label(_ kind: CoachSourceKind) -> String? {
        switch kind {
        case .appleIntelligence: appleIntelligence
        case .fromYourData: fromYourData
        case .remoteModel: nil
        case .scripted: nil
        }
    }
}
