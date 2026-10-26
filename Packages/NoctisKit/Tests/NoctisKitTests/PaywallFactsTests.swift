import Foundation
import SwiftUI
import Testing

@testable import DesignSystem
@testable import NoctisCore
@testable import OnboardingFeature

// The paywall in the band style (APP_RULES.md R58, App Store guideline 3.1.2): every trial word derives from ONE StoreKit value (introductory-offer
// eligibility), the renewal line is always the selected plan's, Save is worked out from the two real prices, and the benefit list is held to FeatureTable.
struct PaywallFactsTests {
    private func plan(_ id: String, yearly: Bool, price: Decimal, shown: String, trial: Bool = false) -> PaywallPlan {
        PaywallPlan(
            id: id, isYearly: yearly, displayPrice: shown, price: price, perMonthText: yearly ? "$3.33 / month" : nil, trialPhrase: trial ? "7 days" : nil,
            trialAdjective: trial ? "7-day" : nil)
    }

    private func facts(selected: String = StoreProductID.yearly, eligible: Bool, yearlyTrial: Bool = true) -> PaywallFacts {
        PaywallFacts(
            yearly: plan(StoreProductID.yearly, yearly: true, price: 39.99, shown: "$39.99", trial: yearlyTrial),
            monthly: plan(StoreProductID.monthly, yearly: false, price: 6.99, shown: "$6.99"),
            selectedID: selected, eligibleForIntroOffer: eligible
        )
    }

    // MARK: Eligible

    @Test func eligibleYearlyShowsTheBadgeTheTrialButtonAndTheTrialRenewalLine() {
        let f = facts(eligible: true)
        #expect(f.showsTrial && f.trialBadge == "7 days free")
        #expect(f.buttonTitle == "Start 7-day free trial")
        #expect(f.renewalText == "7 days free, then $39.99 per year, renewing automatically. Cancel anytime in Settings.")
    }

    @Test func eligibleButMonthlySelectedSaysContinueAndTheMonthlyPrice() {
        let f = facts(selected: StoreProductID.monthly, eligible: true)
        #expect(!f.showsTrial, "the monthly plan has no trial")
        #expect(f.buttonTitle == "Continue")
        #expect(f.renewalText == "$6.99 per month, renewing automatically. Cancel anytime in Settings.")
        #expect(f.trialBadge == "7 days free", "the yearly tile still says what the yearly plan offers")
    }

    // MARK: Not eligible, or not known

    @Test func notEligibleHidesTheBadgeAndSaysContinueWithTheRightPriceText() {
        let f = facts(eligible: false)
        #expect(!f.showsTrial && f.trialBadge == nil)
        #expect(f.buttonTitle == "Continue")
        #expect(
            f.renewalText == "$39.99 per year, renewing automatically. Cancel anytime in Settings.", "no trial wording for someone who cannot have the trial")
        #expect(f.savingsPercent == 52, "the saving is still true")
    }

    @Test func aTrialIsNeverClaimedWithoutAnIntroOfferOnTheProduct() {
        let f = facts(eligible: true, yearlyTrial: false)
        #expect(!f.showsTrial && f.trialBadge == nil && f.buttonTitle == "Continue")
        #expect(f.renewalText?.contains("free") == false)
    }

    @Test func everyTrialWordComesFromTheOneEligibilityValue() {
        for eligible in [true, false] {
            let f = facts(eligible: eligible)
            let badge = f.trialBadge != nil, button = f.buttonTitle != "Continue", renewal = f.renewalText?.contains("free, then") == true
            #expect(
                badge == eligible && button == eligible && renewal == eligible,
                "eligible \(eligible): badge \(badge), button \(button), renewal line \(renewal)")
        }
    }

    // MARK: Save

    @Test func theSavingIsWorkedOutFromTheTwoPricesAndRoundedNotTyped() {
        #expect(facts(eligible: true).savingsPercent == 52, "39.99 against 12 x 6.99")
        func percent(yearly: Decimal, monthly: Decimal) -> Int? {
            PaywallFacts(
                yearly: plan("y", yearly: true, price: yearly, shown: "x"), monthly: plan("m", yearly: false, price: monthly, shown: "y"), selectedID: "y",
                eligibleForIntroOffer: false
            ).savingsPercent
        }
        #expect(percent(yearly: 29.99, monthly: 4.99) == 50)
        #expect(percent(yearly: 24, monthly: 4) == 50)
        #expect(percent(yearly: 48, monthly: 4) == nil, "no saving: no badge")
        #expect(percent(yearly: 60, monthly: 4) == nil, "never a negative saving")
        #expect(percent(yearly: 10, monthly: 0) == nil)
    }

    // MARK: VoiceOver

    @Test func theTilesAndTheButtonReadWithTheirPriceAndTrial() {
        let f = facts(eligible: true)
        #expect(f.spoken(f.yearly!) == "Yearly, $39.99 per year, 7 days free, save 52 percent")
        #expect(f.spoken(f.monthly!) == "Monthly, $6.99 per month")
        #expect(f.buttonSpoken == "Start 7-day free trial, then $39.99 per year")
        let monthly = facts(selected: StoreProductID.monthly, eligible: true)
        #expect(monthly.buttonSpoken == "Continue, $6.99 per month")
        let notEligible = facts(eligible: false)
        #expect(notEligible.spoken(notEligible.yearly!) == "Yearly, $39.99 per year, save 52 percent", "no trial said when it cannot be had")
    }

    // MARK: Restore

    @Test func restoreSaysWhatHappened() {
        #expect(PaywallFacts.restoreMessage(.restored) == "Purchases restored.")
        #expect(PaywallFacts.restoreMessage(.nothingFound) == "No purchases found to restore.")
        #expect(PaywallFacts.restoreMessage(.failed) == "Restore failed. Please try again.")
        #expect(PaywallFacts.restoreMessage(nil).isEmpty, "no alert before there is an answer")
    }

    // MARK: Benefits

    @Test func theFiveLinesAreTheOnesTheScreenAlwaysHadAndEveryFeatureBehindThemIsPremium() {
        #expect(
            PaywallBenefits.all.map(\.text) == [
                "Recovery over 30 and 90 days", "A month of sleep, and what went into it", "Every insight, your records and history",
                "Unlimited Coach questions",
                "Wind-down, meditation and all six sounds",
            ])
        for benefit in PaywallBenefits.all {
            #expect(benefit.features.contains { FeatureTable.tier(of: $0) == .premium }, "\(benefit.text) has a Premium feature behind it")
        }
        // The line that says "all six sounds" is the three free and the three Premium ones, as the table has them.
        #expect(FeatureTable.tier(of: .soundsFree) == .free && FeatureTable.tier(of: .soundsPremium) == .premium)
        for feature in [
            Feature.recovery30D, .recovery90D, .sleepMonth, .sleepQualityFactors, .insightAll, .insightRecords, .insightHistory, .coachUnlimited,
            .windDownSession, .meditation,
        ] {
            #expect(FeatureTable.tier(of: feature) == .premium, "\(feature) is free in the table: the paywall cannot sell it")
        }
    }

    @Test func theDensitiesGetTighterAndOnlyTheLastCollapsesTheList() {
        let all = [PaywallMetrics.regular, .relaxed, .compact, .tight, .tightMore]
        #expect(all.map(\.benefitsShown) == [5, 5, 5, 5, 3])
        #expect(zip(all, all.dropFirst()).allSatisfy { $0.tileHeight >= $1.tileHeight && $0.bandContent >= $1.bandContent })
        #expect(PaywallMetrics.regular.bandContent == 190 && PaywallMetrics.regular.tileHeight == 118 && PaywallMetrics.regular.buttonHeight == 60)
    }

    @Test func theLinkOnTheDarkGroundIsAA() {
        func ratio(_ fg: String, _ bg: String) -> Double { noctisContrastRatio(noctisHexColor(fg), noctisHexColor(bg)) }
        #expect(ratio("F08A4B", "1A110B") >= 4.5, "Compare free and Premium, Dark")
        #expect(ratio("B14F18", "F8F5EE") >= 4.5, "Compare free and Premium, Light")
        #expect(noctisContrastRatio(noctisHexColor("F8F5EE"), noctisHexColor("2B1D14")) >= 4.5, "ivory on the band")
        // "Restore" is ivory at 70% on the band; the renewal line, links and medical line are 65% of the ink or ivory.
        func faded(_ fg: String, _ alpha: Double, _ bg: String) -> Double {
            noctisContrastRatio(noctisHexColor(noctisBlendHex(fg, over: bg, alpha: alpha)), noctisHexColor(bg))
        }
        #expect(faded("F8F5EE", 0.7, "2B1D14") >= 4.5, "Restore on the band")
        #expect(faded("2B1D14", 0.65, "F8F5EE") >= 4.5, "Light: the renewal line, links and medical line")
        #expect(faded("F8F5EE", 0.65, "1A110B") >= 4.5, "Dark: the renewal line, links and medical line")
        #expect(faded("2B1D14", 0.8, "F8F5EE") >= 4.5, "Light: Continue with the free plan")
    }
}
