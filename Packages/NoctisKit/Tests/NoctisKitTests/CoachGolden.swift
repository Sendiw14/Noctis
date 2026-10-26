import Foundation

@testable import CoachKit

enum CoachGolden {
    /// An answer as one comparable line, clock spaces made plain.
    static func render(_ answer: CoachAnswer) -> String {
        let fields: [String] = [
            "S: " + answer.summary,
            "C: " + answer.whatChanged,
            "N: " + answer.whatToNotice,
            "T: " + (answer.tonightSuggestion ?? "-"),
            "P: " + (answer.pattern ?? "-"),
            "K: " + answer.confidenceLine + " / " + (answer.caution ?? "-"),
            "W: " + answer.contributors.map { "\($0.label) \($0.value)" }.joined(separator: "; "),
            "D: " + answer.destinations.map(\.name).joined(separator: ","),
        ]
        return fields.joined(separator: " | ").plain
    }
}
