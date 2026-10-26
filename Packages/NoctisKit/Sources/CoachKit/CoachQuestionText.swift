import Foundation
import NoctisCore

/// The words of a `CoachQuestion`: what a card says, what a chip says and what
/// is asked when a route carries one. All of it is in `Coach.xcstrings`.
public enum CoachQuestionText {
    public static func text(_ question: CoachQuestion, copy: (String) -> String = { CoachCopy.string($0) }) -> String {
        copy("coach.q.\(question.token)")
    }

    /// The intent the router should read a question's text as.
    public static func intent(of question: CoachQuestion) -> CoachIntent {
        switch question {
        case .recovery: .recoveryChange
        case .sleep: .sleepChange
        case .week: .weekChange
        case .bedtime: .bedtimeAdvice
        case .consistency: .consistencyHelp
        case .focus: .todayFocus
        case .insight(let type):
            switch type {
            case .sleepDurationShift, .stageShare, .recordLongestNight: .sleepChange
            case .bedtimeShift, .consistentBedtime, .consistencyChange, .weekendShift, .recordBestConsistency: .consistencyHelp
            case .recoveryDirection, .earlierBedtimePattern, .milestone: .patterns
            case .hrvBelowRange, .restingHeartRateAboveRange, .recordHighestRecovery, .recordLowestRestingHeartRate: .recoveryChange
            case .sleepBalance: .weekChange
            }
        }
    }
}

/// The three questions offered after an answer: what a person looking at that
/// one usually looks at next.
public enum CoachFollowUps {
    public static let maximum = 3

    public static func questions(after intent: CoachIntent) -> [CoachQuestion] {
        let list: [CoachQuestion] =
            switch intent {
            case .recoveryChange: [.sleep(nil), .bedtime, .focus]
            case .sleepChange: [.recovery(nil), .bedtime, .consistency]
            case .weekChange: [.recovery(nil), .consistency, .focus]
            case .bedtimeAdvice: [.consistency, .sleep(nil), .focus]
            case .consistencyHelp: [.bedtime, .week, .sleep(nil)]
            case .todayFocus: [.recovery(nil), .bedtime, .week]
            case .patterns: [.week, .recovery(nil), .consistency]
            case .medicalOutOfScope, .crisis, .unknown: []
            }
        return Array(list.prefix(maximum))
    }
}
