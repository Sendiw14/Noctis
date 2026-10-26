import DesignSystem
import Foundation
import HomeFeature
import NoctisText

/// Turns a number into a `CoachFact`, formatted the way the rest of the app
/// formats it (`HomeFormat`: the person's locale and calendar), so the number
/// Coach says is the number a screen shows.
public struct CoachFactFormatter: Sendable {
    public let format: HomeFormat

    public init(format: HomeFormat) {
        self.format = format
    }

    /// A fact. With `magnitude`, a difference shows its size only ("1h 10m"):
    /// the sentence around it says which way.
    public func fact(
        _ id: String, _ label: String, _ value: Double, _ unit: CoachUnit, source: String, magnitude: Bool = false
    ) -> CoachFact {
        let shown = magnitude ? abs(value) : value
        let (display, spoken) = text(shown, unit: unit)
        return CoachFact(id: id, label: label, value: value, unit: unit, display: display, spoken: spoken, source: source)
    }

    /// What replaces a token, and what VoiceOver reads for it.
    public func text(_ value: Double, unit: CoachUnit) -> (display: String, spoken: String) {
        switch unit {
        case .points:
            let n = number(value)
            return (n, n)
        case .count:
            let n = number(value)
            return (n, n)
        case .duration:
            let minutes = Int(value.rounded())
            return (HomeFormat.compactDuration(minutes), HomeFormat.spokenDuration(minutes))
        case .minutes:
            let minutes = Int(value.rounded())
            return (HomeFormat.compactDuration(minutes, minutesWord: true), HomeFormat.spokenDuration(minutes))
        case .clock:
            let clock = format.clock(minutesAfterNoon: value)
            return (clock, clock)
        case .milliseconds:
            let n = number(value)
            return (NoctisQuantityText.text(n, .millisecond), NoctisUnit.millisecond.spoken(Int(value.rounded())))
        case .beatsPerMinute:
            let n = number(value)
            return (NoctisQuantityText.text(n, .beatsPerMinute), NoctisUnit.beatsPerMinute.spoken(Int(value.rounded())))
        case .percent:
            let n = number(value)
            return ("\(n)\(NoctisUnit.percent.symbol)", NoctisUnit.percent.spoken(Int(value.rounded())))
        }
    }

    private func number(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number.locale(format.locale))
    }

    /// Minutes since midnight as minutes after noon, the unit `.clock` facts
    /// carry (the unit every baseline in the engines uses).
    public static func afterNoon(sinceMidnight minutes: Int) -> Double {
        Double(((minutes - 720) % 1440 + 1440) % 1440)
    }
}
