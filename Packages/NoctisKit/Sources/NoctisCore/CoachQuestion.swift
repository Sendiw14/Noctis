import Foundation
import InsightsKit
import RecoveryKit
import SleepAnalysisKit

/// Which way a number moved, for a question that names it ("Why is my
/// recovery lower?").
public nonisolated enum CoachTrend: String, Sendable, Hashable, Codable, CaseIterable {
    case higher
    case lower
}

/// A question Coach can be handed without anyone typing it: a suggested
/// question, the button under Recovery's why line, the one on an insight's
/// page. The words are Coach's (`Coach.xcstrings`); a route carries only which
/// question it is.
public nonisolated enum CoachQuestion: Sendable, Hashable, Codable {
    /// "Why is my recovery higher / lower?" (neutral when it moved neither way).
    case recovery(CoachTrend?)
    /// "Why was my sleep better / worse?"
    case sleep(CoachTrend?)
    /// "What changed this week?"
    case week
    /// "When should I sleep?"
    case bedtime
    /// "How can I improve consistency?"
    case consistency
    /// "What should I focus on today?"
    case focus
    /// A question about one kind of insight.
    case insight(InsightType)

    /// The suggested questions, in the order Coach lists them with no data to rank by.
    public static let suggested: [CoachQuestion] = [.recovery(nil), .sleep(nil), .week, .bedtime, .consistency, .focus]

    /// A recovery difference of this many points is above or below usual (Recovery's own line for "in line").
    public static let recoveryThreshold = Double(RecoveryModelV1.trendThreshold)
    /// A sleep difference of this many minutes is longer or shorter than usual (Recovery's floor for a normal range).
    public static let sleepThresholdMinutes = RecoveryNormalRange.sleepDurationStandardDeviationFloor

    /// "Why is my recovery higher / lower today?", the way today's score really moved (neutral when it is in line or unknown).
    public static func recovery(delta: Int?) -> CoachQuestion {
        guard let delta else { return .recovery(nil) }
        let value = Double(delta)
        return .recovery(value <= -recoveryThreshold ? .lower : (value >= recoveryThreshold ? .higher : nil))
    }

    /// "Why was my sleep better / worse last night?", the way last night's time asleep really moved from usual, in minutes.
    public static func sleep(deltaMinutes: Double?) -> CoachQuestion {
        guard let deltaMinutes else { return .sleep(nil) }
        return .sleep(deltaMinutes <= -sleepThresholdMinutes ? .lower : (deltaMinutes >= sleepThresholdMinutes ? .higher : nil))
    }

    /// A short word for a URL and a log: "recovery.lower", "insight.bedtimeShift".
    public var token: String {
        switch self {
        case .recovery(let trend): trend.map { "recovery.\($0.rawValue)" } ?? "recovery"
        case .sleep(let trend): trend.map { "sleep.\($0.rawValue)" } ?? "sleep"
        case .week: "week"
        case .bedtime: "bedtime"
        case .consistency: "consistency"
        case .focus: "focus"
        case .insight(let type): "insight.\(type.rawValue)"
        }
    }

    public init?(token: String) {
        let parts = token.split(separator: ".", maxSplits: 1).map(String.init)
        let detail = parts.dropFirst().first
        switch parts.first {
        case "recovery": self = .recovery(detail.flatMap(CoachTrend.init(rawValue:)))
        case "sleep": self = .sleep(detail.flatMap(CoachTrend.init(rawValue:)))
        case "week": self = .week
        case "bedtime": self = .bedtime
        case "consistency": self = .consistency
        case "focus": self = .focus
        case "insight":
            guard let type = detail.flatMap(InsightType.init(rawValue:)) else { return nil }
            self = .insight(type)
        default: return nil
        }
    }
}

/// Screens pushed inside the Coach tab's navigation stack.
public nonisolated enum CoachPage: Sendable, Hashable {
    /// The conversation the tab is holding: the question asked, and its answer.
    case conversation
    /// Every stored conversation.
    case history
}

/// Which question the Coach tab should open on, until it takes it. Each is
/// distinct, so asking the same question twice is still a change.
public nonisolated struct CoachDestination: Sendable, Equatable {
    public let question: CoachQuestion?
    /// A question typed or spoken (Siri and Shortcuts): asked as typed text. Held in memory until the tab takes it, and nowhere else.
    public let text: String?
    let serial: Int

    init(question: CoachQuestion?, text: String? = nil, serial: Int) {
        self.question = question
        self.text = text
        self.serial = serial
    }
}
