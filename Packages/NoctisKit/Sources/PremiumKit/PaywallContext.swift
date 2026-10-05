import Foundation

// Why the paywall was opened (APP_RULES.md R58): the line above its title says exactly what the tapped thing unlocks. A paywall opens only after a tap on a
// locked element or on "What Premium includes", never on launch or on entering a tab.

public nonisolated enum PaywallContext: String, Sendable, Equatable, CaseIterable, Identifiable {
    case recovery30D, recovery90D, recoveryFactors
    case sleepMonth, sleepNights, sleepQuality, sleepDetails
    case insightsAll, insightsRecords, insightsHistory, insightsFilters
    case coachQuestions
    case tonightWindow
    case windDown, meditation, sounds
    case widgets, watch, siri
    case whatPremiumIncludes
    case general

    public var id: String { rawValue }

    /// The line above the paywall's title.
    public var line: String {
        switch self {
        case .recovery30D: "Unlock 30-day Recovery trends"
        case .recovery90D: "Unlock 90-day Recovery trends"
        case .recoveryFactors: "Unlock the detail behind each recovery factor"
        case .sleepMonth: "Unlock a month of sleep"
        case .sleepNights: "Unlock your last 14 nights"
        case .sleepQuality: "Unlock what went into your sleep quality"
        case .sleepDetails: "Unlock consistency, balance and timing details"
        case .insightsAll: "Unlock every insight NOCTIS finds"
        case .insightsRecords: "Unlock your records"
        case .insightsHistory: "Unlock your insight history"
        case .insightsFilters: "Unlock insights by category"
        case .coachQuestions: "Unlock unlimited Coach questions"
        case .tonightWindow: "Unlock why this time, and your bedtime window"
        case .windDown: "Unlock wind-down sessions"
        case .meditation: "Unlock meditation"
        case .sounds: "Unlock Wind, Fireplace and Ambient"
        case .widgets: "Unlock the medium and large widgets"
        case .watch: "Unlock Heart and Tonight on your Apple Watch"
        case .siri: "Unlock starting a wind-down with Siri"
        case .whatPremiumIncludes: "What Premium includes"
        case .general: "Understand yourself"
        }
    }

    /// The context a locked feature opens.
    public init(feature: Feature) {
        switch feature {
        case .recovery30D: self = .recovery30D
        case .recovery90D: self = .recovery90D
        case .recoveryFactorDetail: self = .recoveryFactors
        case .sleepMonth: self = .sleepMonth
        case .sleepNightPicker14: self = .sleepNights
        case .sleepQualityFactors: self = .sleepQuality
        case .sleepConsistencyBalanceTimingDetails: self = .sleepDetails
        case .insightAll: self = .insightsAll
        case .insightRecords: self = .insightsRecords
        case .insightHistory: self = .insightsHistory
        case .insightCategoryFilters: self = .insightsFilters
        case .coachUnlimited, .siriAskCoachBeyondFree: self = .coachQuestions
        case .tonightPersonalizedWindow: self = .tonightWindow
        case .windDownSession: self = .windDown
        case .meditation: self = .meditation
        case .soundsPremium: self = .sounds
        case .widgetMediumLargeAndOtherLock: self = .widgets
        case .watchHeartTonightPages, .watchOtherComplications: self = .watch
        case .siriStartWindDown: self = .siri
        default: self = .general
        }
    }
}

/// The keys the free-tier bookkeeping keeps in the app's defaults (listed in the data inventory, under the subscription).
public nonisolated enum PremiumKeys {
    /// The last tier seen, "free", "premium" or "lapsed": a first-frame cache, replaced by the App Store's answer each launch.
    public static let cachedTier = "noctis.entitlement.tier"
    /// The day and count of free Coach questions used: "2026-09-24|2". A count and a date, never a question.
    public static let coachQuota = "noctis.coach.quota"
}
