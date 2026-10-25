import Foundation
import Testing

@testable import DesignSystem
@testable import NoctisCore
@testable import OnboardingFeature

// Onboarding step 5 (Stay gently informed), in the band style: the same three reminders with the same words, in the same order, and the example text is the
// notification's own (R13). The redesign adds a row subtitle for each and a tap-for-the-next example; neither changes what is scheduled.
struct NotificationStepTests {
    @Test func theThreeRemindersAreInTheSameOrderWithTheSameNames() {
        #expect(NotificationKind.allCases.map(\.toggleTitle) == ["Morning summary", "Wind-down reminder", "Weekly review"])
        #expect(NotificationKind.allCases.map(\.identifier) == [NoctisNotification.morningSummary, NoctisNotification.windDown, NoctisNotification.weeklyReview])
    }

    @Test func theExamplesAreTheRealNotificationTexts() {
        #expect(NotificationKind.allCases.map(\.previewBody) == [
            "Your morning summary is ready.", "Your wind-down starts in 20 minutes.", "Your weekly review is ready.",
        ])
    }

    @Test func eachRowSaysWhatItDoes() {
        #expect(NotificationKind.allCases.map(\.toggleSubtitle) == [
            "Your night and recovery, ready when you wake", "20 minutes before your bedtime", "A calm look back, once a week",
        ])
    }

    @Test func tappingTheExampleGoesRoundTheThree() {
        var kind = NotificationKind.morningSummary
        var seen: [NotificationKind] = []
        for _ in 0..<4 {
            seen.append(kind)
            kind = kind.next
        }
        #expect(seen == [.morningSummary, .windDown, .weeklyReview, .morningSummary])
    }

    @Test func voiceOverReadsTheStackAsOneExampleAndEachSwitchWithItsLine() {
        #expect(NotificationKind.morningSummary.spokenExample == "Example notification: your morning summary is ready")
        #expect(NotificationKind.windDown.spokenExample == "Example notification: your wind-down starts in 20 minutes")
        #expect(NotificationKind.weeklyReview.spokenSwitch == "Weekly review. A calm look back, once a week")
        #expect(NotificationKind.windDown.spokenSwitch == "Wind-down reminder. 20 minutes before your bedtime")
    }

    @Test func noExampleCarriesAFigureFromTheBody() {
        // R13: generic only. No digits but the "20 minutes" the reminder is defined by, no scores, no streaks.
        for kind in NotificationKind.allCases {
            let digits = kind.previewBody.filter(\.isNumber)
            #expect(digits.isEmpty || (kind == .windDown && digits == "20"), "\(kind.previewBody)")
            #expect(!kind.previewBody.lowercased().contains("streak") && !kind.previewBody.contains("%"))
        }
    }
}
