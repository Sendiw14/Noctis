import Foundation
import HealthProviding
import NightKit
import NoctisCore
import RecoveryKit
import SleepAnalysisKit

/// The words of Settings, apart from the screens: each is plain, and where it states a number or a behaviour it
/// takes it from the code that does it, so the two cannot drift apart (a test holds them to it).

// MARK: - Help

public nonisolated struct HelpEntry: Sendable, Equatable, Identifiable {
    public let key: String
    public let question: String
    public let answer: String

    public var id: String { key }
}

public nonisolated enum HelpCatalog {
    /// The eight questions, in the order they are shown. The words are in `Resources/Help.xcstrings`.
    public static let keys = ["recovery", "quality", "bedtime", "missing", "coach", "watch", "storage", "delete"]

    public static func string(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: key, table: "Help")
    }

    public static var entries: [HelpEntry] {
        keys.map { HelpEntry(key: $0, question: string("help.\($0).q"), answer: answer($0)) }
    }

    /// An answer: the catalog's words, with the sentences about privacy made from the data inventory (APP_RULES.md R41).
    static func answer(_ key: String, inventory: DataInventory = .shared) -> String {
        switch key {
        case "storage": PrivacyStatements.helpStorage(inventory)
        case "delete": PrivacyStatements.helpDelete(inventory)
        case "coach":
            string("help.coach.a")
                .replacingOccurrences(of: "{written}", with: PrivacyStatements.coachShort(inventory))
                .replacingOccurrences(of: "{neverSees}", with: PrivacyStatements.coachNeverSees(inventory))
        default: string("help.\(key).a")
        }
    }
}

// MARK: - About

public nonisolated enum AboutContent {
    public static let medical = "NOCTIS isn't a medical device and doesn't diagnose or treat any condition."
    public static let acknowledgements = "NOCTIS uses no third-party code, so there is nothing to acknowledge."

    /// "1.0 (42)".
    public static func versionLine(version: String, build: String) -> String { "\(version) (\(build))" }

    /// The model each number comes from, as the code names it.
    public static var models: [(name: String, version: String)] {
        [
            ("Recovery", RecoveryModel.current.rawValue),
            ("Sleep quality", SleepQualityModelV1.version),
            ("Bedtime", BedtimeModel.current.version),
        ]
    }
}

// MARK: - Notifications

public nonisolated enum NotificationsCopy {
    public struct Banner: Equatable {
        public let title: String
        public let detail: String
        /// The one button the state offers; nil when nothing needs doing.
        public let action: Action?

        public enum Action: Equatable {
            case allow
            case openSettings

            public var title: String { self == .allow ? "Turn on notifications" : "Open Settings" }
        }
    }

    public static func banner(for authorization: NotificationAuthorization) -> Banner {
        switch authorization {
        case .notDetermined:
            Banner(title: "Notifications aren't on yet", detail: "NOCTIS asks once, when you tap the button. Choose which reminders you want below.", action: .allow)
        case .denied:
            Banner(
                title: "Notifications are off for NOCTIS",
                detail: "Turn them on in Settings to get reminders. Your choices below are kept for when you do.", action: .openSettings
            )
        case .allowed:
            Banner(title: "Notifications are on", detail: "Each reminder below arrives at the time shown, whatever day it is.", action: nil)
        }
    }

    /// The switches work only where the system lets NOCTIS send anything.
    public static func switchesAreEnabled(_ authorization: NotificationAuthorization) -> Bool { authorization != .denied }

    public static var privacyNote: String { PrivacyStatements.remindersGeneric(.shared) }

    /// What the notification says, word for word.
    public static let morningSays = NotificationPlan.morningBody
    public static let weeklySays = NotificationPlan.weeklyBody
    public static func windDownSays(leadMinutes: Int, tier: Tier) -> String { NotificationPlan.windDownBody(leadMinutes: leadMinutes, tier: tier) }

    public static func minutesAfterWake(_ minutes: Int) -> String { minutes == 0 ? "At wake time" : "\(minutes) min after waking" }
    public static func minutesBeforeBed(_ minutes: Int) -> String { "\(minutes) min before bedtime" }

    /// "Sunday".
    public static func weekdayName(_ weekday: Int, calendar: Calendar = .autoupdatingCurrent) -> String {
        let symbols = calendar.weekdaySymbols
        return symbols[((weekday - 1) % 7 + 7) % 7]
    }
}

// MARK: - Health data

public nonisolated enum HealthCopy {
    /// What a kind is for, from the same list the authorization manager asks about.
    public static func purpose(_ kind: HealthDataKind) -> String { kind.benefit }

    /// "Data found · last sample Sep 29", "No data found", or "Couldn't check just now".
    public static func line(_ status: HealthKindStatus, calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) -> String {
        if status.couldNotCheck { return "Couldn't check just now" }
        guard let last = status.lastSample else { return "No data found" }
        let date = last.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day())
        return "Data found · last sample \(date)"
    }

    /// Why a kind can be empty, in the one honest sentence: HealthKit never says whether read access was declined.
    public static let emptyExplanation = "Nothing was recorded in the last \(HealthDataStatus.lookBackDays) days, or NOCTIS isn't allowed to read it. Apple Health doesn't tell apps which."

    public static func sourceLine(_ source: String?) -> String? {
        source.map { "Last night's sleep came from \($0)." }
    }

    public static let noDataTitle = "No Health data found"
    public static let noDataDetail = "NOCTIS found none of the kinds below in the last \(HealthDataStatus.lookBackDays) days. An iPhone on its own records no sleep or heart data: an Apple Watch or a sleep app does. If you have one, check that NOCTIS may read it."
    public static let unavailableDetail = "Apple Health isn't available on this device, so NOCTIS has nothing to read."
    public static let connectButton = "Connect Apple Health"
    public static let openHealthButton = "Open Health"
    public static let howAccessWorksButton = "How access works"

    public static var howAccessWorks: [String] { [
        "Apple Health lets you choose, for each kind of data, whether NOCTIS may read it. NOCTIS asks once; Apple never asks again, and never tells an app which kinds you declined. They just look empty.",
        "To change what NOCTIS can read, open the Health app, tap your picture at the top, and look for NOCTIS under Apps.",
        PrivacyStatements.healthKeeps(.shared) ?? "You can change what NOCTIS may read in the Health app at any time.",
    ] }
}

// MARK: - Subscription

public nonisolated enum SubscriptionCopy {
    public static func restoreMessage(_ result: StoreManager.RestoreResult) -> String {
        switch result {
        case .restored: "Premium is back on this iPhone."
        case .nothingFound: "There's nothing to restore for this Apple Account."
        case .failed: "Couldn't reach the App Store. Try again in a moment."
        }
    }
}
