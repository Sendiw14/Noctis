import DesignSystem
import Foundation
import NoctisCore
import SwiftUI

/// A plan as the paywall shows it, mapped once from a real StoreKit `Product` (in `PaywallScreen`): the price is the product's own `displayPrice`, the trial is
/// its own introductory offer, and nothing here is typed in by hand.
struct PaywallPlan: Equatable, Identifiable {
    let id: String
    let isYearly: Bool
    let displayPrice: String
    let price: Decimal
    /// "$3.33 / month" under the yearly price: the year's price over twelve, in the product's own format.
    let perMonthText: String?
    /// The free trial the product's introductory offer grants: "7 days" and "7-day". Nil when it has none.
    let trialPhrase: String?
    let trialAdjective: String?

    var name: String { isYearly ? "Yearly" : "Monthly" }
    var periodWord: String { isYearly ? "year" : "month" }
}

/// Everything the paywall says that depends on a choice: which plan is selected, whether the trial is on offer, what the button says, what the renewal line
/// says, what Save is. The trial words all derive from ONE value, `eligibleForIntroOffer` (StoreKit's `Product.SubscriptionInfo.isEligibleForIntroOffer`): the
/// badge, the button and the renewal line cannot disagree, on any device. It is false until StoreKit has answered, and if it cannot.
struct PaywallFacts: Equatable {
    var yearly: PaywallPlan?
    var monthly: PaywallPlan?
    var selectedID: String
    var eligibleForIntroOffer: Bool

    var plans: [PaywallPlan] { [yearly, monthly].compactMap { $0 } }
    var selected: PaywallPlan? { plans.first { $0.id == selectedID } }

    /// The trial is offered to this person for the selected plan.
    var showsTrial: Bool { eligibleForIntroOffer && selected?.trialPhrase != nil }

    /// The yearly plan's "7 DAYS FREE" badge: only when the person can have the trial.
    var trialBadge: String? {
        guard eligibleForIntroOffer, let phrase = yearly?.trialPhrase else { return nil }
        return "\(phrase) free"
    }

    /// "Save 52%": worked out from the two real prices (a year of months, against the year), never typed.
    var savingsPercent: Int? {
        guard let yearly, let monthly else { return nil }
        let monthsCost = monthly.price * 12
        guard monthsCost > 0 else { return nil }
        let saving = 1 - (yearly.price / monthsCost)
        let percent = Int((Double(truncating: saving as NSDecimalNumber) * 100).rounded())
        return percent > 0 ? percent : nil
    }

    /// "Start 7-day free trial", or "Continue" when there is no trial to start (not eligible, or the monthly plan).
    var buttonTitle: String {
        guard showsTrial, let adjective = selected?.trialAdjective else { return "Continue" }
        return "Start \(adjective) free trial"
    }

    /// The line under the button, for the SELECTED plan, always: price, period, that it renews, and how to stop it.
    var renewalText: String? {
        guard let plan = selected else { return nil }
        if showsTrial, let phrase = plan.trialPhrase {
            return "\(phrase) free, then \(plan.displayPrice) per \(plan.periodWord), renewing automatically. Cancel anytime in Settings."
        }
        return "\(plan.displayPrice) per \(plan.periodWord), renewing automatically. Cancel anytime in Settings."
    }

    /// The alert after Restore Purchases.
    static func restoreMessage(_ result: StoreManager.RestoreResult?) -> String {
        switch result {
        case .restored: "Purchases restored."
        case .nothingFound: "No purchases found to restore."
        case .failed: "Restore failed. Please try again."
        case nil: ""
        }
    }

    /// What VoiceOver says for a tile: "Yearly, $39.99 per year, 7 days free, save 52 percent". The tile is selected or not by its trait.
    func spoken(_ plan: PaywallPlan) -> String {
        var parts = ["\(plan.name), \(plan.displayPrice) per \(plan.periodWord)"]
        if plan.isYearly, let badge = trialBadge { parts.append(badge) }
        if plan.isYearly, let percent = savingsPercent { parts.append("save \(percent) percent") }
        return parts.joined(separator: ", ")
    }

    /// The button's label includes the price and the trial: "Start 7-day free trial, then $39.99 per year".
    var buttonSpoken: String {
        guard let plan = selected else { return buttonTitle }
        return showsTrial ? "\(buttonTitle), then \(plan.displayPrice) per \(plan.periodWord)" : "\(buttonTitle), \(plan.displayPrice) per \(plan.periodWord)"
    }
}

/// One of the five lines on the benefits card, with the Premium features of `FeatureTable` it speaks of: each must be Premium there (`PaywallBenefitTests`),
/// so the list cannot promise what the table gives away free.
struct PaywallBenefit: Identifiable {
    let id: Int
    let icon: String
    let text: String
    let features: [Feature]
}

enum PaywallBenefits {
    static let all: [PaywallBenefit] = [
        PaywallBenefit(id: 0, icon: "heart.fill", text: "Recovery over 30 and 90 days", features: [.recovery30D, .recovery90D]),
        PaywallBenefit(id: 1, icon: "moon.zzz.fill", text: "A month of sleep, and what went into it", features: [.sleepMonth, .sleepQualityFactors]),
        PaywallBenefit(id: 2, icon: "chart.line.uptrend.xyaxis", text: "Every insight, your records and history", features: [.insightAll, .insightRecords, .insightHistory]),
        PaywallBenefit(id: 3, icon: "sparkles", text: "Unlimited Coach questions", features: [.coachUnlimited]),
        PaywallBenefit(id: 4, icon: "speaker.wave.2.fill", text: "Wind-down, meditation and all six sounds", features: [.windDownSession, .meditation, .soundsFree, .soundsPremium]),
    ]

    /// The colour of each icon's circle, in the order above: orange, sage, lavender, ivory and butter.
    static func fill(_ id: Int) -> Color {
        switch id {
        case 0: NoctisPaper.orange
        case 1: NoctisPaper.sage
        case 2: NoctisPaper.lavender
        case 3: NoctisPaper.ivory
        default: NoctisPaper.butter
        }
    }
}

/// How much of the screen the paywall can have: the design's sizes, then tighter ones for a sheet or a short screen. The first that fits the height is used;
/// the last scrolls (the accessibility sizes), with the button pinned.
struct PaywallMetrics: Equatable {
    var bandContent: CGFloat
    var titleSize: CGFloat
    var ring: CGFloat
    var ringLine: CGFloat
    var benefitRowHeight: CGFloat
    var benefitsShown: Int
    var cardPadding: CGFloat
    var tileHeight: CGFloat
    var buttonHeight: CGFloat
    var gap: CGFloat
    /// "Sleep deeper." on one line, for a short screen.
    var oneLineTitle: Bool = false

    static let regular = PaywallMetrics(bandContent: 190, titleSize: 40, ring: 92, ringLine: 10, benefitRowHeight: 32, benefitsShown: 5, cardPadding: 10, tileHeight: 118, buttonHeight: 60, gap: 16)
    /// Between the two: what the design's page gives up to make room for the trial reminder's switch (shown once notifications are allowed).
    static let relaxed = PaywallMetrics(bandContent: 160, titleSize: 38, ring: 80, ringLine: 9, benefitRowHeight: 30, benefitsShown: 5, cardPadding: 9, tileHeight: 112, buttonHeight: 56, gap: 12)
    static let compact = PaywallMetrics(bandContent: 150, titleSize: 34, ring: 72, ringLine: 8, benefitRowHeight: 28, benefitsShown: 5, cardPadding: 8, tileHeight: 108, buttonHeight: 54, gap: 10)
    static let tight = PaywallMetrics(bandContent: 124, titleSize: 30, ring: 58, ringLine: 7, benefitRowHeight: 26, benefitsShown: 5, cardPadding: 6, tileHeight: 100, buttonHeight: 50, gap: 8, oneLineTitle: true)
    /// Only if the five rows cannot fit: the first three and "and more".
    static let tightMore = PaywallMetrics(bandContent: 124, titleSize: 30, ring: 58, ringLine: 7, benefitRowHeight: 26, benefitsShown: 3, cardPadding: 6, tileHeight: 100, buttonHeight: 50, gap: 8, oneLineTitle: true)
}
