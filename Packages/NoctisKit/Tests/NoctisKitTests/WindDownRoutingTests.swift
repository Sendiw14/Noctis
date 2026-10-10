import Foundation
import HealthProviding
import SwiftData
import Testing

@testable import NightFeature
@testable import NoctisCore

// How the wind-down is reached (APP_RULES.md R32): Tonight, Home's evening card and the evening notification
// all open the pre-start state; only the Siri-ready route begins at once; each way out returns to where
// the person came from; and nothing says "Coming soon" any more.

@MainActor
struct WindDownRoutingTests {
    static func model() throws -> AppModel {
        let container = try ModelContainer(for: Schema([UserProfileRecord.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return AppModel(healthProvider: MockHealthKitProvider(scenario: .empty), profileStore: ProfileStore(context: ModelContext(container)))
    }

    @Test func theEveningNotificationOpensTheWindDownWithoutStartingItForPremium() {
        #expect(NoctisNotification.route(for: NoctisNotification.windDown, tier: .premium) == .windDown(autostart: false))
        #expect(NoctisNotification.route(for: NoctisNotification.morningSummary, tier: .premium) == nil)
        // The weekly reminder opens the latest weekly review, on either plan (its cover is free); the morning one just opens the app.
        #expect(NoctisNotification.route(for: NoctisNotification.weeklyReview, tier: .premium) == .review(kind: .weekly))
        #expect(NoctisNotification.route(for: NoctisNotification.weeklyReview, tier: .free) == .review(kind: .weekly))
        #expect(NoctisNotification.route(for: "something.else", tier: .premium) == nil)
    }

    @Test func aNotificationBuildsItsOwnPathTonightThenTheWindDown() throws {
        let model = try Self.model()
        model.selectedTab = .coach
        let route = try #require(NoctisNotification.route(for: NoctisNotification.windDown, tier: .premium))
        model.open(route)
        #expect(model.selectedTab == .home)
        #expect(model.homePath == [.tonight, .windDown(autostart: false)])
    }

    @Test func homesEveningCardStacksTheWindDownOnHomeSoNotNowReturnsThere() throws {
        let model = try Self.model()
        model.push(.windDown(autostart: false))
        #expect(model.selectedTab == .home)
        #expect(model.homePath == [.windDown(autostart: false)])
        // "Not now" is a dismiss: the screen is popped, and Home is what is left.
        model.homePath.removeLast()
        #expect(model.homePath.isEmpty)
    }

    @Test func tonightsButtonStacksTheWindDownOnTonight() throws {
        let model = try Self.model()
        model.open(.tonight)
        model.push(.windDown(autostart: false))
        #expect(model.homePath == [.tonight, .windDown(autostart: false)])
        model.homePath.removeLast()
        #expect(model.homePath == [.tonight])
    }

    @Test func aSecondTapOnTheSameRouteDoesNothing() throws {
        let model = try Self.model()
        model.push(.windDown(autostart: false))
        model.push(.windDown(autostart: false))
        #expect(model.homePath == [.windDown(autostart: false)])
        model.push(.sounds)
        #expect(model.homePath == [.windDown(autostart: false), .sounds])
    }

    @Test func theBedtimePillAndTheTabBarKnowWhenTheWindDownIsTheScreenShowing() throws {
        let model = try Self.model()
        #expect(!model.isWindDownShowing)
        model.open(.tonight)
        #expect(!model.isWindDownShowing, "Tonight is not the wind-down")
        model.push(.windDown(autostart: false))
        #expect(model.isWindDownShowing)
        model.selectedTab = .coach
        #expect(!model.isWindDownShowing, "on another tab, Home's stack is not what is showing")
        model.selectedTab = .home
        #expect(model.isWindDownShowing)
        model.homePath.removeLast()
        #expect(!model.isWindDownShowing)
        model.open(.windDown(autostart: true))
        #expect(model.isWindDownShowing)
        model.open(.home)
        #expect(!model.isWindDownShowing)
    }

    @Test func pushingFromAnotherTabComesToHome() throws {
        let model = try Self.model()
        model.selectedTab = .insights
        model.push(.windDown(autostart: false))
        #expect(model.selectedTab == .home)
    }

    @Test func onlyTheSiriReadyRouteBeginsASessionAndEveryOtherWayInOpensPreStart() {
        // Every entry point's route, built the way the code builds it: none starts a session.
        let entryPoints: [AppRoute] = [
            .windDown(),
            .windDown(autostart: false),
            NoctisNotification.route(for: NoctisNotification.windDown, tier: .premium) ?? .home,
            AppRoute(name: "wind-down") ?? .home,
            AppRoute(url: URL(string: "noctis://wind-down") ?? URL(fileURLWithPath: "/")) ?? .home,
        ]
        for route in entryPoints { #expect(route == .windDown(autostart: false), Comment(rawValue: "\(route)")) }
        #expect(AppRoute(url: URL(string: "noctis://wind-down?autostart=1") ?? URL(fileURLWithPath: "/")) == .windDown(autostart: true))
    }

    @Test func theScreenOpensIdleForPreStartAndRunningForTheSiriReadyRoute() {
        let idle = WindDownViewModelTests.make()
        idle.model.prepare(autostart: false)
        #expect(idle.model.state == .idle)
        let started = WindDownViewModelTests.make()
        started.model.prepare(autostart: true)
        #expect(started.model.state == .running)
    }
}

nonisolated struct WindDownCopyAndRoadmapTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func noEntryPointStillShowsAComingSoonScreenForTheWindDownOrItsParts() throws {
        let sources = Self.root.appendingPathComponent("Packages/NoctisKit/Sources")
        let home = try String(contentsOf: sources.appendingPathComponent("HomeFeature/HomeView.swift"), encoding: .utf8)
        // The routes' destinations in Home's stack: the real screens.
        let windDownCase = try #require(home.range(of: "case .windDown(let autostart):"))
        let after = home[windDownCase.upperBound...].prefix(200)
        #expect(after.contains("windDownScreen(autostart)") && !after.contains("ComingSoon"))
        let soundsCase = try #require(home.range(of: "case .sounds:"))
        #expect(home[soundsCase.upperBound...].prefix(120).contains("soundsScreen()"))
        // Neither the roadmap nor the code describes the wind-down as unbuilt.
        let roadmap = try String(contentsOf: Self.root.appendingPathComponent("ROADMAP.md"), encoding: .utf8)
        for line in roadmap.split(separator: "\n") where line.lowercased().contains("coming soon") {
            let lowered = line.lowercased()
            #expect(!lowered.contains("wind-down") && !lowered.contains("sounds") && !lowered.contains("breathing") && !lowered.contains("meditation") && !lowered.contains("reflect"), Comment(rawValue: String(line)))
        }
    }

    @Test func theRoadmapKeepsTheWindDownPassesThatAreNotBuiltAndNoLongerListsThoseThatAre() throws {
        let roadmap = try String(contentsOf: Self.root.appendingPathComponent("ROADMAP.md"), encoding: .utf8)
        for entry in ["Adaptive wind-down lengths", "Recorded, voice-guided meditations"] {
            #expect(roadmap.contains(entry), Comment(rawValue: "ROADMAP.md lost \"\(entry)\""))
        }
        // The Live Activity, the Control Center controls and the App Intents are built (R47 to R49): QA found the roadmap still calling them
        // "Not started" (QA_LEDGER.md), so they must not come back as unbuilt.
        for entry in ["Live Activity and Dynamic Island", "Control Center control", "StartWindDownIntent", "PlaySleepSoundsIntent"] {
            #expect(!roadmap.contains(entry), Comment(rawValue: "ROADMAP.md lists \"\(entry)\" as unbuilt, and it is built"))
        }
        // The wind-down's gating is built now (R57, R61): the table decides it, so the roadmap no longer lists it.
        #expect(!roadmap.contains("Free vs Premium gating for the wind-down"))
    }

    @Test func theTwoButtonsSayTheSameWords() throws {
        let sources = Self.root.appendingPathComponent("Packages/NoctisKit/Sources")
        let tonight = try String(contentsOf: sources.appendingPathComponent("NightFeature/TonightScreen.swift"), encoding: .utf8)
        let home = try String(contentsOf: sources.appendingPathComponent("HomeFeature/HomeView.swift"), encoding: .utf8)
        #expect(tonight.contains("\"Start wind-down\"") && home.contains("\"Start wind-down\""))
        // Both go through the same call, so the wind-down returns to where it was opened from.
        #expect(tonight.contains("model.push(.windDown(autostart: false))"))
        #expect(home.contains("model.push(.windDown(autostart: false))"))
        #expect(!tonight.contains("model.open(.windDown") && !home.contains("model.open(.windDown"))
    }
}
