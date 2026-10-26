import Foundation
import Testing

@testable import NoctisWatchKit
@testable import NoctisWidgetKit
@testable import PremiumKit

// The Apple Watch by plan (APP_RULES.md R62): the Recovery and Sleep pages, the Recovery complication (all four families) and Breathing are free; the Heart and
// Tonight pages and the Sleep, Bedtime and Sleep quality complications are Premium. A locked page is a Watch-sized card saying it is part of NOCTIS Premium and where to
// learn more (there is no purchase on the Watch); a locked complication is a plain "Premium" state that opens the Watch app. The plan is the one word in the snapshot the
// iPhone sent, and with no snapshot nothing is known and nothing is claimed to be locked.

private nonisolated let gateCalendar: Calendar = {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: "America/New_York") ?? .current
    return value
}()

private nonisolated let gateNow: Date = gateCalendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 10)) ?? Date()
private nonisolated let gateEvening: Date = gateCalendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 21, minute: 30)) ?? Date()
private let gateFormat = WidgetFormat(calendar: gateCalendar, locale: Locale(identifier: "en_US"))

private func gateSnapshot(_ state: WidgetDataState = .full, tier: Tier, at date: Date = gateNow) -> WidgetSnapshot {
    var value = WidgetSamples.snapshot(state, now: date, calendar: gateCalendar, tier: tier)
    value.forDay = WidgetDay(year: 2026, month: 9, day: 24)
    return value
}

private func input(_ snapshot: WidgetSnapshot?, now: Date = gateNow) -> WatchPageInput {
    WatchPageInput(snapshot: snapshot, now: now, format: gateFormat)
}

private func digitFree(_ text: String) -> Bool { !text.contains { $0.isNumber } }

struct WatchGateDecisionTests {
    @Test func thePagesAndKindsAreExactlyTheOnesTheTableSays() {
        let freePages: Set<WatchPage> = [.recovery, .sleep, .settings]
        for page in WatchPage.allCases {
            #expect(WatchGate.isLocked(page, tier: .free) == !freePages.contains(page), Comment(rawValue: page.rawValue))
            #expect(!WatchGate.isLocked(page, tier: .premium), Comment(rawValue: "premium has every page: \(page.rawValue)"))
            #expect(!WatchGate.isLocked(page, tier: nil), "no snapshot: nothing is known, nothing is locked")
        }
        #expect(WatchGate.feature(for: WatchPage.settings) == nil, "Settings is always free")
        for kind in WatchComplicationKind.allCases {
            #expect(WatchGate.isLocked(kind, tier: .free) == (kind != .recovery), Comment(rawValue: kind.rawValue))
            #expect(!WatchGate.isLocked(kind, tier: .premium))
            #expect(!WatchGate.isLocked(kind, tier: nil))
        }
        #expect(WatchGate.feature(for: WatchPage.recovery) == .watchRecoverySleepPages && WatchGate.feature(for: WatchPage.sleep) == .watchRecoverySleepPages)
        #expect(WatchGate.feature(for: WatchPage.heart) == .watchHeartTonightPages && WatchGate.feature(for: WatchPage.tonight) == .watchHeartTonightPages)
        #expect(WatchGate.feature(for: WatchComplicationKind.recovery) == .watchRecoveryComplication)
        for kind in [WatchComplicationKind.sleep, .bedtime, .quality] { #expect(WatchGate.feature(for: kind) == .watchOtherComplications) }
    }

    @Test func theDecisionIsTheTablesAndNothingElses() {
        for page in WatchPage.allCases {
            guard let feature = WatchGate.feature(for: page) else { continue }
            #expect(WatchGate.isLocked(page, tier: .free) == !FeatureTable.isIncluded(feature, in: .free))
        }
        for kind in WatchComplicationKind.allCases {
            #expect(WatchGate.isLocked(kind, tier: .free) == !FeatureTable.isIncluded(WatchGate.feature(for: kind), in: .free))
        }
    }

    @Test func theLockedWordsAreTheOnesWritten() {
        #expect(WatchGate.lockedLine == "Part of NOCTIS Premium. Open NOCTIS on your iPhone to learn more.")
        for page in [WatchPage.heart, .tonight] {
            let content = WatchLockedContent(page)
            #expect(content.title == page.title && content.line == WatchGate.lockedLine)
            #expect(content.accessibilityLabel == "\(page.title). \(WatchGate.lockedLine)")
            #expect(digitFree(content.accessibilityLabel))
            #expect(LockedCopy.pressure(in: content.accessibilityLabel).isEmpty)
        }
    }
}

struct WatchLockedPageTests {
    @Test func aFreePersonSeesTheRecoveryAndSleepPagesAsTheyAlwaysWere() {
        for state in [WidgetDataState.full, .sleepOnly, .stale(hours: 14), .learning(nightsSoFar: 3), .gap] {
            let free = input(gateSnapshot(state, tier: .free))
            let premium = input(gateSnapshot(state, tier: .premium))
            #expect(WatchPages.recovery(free) == WatchPages.recovery(premium), Comment(rawValue: "\(state)"))
            #expect(WatchPages.sleep(free) == WatchPages.sleep(premium), Comment(rawValue: "\(state)"))
            #expect(WatchPages.settings(free, version: "1") == WatchPages.settings(premium, version: "1"))
        }
    }

    @Test func theHeartAndTonightPagesAreALockedCardAndNothingElseOnTheFreePlan() {
        for state in [WidgetDataState.full, .sleepOnly, .stale(hours: 14), .learning(nightsSoFar: 3), .empty, .gap] {
            let snapshot = gateSnapshot(state, tier: .free)
            let heart = WatchPages.heart(input(snapshot))
            #expect(
                heart.locked == WatchLockedContent(.heart) && heart.tiles.isEmpty && heart.message == nil && heart.staleLine == nil,
                Comment(rawValue: "\(state)"))
            #expect(heart.accessibilityLabel == WatchLockedContent(.heart).accessibilityLabel && heart.sensitivity == .plan)
            let tonight = WatchPages.tonight(input(snapshot))
            #expect(
                tonight.locked == WatchLockedContent(.tonight) && tonight.bedtime == nil && tonight.windowText == nil && tonight.wakeLine == nil
                    && tonight.alarmLine == nil)
            #expect(tonight.countdown == .none && tonight.message == nil && tonight.sensitivity == .plan)
            #expect(digitFree(heart.accessibilityLabel) && digitFree(tonight.accessibilityLabel), "no number can reach a locked page")
        }
    }

    @Test func theEveningDoesNotUnlockTheTonightPageEither() {
        let tonight = WatchPages.tonight(input(gateSnapshot(.full, tier: .free, at: gateEvening), now: gateEvening))
        #expect(tonight.locked != nil && tonight.countdown == .none)
    }

    @Test func aPremiumPersonSeesBothPagesAsThePagesAlwaysWere() {
        let snapshot = gateSnapshot(.full, tier: .premium)
        let heart = WatchPages.heart(input(snapshot))
        #expect(heart.locked == nil && !heart.tiles.isEmpty)
        let tonight = WatchPages.tonight(input(snapshot))
        #expect(tonight.locked == nil && tonight.alarmLine != nil && (tonight.bedtime != nil || tonight.windowText != nil))
    }

    @Test func withNoSnapshotNothingIsClaimedToBeLocked() {
        let nothing = input(nil)
        #expect(WatchPages.heart(nothing).locked == nil && WatchPages.tonight(nothing).locked == nil)
        #expect(WatchPages.tonight(nothing).message?.title == WatchCopy.getStarted, "it says to open NOCTIS on the iPhone, as it always did")
    }

    @Test func theLockedCardIsDrawnFromThePageAloneAndBreathingIsStillOnTheTonightPage() throws {
        let views = RawDefaultsTests.code(try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Watch/App/WatchViews.swift"), encoding: .utf8))
        let start = try #require(views.range(of: "struct WatchLockedView: View {"))
        let end = try #require(views.range(of: "private struct WatchQuietLine", range: start.upperBound..<views.endIndex))
        let locked = String(views[start.lowerBound..<end.lowerBound])
        for word in ["snapshot", "StoreKit", "NoctisMetric", "score", "Button"] {
            #expect(!locked.contains(word), Comment(rawValue: "the locked card uses \(word)"))
        }
        for size in locked.components(separatedBy: "noctisFont(").dropFirst().compactMap({ Int($0.prefix { $0.isNumber }) }) { #expect(size >= 12) }
        // Locked or not, the Tonight page ends with the Breathe button (free, and it needs nothing from the iPhone).
        let tonight = try #require(views.range(of: "struct TonightPageView: View {"))
        let page = views[tonight.lowerBound...]
        let lockedAt = try #require(page.range(of: "WatchLockedView(content: locked)"))
        let breatheAt = try #require(page.range(of: "Button(action: breathe)"))
        #expect(lockedAt.lowerBound < breatheAt.lowerBound, "the button follows the page's content, locked or not")
    }
}

struct WatchLockedComplicationTests {
    private func content(_ kind: WatchComplicationKind, _ snapshot: WidgetSnapshot?, now: Date = gateNow) -> WatchComplicationContent {
        WatchComplications.content(kind, input: input(snapshot, now: now))
    }

    @Test func theRecoveryComplicationIsTheSameOnBothPlansInEveryFamilyAndState() {
        for state in [WidgetDataState.full, .sleepOnly, .stale(hours: 14), .learning(nightsSoFar: 3), .empty, .gap] {
            let free = content(.recovery, gateSnapshot(state, tier: .free))
            #expect(free == content(.recovery, gateSnapshot(state, tier: .premium)), Comment(rawValue: "\(state)"))
            #expect(!free.isLocked)
        }
    }

    @Test func theOtherThreeKindsAreAPlainPremiumStateOnTheFreePlanWhateverTheNumbersAre() {
        for kind in [WatchComplicationKind.sleep, .bedtime, .quality] {
            for state in [WidgetDataState.full, .sleepOnly, .stale(hours: 14), .learning(nightsSoFar: 3), .empty, .gap] {
                let locked = content(kind, gateSnapshot(state, tier: .free))
                #expect(locked.isLocked && locked.kind == kind, Comment(rawValue: "\(kind) \(state)"))
                #expect(locked.gauge == nil && locked.centerText.isEmpty && locked.centerGlyph == "lock.fill" && !locked.centerIsHealth)
                #expect(locked.stages == nil)
                #expect(locked.cornerLabel == "Premium")
                #expect(locked.inline == [.text("Premium")])
                #expect(locked.rectangular == [[.text("Premium")], [.text("Open NOCTIS")]])
                #expect(locked.link == kind.link, "a tap opens the Watch app")
                let spoken = locked.accessibilityLabel
                #expect(spoken == "\(kind.displayName). Premium. Opens NOCTIS.")
                #expect(digitFree(spoken), "the name of a kind has no number")
                #expect(locked.locked() == locked, "there is no Health value in it to hide while the Watch is locked")
            }
        }
    }

    @Test func aPremiumPersonHasAllFourKindsAsTheyAlwaysWere() {
        for kind in WatchComplicationKind.allCases {
            let value = content(kind, gateSnapshot(.full, tier: .premium))
            #expect(!value.isLocked && value.cornerLabel == kind.cornerLabel, Comment(rawValue: kind.rawValue))
        }
    }

    @Test func noLockedStateHasANumberInAnyWordItSays() {
        for kind in [WatchComplicationKind.sleep, .bedtime, .quality] {
            let locked = content(kind, gateSnapshot(.full, tier: .free))
            func words(_ pieces: [WidgetLockPiece]) -> String {
                pieces.map { piece -> String in
                    switch piece {
                    case .text(let text), .health(let text): text
                    case .countdown: "<timer>"
                    }
                }.joined()
            }
            let all = ([locked.centerText, locked.cornerLabel, words(locked.inline)] + locked.rectangular.map(words)).joined(separator: " ")
            #expect(digitFree(all), Comment(rawValue: "\(kind): \(all)"))
        }
    }

    @Test func withNoSnapshotItStillSaysToOpenNOCTISAndClaimsNothing() {
        for kind in WatchComplicationKind.allCases {
            let value = content(kind, nil)
            #expect(!value.isLocked && value.inline == [.text("Open NOCTIS on iPhone")], Comment(rawValue: kind.rawValue))
        }
    }

    @Test func aLockedKindGivesTheSmartStackNothingToPromote() {
        let morning = gateSnapshot(.full, tier: .free)
        let evening = gateSnapshot(.full, tier: .free, at: gateEvening)
        for kind in WatchComplicationKind.allCases {
            let lockedKind = kind != .recovery
            let relevance = WatchComplicationSchedule.relevance(kind, at: gateNow, snapshot: morning, calendar: gateCalendar)
            let premiumRelevance = WatchComplicationSchedule.relevance(kind, at: gateNow, snapshot: gateSnapshot(.full, tier: .premium), calendar: gateCalendar)
            #expect(lockedKind ? relevance == .idle : relevance == premiumRelevance, Comment(rawValue: kind.rawValue))
            let window = WatchComplicationSchedule.window(kind, snapshot: morning, from: gateNow, calendar: gateCalendar)
            let premiumWindow = WatchComplicationSchedule.window(kind, snapshot: gateSnapshot(.full, tier: .premium), from: gateNow, calendar: gateCalendar)
            #expect(lockedKind ? window == nil : window == premiumWindow, Comment(rawValue: kind.rawValue))
            let eveningRelevance = WatchComplicationSchedule.relevance(kind, at: gateEvening, snapshot: evening, calendar: gateCalendar)
            let eveningPremium = WatchComplicationSchedule.relevance(
                kind, at: gateEvening, snapshot: gateSnapshot(.full, tier: .premium, at: gateEvening), calendar: gateCalendar)
            #expect(lockedKind ? eveningRelevance == .idle : eveningRelevance == eveningPremium, Comment(rawValue: kind.rawValue))
        }
    }

    @Test func theComplicationViewsAndTheGalleryDrawTheLockedStateFromTheContent() throws {
        let views = RawDefaultsTests.code(
            try String(
                contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/NoctisWatchKit/WatchComplicationViews.swift"),
                encoding: .utf8))
        #expect(views.contains("content.isLocked"))
        for file in [
            "Watch/Widgets/NOCTISWatchWidgets.swift", "Watch/App/ComplicationGallery.swift", "Watch/App/WatchModel.swift", "Watch/App/WatchRootView.swift",
        ] {
            let code = RawDefaultsTests.code(try String(contentsOf: RawDefaultsTests.root.appendingPathComponent(file), encoding: .utf8))
            #expect(!code.contains("StoreKit") && !code.contains("FeatureTable"), Comment(rawValue: "\(file) decides the plan itself"))
        }
    }
}
