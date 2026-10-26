import CoachKit
import DesignSystem
import Foundation
import HomeFeature
import NoctisCore

/// Which of the section colors a suggested question's tile wears.
public nonisolated enum CoachTile: Sendable, Equatable {
    case lavender
    case sage
    case butter
    case apricot
    case rose
}

/// One suggested question on the hub.
public nonisolated struct CoachQuestionCard: Sendable, Equatable, Identifiable {
    public let question: CoachQuestion
    public let title: String
    public let symbol: String
    public let tile: CoachTile
    public let isEnabled: Bool

    public var id: String { question.token }
}

/// What the hub shows instead of the questions being askable, when there's
/// nothing yet to ask about.
public nonisolated enum CoachHubState: Sendable, Equatable {
    /// Health access isn't granted (or there's no Health on this device).
    case connect(title: String, message: String, showsButton: Bool)
    /// Access is granted and there's no sleep to read.
    case noSleepData(title: String, message: String)
    case failed(message: String)
}

/// Everything the hub lays out (APP_RULES.md R20): the words are written here,
/// once, from the ranked questions and the state of the data.
public nonisolated struct CoachHubContent: Sendable, Equatable {
    public static let summary = "Understand your patterns."
    public static let firstRunText = "Coach explains patterns in your own data. It isn't medical advice."
    public static let firstRunButton = "How Coach uses your data"
    public static let withoutAppleIntelligence = "Answers are built from your data without Apple Intelligence"
    public static let turnOnAppleIntelligence = "Turn on Apple Intelligence"
    public static let disabledReason = "Available once Coach can read a few of your nights."

    public let dateCaption: String
    public let cards: [CoachQuestionCard]
    /// Set when there's nothing to ask about yet; the cards are then disabled.
    public let state: CoachHubState?
    /// "Coach has 3 nights to read so far...": under five nights, answers say when they can't say more.
    public let learningNote: String?
    /// The banner under the field: Coach can't use Apple Intelligence.
    public let appleIntelligenceUnavailable: Bool
    /// The one case the person can fix from Settings.
    public let showsTurnOnAppleIntelligence: Bool
    public let showsFirstRun: Bool

    public var questionsAreEnabled: Bool { state == nil }

    public init(
        dateCaption: String, cards: [CoachQuestionCard], state: CoachHubState?, learningNote: String?, appleIntelligenceUnavailable: Bool,
        showsTurnOnAppleIntelligence: Bool, showsFirstRun: Bool
    ) {
        self.dateCaption = dateCaption
        self.cards = cards
        self.state = state
        self.learningNote = learningNote
        self.appleIntelligenceUnavailable = appleIntelligenceUnavailable
        self.showsTurnOnAppleIntelligence = showsTurnOnAppleIntelligence
        self.showsFirstRun = showsFirstRun
    }
}

public nonisolated enum CoachHubBuilder {
    /// Under this many nights Home is still learning the baseline.
    public static let learningNights = CoachContextBuilder.learningNights

    public static func build(
        suggestions: [CoachSuggestion], dataState: HomeDataState?, availability: CoachAvailability, showsFirstRun: Bool, now: Date, format: HomeFormat
    ) -> CoachHubContent {
        let state = state(dataState)
        let cards = suggestions.map { card($0, enabled: state == nil) }
        var learning: String?
        if state == nil, case .learning(let nights)? = dataState, nights > 0 {
            let count = nights.formatted(.number.locale(format.locale))
            learning =
                nights == 1
                ? "Coach has \(count) night to read so far. Answers say when there isn't enough yet."
                : "Coach has \(count) nights to read so far. Answers say when there isn't enough yet."
        }
        return CoachHubContent(
            dateCaption: format.longDate(now).uppercased(with: format.locale),
            cards: cards,
            state: state,
            learningNote: learning,
            appleIntelligenceUnavailable: availability != .available,
            showsTurnOnAppleIntelligence: availability == .notEnabled,
            showsFirstRun: showsFirstRun
        )
    }

    /// The same copy Home, Sleep, Recovery and Insights use for the same situations.
    static func state(_ dataState: HomeDataState?) -> CoachHubState? {
        let title = "Coach needs a few nights to explain your patterns"
        switch dataState {
        case .healthDataUnavailable?:
            return .connect(title: title, message: "Apple Health isn't available on this device.", showsButton: false)
        case .permissionRequired?:
            return .connect(title: title, message: "Connect Apple Health so NOCTIS can read your nights.", showsButton: true)
        case .empty?, .learning(nightsSoFar: 0)?:
            return .noSleepData(
                title: title, message: "NOCTIS reads sleep from Apple Health. Track sleep with Apple Watch or set up Sleep in the Health app."
            )
        case .failed?:
            return .failed(message: "We couldn't read your latest sleep data.")
        case .stale?, .learning?, .noSleepLastNight?, .ready?, nil:
            return nil
        }
    }

    static func card(_ suggestion: CoachSuggestion, enabled: Bool) -> CoachQuestionCard {
        let (symbol, tile): (String, CoachTile) =
            switch suggestion.question {
            case .recovery: ("heart", .lavender)
            case .sleep: ("moon.zzz", .sage)
            case .week: ("calendar", .butter)
            case .bedtime: ("bed.double", .apricot)
            case .consistency: ("repeat", .butter)
            case .focus: ("scope", .rose)
            case .insight: ("lightbulb", .butter)
            }
        return CoachQuestionCard(
            question: suggestion.question, title: CoachQuestionText.text(suggestion.question), symbol: symbol, tile: tile, isEnabled: enabled
        )
    }
}
