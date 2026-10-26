import Foundation

// The one place that decides what is free and what is Premium (APP_RULES.md R57, R59). Nothing else decides: a screen asks `FeatureGate`, and `FeatureGate`
// asks this table. Premium means more depth, never a broken free app (R57): the table says which depth a person sees, and presentation follows it. The
// engines keep computing for everyone, and nothing a person recorded is ever deleted or hidden by deletion when a subscription lapses.

public nonisolated enum Tier: String, Sendable, Equatable, CaseIterable, Codable {
    case free
    case premium
}

/// Every thing a person can be shown or can do that has a tier. An exhaustive switch in `FeatureTable.tier(of:)` means a new case does not compile
/// until it has one.
public nonisolated enum Feature: String, Sendable, Equatable, CaseIterable, Hashable, Codable {
    // Recovery
    case recoveryToday, recovery7D, recovery30D, recovery90D, recoveryFactorDetail
    // Sleep
    case sleepLast3Nights, sleepWeek, sleepMonth, sleepNightPicker14, sleepQualityScore, sleepQualityFactors, sleepConsistencyBalanceTimingDetails
    // Insights
    case insightFeatured, insightRecentOne, insightAll, insightRecords, insightHistory, insightCategoryFilters
    // Reviews
    case weeklyReviewCover, weeklyReviewFull, monthlyReview
    // Coach
    case coachQuestions, coachHistory, coachUnlimited
    // Tonight and the night
    case tonightSingleBedtime, tonightPersonalizedWindow, alarm, windDownSession, meditation, breathing, reflectJournal
    // Sounds
    case soundsFree, soundsPremium
    // Widgets
    case widgetSmall, widgetLockCircular, widgetMediumLargeAndOtherLock
    // Apple Watch
    case watchRecoverySleepPages, watchRecoveryComplication, watchBreathing, watchHeartTonightPages, watchOtherComplications
    // Siri and Shortcuts
    case siriRecoverySleepBedtime, siriStartWindDown, siriAskCoachBeyondFree
}

/// The parts of the app a feature belongs to, for the comparison sheet's headings.
public nonisolated enum FeatureArea: String, Sendable, CaseIterable, Equatable {
    case recovery, sleep, insights, reviews, coach, night, sounds, widgets, watch, siri

    public var title: String {
        switch self {
        case .recovery: "Recovery"
        case .sleep: "Sleep"
        case .insights: "Insights"
        case .reviews: "Reviews"
        case .coach: "Coach"
        case .night: "Tonight and the night"
        case .sounds: "Sleep sounds"
        case .widgets: "Widgets"
        case .watch: "Apple Watch"
        case .siri: "Siri and Shortcuts"
        }
    }
}

public nonisolated enum FeatureTable {
    /// The tier of every feature.
    public static func tier(of feature: Feature) -> Tier {
        switch feature {
        case .recoveryToday, .recovery7D, .sleepLast3Nights, .sleepWeek, .sleepQualityScore, .insightFeatured, .insightRecentOne, .coachQuestions,
            .coachHistory, .tonightSingleBedtime, .alarm, .breathing, .reflectJournal, .soundsFree, .widgetSmall, .widgetLockCircular, .watchRecoverySleepPages,
            .watchRecoveryComplication, .watchBreathing, .siriRecoverySleepBedtime, .weeklyReviewCover:
            .free
        case .recovery30D, .recovery90D, .recoveryFactorDetail, .sleepMonth, .sleepNightPicker14, .sleepQualityFactors, .sleepConsistencyBalanceTimingDetails,
            .insightAll, .insightRecords, .insightHistory, .insightCategoryFilters, .coachUnlimited, .tonightPersonalizedWindow, .windDownSession, .meditation,
            .soundsPremium, .widgetMediumLargeAndOtherLock, .watchHeartTonightPages, .watchOtherComplications, .siriStartWindDown, .siriAskCoachBeyondFree,
            .weeklyReviewFull, .monthlyReview:
            .premium
        }
    }

    public static func features(in tier: Tier) -> [Feature] { Feature.allCases.filter { self.tier(of: $0) == tier } }

    public static func isIncluded(_ feature: Feature, in tier: Tier) -> Bool {
        tier == .premium || self.tier(of: feature) == .free
    }

    public static func area(of feature: Feature) -> FeatureArea {
        switch feature {
        case .recoveryToday, .recovery7D, .recovery30D, .recovery90D, .recoveryFactorDetail: .recovery
        case .sleepLast3Nights, .sleepWeek, .sleepMonth, .sleepNightPicker14, .sleepQualityScore, .sleepQualityFactors, .sleepConsistencyBalanceTimingDetails:
            .sleep
        case .insightFeatured, .insightRecentOne, .insightAll, .insightRecords, .insightHistory, .insightCategoryFilters: .insights
        case .weeklyReviewCover, .weeklyReviewFull, .monthlyReview: .reviews
        case .coachQuestions, .coachHistory, .coachUnlimited: .coach
        case .tonightSingleBedtime, .tonightPersonalizedWindow, .alarm, .windDownSession, .meditation, .breathing, .reflectJournal: .night
        case .soundsFree, .soundsPremium: .sounds
        case .widgetSmall, .widgetLockCircular, .widgetMediumLargeAndOtherLock: .widgets
        case .watchRecoverySleepPages, .watchRecoveryComplication, .watchBreathing, .watchHeartTonightPages, .watchOtherComplications: .watch
        case .siriRecoverySleepBedtime, .siriStartWindDown, .siriAskCoachBeyondFree: .siri
        }
    }

    /// What it is, in plain words: the row's text in the comparison.
    public static func title(of feature: Feature) -> String {
        switch feature {
        case .recoveryToday: "Today's recovery and how it was built"
        case .recovery7D: "Recovery over 7 days"
        case .recovery30D: "Recovery over 30 days"
        case .recovery90D: "Recovery over 90 days"
        case .recoveryFactorDetail: "The detail behind each recovery factor"
        case .sleepLast3Nights: "Sleep for your last 3 nights"
        case .sleepWeek: "Sleep over a week"
        case .sleepMonth: "Sleep over a month"
        case .sleepNightPicker14: "Look back at any of your last 14 nights"
        case .sleepQualityScore: "Your sleep quality score"
        case .sleepQualityFactors: "What went into the score, and what changed"
        case .sleepConsistencyBalanceTimingDetails: "Consistency, balance and timing details"
        case .insightFeatured: "The featured insight"
        case .insightRecentOne: "Your most recent other insight"
        case .insightAll: "Every insight NOCTIS finds"
        case .insightRecords: "Your records"
        case .insightHistory: "Your insight history"
        case .insightCategoryFilters: "Insights by category"
        case .weeklyReviewCover: "The summary of your weekly review"
        case .weeklyReviewFull: "Every page of your weekly review"
        case .monthlyReview: "Your monthly review"
        case .coachQuestions: "3 Coach questions a day"
        case .coachHistory: "Your Coach history"
        case .coachUnlimited: "Unlimited Coach questions"
        case .tonightSingleBedtime: "Tonight's bedtime"
        case .tonightPersonalizedWindow: "Why this time, and your bedtime window"
        case .alarm: "The wake alarm"
        case .windDownSession: "Wind-down sessions"
        case .meditation: "Meditation"
        case .breathing: "Breathing"
        case .reflectJournal: "Reflect and your journal"
        case .soundsFree: "Brown noise, Rain and Ocean"
        case .soundsPremium: "Wind, Fireplace and Ambient"
        case .widgetSmall: "The small Home Screen widget"
        case .widgetLockCircular: "The circular Lock Screen widget"
        case .widgetMediumLargeAndOtherLock: "Medium and large widgets, and the other Lock Screen widgets"
        case .watchRecoverySleepPages: "Recovery and Sleep on your Apple Watch"
        case .watchRecoveryComplication: "The Recovery complication"
        case .watchBreathing: "Breathing on your Apple Watch"
        case .watchHeartTonightPages: "Heart and Tonight on your Apple Watch"
        case .watchOtherComplications: "The other complications"
        case .siriRecoverySleepBedtime: "Ask Siri for recovery, sleep and bedtime"
        case .siriStartWindDown: "Start a wind-down with Siri"
        case .siriAskCoachBeyondFree: "Ask Coach through Siri beyond the free questions"
        }
    }

    /// An SF Symbol for the feature's row.
    public static func symbol(of feature: Feature) -> String {
        switch area(of: feature) {
        case .recovery: "heart.text.square"
        case .sleep: "bed.double"
        case .insights: "lightbulb"
        case .reviews: "calendar"
        case .coach: "sparkles"
        case .night: "moon.stars"
        case .sounds: "speaker.wave.2"
        case .widgets: "rectangle.on.rectangle"
        case .watch: "applewatch"
        case .siri: "mic"
        }
    }

    /// One row of the comparison: made from the table and nothing else, so it cannot disagree with it.
    public struct Row: Sendable, Equatable, Identifiable {
        public let feature: Feature
        public let title: String
        public let symbol: String
        public let free: Bool
        public var premium: Bool { true }
        public var id: Feature { feature }

        /// "Free: Included. Premium: Included." for VoiceOver, and the words under the marks (never color alone).
        public var spoken: String { "\(title). Free: \(free ? "Included" : "Not included"). Premium: Included." }
    }

    /// The comparison, by area, in the table's order; every feature is in it exactly once.
    public static func comparison() -> [(area: FeatureArea, rows: [Row])] {
        FeatureArea.allCases.map { area in
            (
                area,
                Feature.allCases.filter { self.area(of: $0) == area }.map {
                    Row(feature: $0, title: title(of: $0), symbol: symbol(of: $0), free: tier(of: $0) == .free)
                }
            )
        }
    }
}
