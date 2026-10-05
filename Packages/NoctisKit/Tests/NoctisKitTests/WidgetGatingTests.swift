import Foundation
import SwiftData
import Testing

@testable import HealthProviding
@testable import NoctisCore
@testable import NoctisWidgetKit
@testable import PremiumKit

// The widgets by plan (APP_RULES.md R62): the small Home Screen widget and the circular Lock Screen widget are free; every other family is a calm locked view with no
// health number that opens the paywall through the one strict link. The decision is the feature table's, the plan is the one word in the snapshot, and a missing
// snapshot is free.

private enum GateFixture {
    static let morning = Fixture.date(2026, 9, 24, 10)
    static var calendar: Calendar { Fixture.calendar() }

    /// The widget's own entry for a sample snapshot on the given plan, as the real timeline would make it.
    static func entry(_ tier: Tier?, state: WidgetDataState = .full) -> WidgetEntryModel {
        let snapshot = tier.map { WidgetSamples.snapshot(state, now: morning, calendar: calendar).with(tier: $0) }
        return WidgetTimelineBuilder.entry(for: snapshot, at: morning, calendar: calendar)
    }
}

struct WidgetGateDecisionTests {
    @Test func theFamiliesAreExactlyTheOnesTheTableSays() {
        #expect(WidgetSurface.allCases.count == 6)
        let free: Set<WidgetSurface> = [.small, .lockCircular]
        for surface in WidgetSurface.allCases {
            #expect(surface.isLocked(in: .free) == !free.contains(surface), Comment(rawValue: surface.rawValue))
            #expect(!surface.isLocked(in: .premium), Comment(rawValue: "premium has every family: \(surface.rawValue)"))
            #expect(surface.isLocked(in: .free) != FeatureTable.isIncluded(surface.feature, in: .free))
        }
        #expect(WidgetSurface.small.feature == .widgetSmall && WidgetSurface.lockCircular.feature == .widgetLockCircular)
        for surface in [WidgetSurface.medium, .large, .lockRectangular, .lockInline] { #expect(surface.feature == .widgetMediumLargeAndOtherLock) }
    }

    @Test func eachFamilyPerTierIsLockedOrDrawnAsItAlwaysWas() {
        for tier in Tier.allCases {
            let entry = GateFixture.entry(tier)
            for surface in WidgetSurface.allCases {
                let locked = WidgetGate.lockedContent(entry, in: surface)
                #expect((locked != nil) == (tier == .free && surface != .small && surface != .lockCircular), Comment(rawValue: "\(tier) \(surface)"))
                #expect(WidgetGate.isLocked(entry, in: surface) == (locked != nil))
            }
        }
    }

    @Test func aMissingSnapshotIsFree() {
        let nothing = GateFixture.entry(nil)
        #expect(nothing.snapshot == nil)
        for surface in WidgetSurface.allCases {
            #expect(WidgetGate.isLocked(nothing, in: surface) == surface.isLocked(in: .free), Comment(rawValue: surface.rawValue))
        }
    }

    @Test func everyDataStateFollowsThePlanNotTheState() {
        let states: [WidgetDataState] = [.full, .sleepOnly, .learning(nightsSoFar: 3), .empty, .noPermission, .stale(hours: 14), .gap]
        for state in states {
            for surface in WidgetSurface.allCases {
                #expect(WidgetGate.isLocked(GateFixture.entry(.free, state: state), in: surface) == surface.isLocked(in: .free), Comment(rawValue: "\(state) \(surface)"))
                #expect(!WidgetGate.isLocked(GateFixture.entry(.premium, state: state), in: surface))
            }
        }
    }

    @Test func theGalleryPreviewKeepsTheUnlockedDesign() {
        let preview = WidgetTimelineBuilder.previewEntry(WidgetSamples.snapshot(.full, now: GateFixture.morning, calendar: GateFixture.calendar), at: GateFixture.morning, calendar: GateFixture.calendar)
        #expect(preview.isPreview && preview.snapshot?.tier == .premium, "a sample is the unlocked design, whatever the tier")
        #expect(WidgetSamples.snapshot(.full, now: GateFixture.morning, calendar: GateFixture.calendar, tier: .free).tier == .free)
        for surface in WidgetSurface.allCases {
            #expect(!WidgetGate.isLocked(preview, in: surface), Comment(rawValue: "the widget gallery shows what \(surface.rawValue) is, tagged Sample"))
        }
    }

    @Test func aLockedFamilyGivesTheSmartStackNothingToPromote() {
        let morningEntries = [GateFixture.entry(.premium)]
        var promoted = morningEntries[0]
        promoted.relevance = WidgetRelevanceScore(score: 100, duration: 3600)
        for tier in Tier.allCases {
            var entry = GateFixture.entry(tier)
            entry.relevance = promoted.relevance
            for surface in WidgetSurface.allCases {
                let result = WidgetGate.entries([entry], in: surface)[0]
                #expect(result.relevance == (surface.isLocked(in: tier) ? .idle : promoted.relevance), Comment(rawValue: "\(tier) \(surface)"))
                #expect(result.date == entry.date && result.snapshot == entry.snapshot, "nothing else changes")
            }
        }
    }
}

struct WidgetLockedContentTests {
    private let lockedSurfaces: [WidgetSurface] = [.medium, .large, .lockRectangular, .lockInline]

    @Test func aLockedWidgetSaysNOCTISPremiumAndOneLineOfWhatItShows() {
        #expect(WidgetLockedContent.title == "NOCTIS Premium")
        for surface in [WidgetSurface.medium, .large] { #expect(WidgetLockedContent(surface).line == "Your recovery and tonight's bedtime.") }
        #expect(WidgetLockedContent(.lockRectangular).line == "Recovery and bedtime on your Lock Screen.")
        #expect(WidgetLockedContent(.lockInline).line == nil, "one line of text has room for the title alone")
        for surface in lockedSurfaces {
            let content = WidgetLockedContent(surface)
            #expect(content.accessibilityLabel.hasPrefix("NOCTIS Premium") && content.accessibilityLabel.hasSuffix("Opens NOCTIS."), Comment(rawValue: content.accessibilityLabel))
        }
    }

    @Test func noLockedEntryCarriesAHealthNumber() {
        // Every locked family, on every sample, on the plan that locks it: nothing it says holds a digit, and nothing is built from the snapshot.
        for state in [WidgetDataState.full, .sleepOnly, .stale(hours: 14), .learning(nightsSoFar: 3)] {
            let entry = GateFixture.entry(.free, state: state)
            for surface in lockedSurfaces {
                let content = WidgetGate.lockedContent(entry, in: surface)
                #expect(content != nil)
                let words = [WidgetLockedContent.title, content?.line, content?.accessibilityLabel].compactMap { $0 }.joined(separator: " ")
                let hasDigit = words.contains { $0.isNumber }
                #expect(!hasDigit, Comment(rawValue: "\(surface) \(words)"))
                #expect(content == WidgetLockedContent(surface), "the same words whatever the snapshot holds")
            }
        }
    }

    @Test func theWordsAreCalmAndHonest() {
        for surface in WidgetSurface.allCases {
            let content = WidgetLockedContent(surface)
            for text in [WidgetLockedContent.title, content.line, content.accessibilityLabel].compactMap({ $0 }) {
                #expect(LockedCopy.pressure(in: text).isEmpty, Comment(rawValue: text))
            }
        }
    }

    @Test func theLockedViewDrawsOnlyTheContent() throws {
        let views = RawDefaultsTests.code(try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/NoctisWidgetKit/WidgetViews.swift"), encoding: .utf8))
        let start = try #require(views.range(of: "struct WidgetLockedView: View {"))
        let end = try #require(views.range(of: "struct WidgetMessageView: View {", range: start.upperBound..<views.endIndex))
        let locked = String(views[start.lowerBound..<end.lowerBound])
        for word in ["presentation", "snapshot", "WidgetPrivate", "NoctisMetric", "score", "asleep"] {
            #expect(!locked.contains(word), Comment(rawValue: "the locked view uses \(word)"))
        }
        // Both widgets decide with the one gate and draw the one locked view.
        #expect(views.components(separatedBy: "WidgetGate.lockedContent(entry, in: $0)").count == 3)
        #expect(views.components(separatedBy: "WidgetLockedView(content: locked)").count == 3)
    }

    @Test func theExtensionDecidesNothingItselfAndTheLockedTextIs12ptOrMore() throws {
        let extensionCode = RawDefaultsTests.code(try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("NoctisWidgets/NoctisWidgets.swift"), encoding: .utf8))
        #expect(extensionCode.contains("WidgetGate.entries(entries, in: $0)"))
        #expect(!extensionCode.contains("StoreKit") && !extensionCode.contains(".tier"), "the extension never reads or asks for the plan: the kit does")
        let views = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/NoctisWidgetKit/WidgetViews.swift"), encoding: .utf8)
        let locked = try #require(views.range(of: "struct WidgetLockedView: View {"))
        for size in views[locked.lowerBound...].prefix(2600).components(separatedBy: "noctisFont(").dropFirst().compactMap({ Int($0.prefix { $0.isNumber }) }) { #expect(size >= 12) }
    }
}

struct PremiumLinkTests {
    private let hostile = [
        "noctis://premium?context=evil", "noctis://premium?context=widgets&context=watch", "noctis://premium?context=widgets&x=1", "noctis://premium?x=widgets",
        "noctis://premium?context=", "noctis://premium?context", "noctis://premium?=widgets", "noctis://premium?context=%77idgets", "noctis://premium?context=Widgets",
        "noctis://premium?context=widgets%20", "noctis://premium?context=widgets%00", "noctis://premium?context=whatPremiumIncludes", "noctis://premium?context=recovery30D",
        "noctis://premium?context=coachQuestions;drop", "noctis://premium?context=general", "noctis://premium?context=widgets&", "noctis://premium?&context=widgets",
        "noctis://premium?context=widgets=1", "noctis://premium?context=https://evil.example", "noctis://premium?" + String(repeating: "a", count: 5000),
        "noctis://premium/extra", "noctis://premium/../recovery", "noctis://premium#widgets", "noctis://premium?context=widgets#x", "noctis://user@premium", "noctis://user:pw@premium",
        "noctis://premium:8080", "noctis:premium", "noctis:///premium", "noctis://premium.evil.example", "noctis://PREMIUM.evil.example", "noctis://%70remium", "noctis://premium%20",
        "noctis://pr\u{0435}mium", "noctis://premiums", "noctis://premium//", "https://premium", "http://noctis/premium", "noctisx://premium", "xnoctis://premium",
        "noctis://paywall", "noctis://upgrade", "noctis://subscribe", "noctis://purchase", "noctis://buy",
    ]

    @Test func everyAllowedContextRoundTripsAsOneShortURL() throws {
        #expect(PremiumLink.allowedContexts == [.general, .widgets, .watch, .siri, .windDown, .sounds, .coachQuestions])
        #expect(PremiumLink(context: .general).url.absoluteString == "noctis://premium")
        for context in PremiumLink.allowedContexts {
            let link = PremiumLink(context: context)
            let expected = context == .general ? "noctis://premium" : "noctis://premium?context=\(context.rawValue)"
            #expect(link.url.absoluteString == expected)
            #expect(PremiumLink(url: link.url) == link)
            #expect(WidgetURLRouter.destination(for: link.url) == .paywall(context))
        }
        #expect(WidgetLockedContent(.medium).link.absoluteString == "noctis://premium?context=widgets")
    }

    @Test func aContextOffTheWhitelistIsTheGeneralOne() {
        for context in PaywallContext.allCases where !PremiumLink.allowedContexts.contains(context) {
            #expect(PremiumLink(context: context).context == .general, Comment(rawValue: context.rawValue))
            #expect(PremiumLink(context: context).url.absoluteString == "noctis://premium")
        }
    }

    @Test func nothingButTheLinkItselfIsAccepted() {
        for text in hostile {
            guard let url = URL(string: text) else { continue }
            #expect(PremiumLink(url: url) == nil, Comment(rawValue: "\(text.prefix(70)) is accepted as the premium link"))
            #expect(WidgetURLRouter.destination(for: url) == nil, Comment(rawValue: "\(text.prefix(70)) opens something"))
        }
    }

    @Test func caseAndATrailingSlashDoNotMatterAsForTheOtherLinks() {
        for text in ["NOCTIS://PREMIUM", "noctis://premium/", "noctis://premium/?context=widgets", "Noctis://Premium?context=siri"] {
            #expect(URL(string: text).flatMap(PremiumLink.init(url:)) != nil, Comment(rawValue: text))
        }
    }

    @Test func theLinkIsNotAScreenAndTheFiveScreenLinksAreStillTheirOwn() {
        let url = PremiumLink(context: .widgets).url
        #expect(WidgetLink(url: url) == nil && WidgetURLRouter.route(for: url) == nil, "it opens no screen")
        #expect(WidgetLink.allCases.count == 5)
        for link in WidgetLink.allCases {
            #expect(PremiumLink(url: link.url) == nil)
            #expect(WidgetURLRouter.destination(for: link.url) == .screen(WidgetURLRouter.route(for: link)))
        }
        // None of the screen links' hostile inputs becomes the paywall.
        for text in ["noctis://recovery?context=widgets", "noctis://tonight?context=widgets", "noctis://wind-down?context=windDown"] {
            #expect(URL(string: text).flatMap(WidgetURLRouter.destination(for:)) == nil, Comment(rawValue: text))
        }
    }
}

@MainActor
struct PaywallFromOutsideTests {
    private func model(_ tier: Tier?, onboarded: Bool = true) async throws -> AppModel {
        let container = try ModelContainer(for: Schema([UserProfileRecord.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let model = AppModel(healthProvider: MockHealthKitProvider(scenario: .empty), profileStore: ProfileStore(context: ModelContext(container)))
        model.featureGate = tier.map { FeatureGate(tier: $0) }
        if onboarded { await model.completeOnboarding(UserProfileSnapshot()) }
        return model
    }

    @Test func aTapOnALockedWidgetOpensThePaywallForAFreePersonWithItsContext() async throws {
        let free = try await model(.free)
        free.open(.paywall(.widgets))
        #expect(free.paywall == .widgets)
        free.dismissPaywall()
        free.open(WidgetURLRouter.destination(for: PremiumLink(context: .siri).url) ?? .screen(.home))
        #expect(free.paywall == .siri)
    }

    @Test func aPremiumPersonWhoTapsAStaleLockedWidgetLandsOnHome() async throws {
        let premium = try await model(.premium)
        premium.open(.screen(.sleep()))
        premium.open(.paywall(.widgets))
        #expect(premium.paywall == nil, "nothing to sell to someone who already has it")
        #expect(premium.selectedTab == .home)
    }

    @Test func theLinkNeverOpensThePaywallBeforeSetupIsFinished() async throws {
        let fresh = try await model(.free, onboarded: false)
        fresh.open(.paywall(.widgets))
        #expect(fresh.paywall == nil, "never on launch, and never over onboarding (R58)")
    }

    @Test func aScreenLinkStillOpensItsScreen() async throws {
        let free = try await model(.free)
        free.open(.screen(.recovery()))
        #expect(free.selectedTab == .recovery && free.paywall == nil)
    }
}
