import Foundation
import SwiftData
import Testing
@testable import AppRoot
@testable import HomeFeature
@testable import HealthProviding
@testable import NoctisCore

struct AppRouteTests {
    @Test func everyRouteRoundTripsThroughItsURL() {
        for route in AppRoute.allCases {
            #expect(route.url.absoluteString == "noctis://\(route.rawValue)")
            #expect(AppRoute(url: route.url) == route)
        }
        #expect(AppRoute.allCases == [.home, .sleep, .recovery, .insights, .coach, .profile])
    }

    @Test func foreignOrUnknownURLsAreNotRoutes() throws {
        #expect(AppRoute(url: try #require(URL(string: "noctis://settings"))) == nil)
        #expect(AppRoute(url: try #require(URL(string: "https://example.com/home"))) == nil)
        #expect(AppRoute(url: try #require(URL(string: "NOCTIS://Recovery"))) == .recovery)
    }

    @Test func routesMapToTabsAndProfileLandsOnHome() {
        #expect(AppRoute.home.tab == .home)
        #expect(AppRoute.sleep.tab == .sleep)
        #expect(AppRoute.recovery.tab == .recovery)
        #expect(AppRoute.insights.tab == .insights)
        #expect(AppRoute.coach.tab == .coach)
        #expect(AppRoute.profile.tab == .home)
    }

    @Test func tabsMatchTheSpecInOrder() {
        #expect(AppTab.allCases.map(\.title) == ["Home", "Sleep", "Recovery", "Insights", "Coach"])
        #expect(AppTab.allCases.map(\.systemImage) == ["house", "moon.zzz", "heart", "lightbulb", "sparkles"])
    }

    @Test func openingARouteSelectsItsTabAndHomeIsTheDefault() throws {
        let container = try ModelContainer(for: Schema([UserProfileRecord.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let model = AppModel(healthProvider: MockHealthKitProvider(scenario: .empty), profileStore: ProfileStore(context: ModelContext(container)))
        #expect(model.selectedTab == .home)
        model.open(.recovery)
        #expect(model.selectedTab == .recovery)
        model.open(.profile)
        #expect(model.selectedTab == .home)
        #expect(model.homePath == [.profile])
        model.open(.home)
        #expect(model.homePath.isEmpty)
    }

    @Test func mockScenarioLaunchArgumentsParse() {
        #expect(DebugLaunchOptions(arguments: ["-mockScenario", "learning"]).mockScenario == .learning)
        #expect(DebugLaunchOptions(arguments: ["-mockScenario", "sleepOnly"]).mockScenario == .sleepOnly)
        #expect(DebugLaunchOptions(arguments: ["-useMockHealth"]).mockScenario == .full)
        #expect(DebugLaunchOptions(arguments: []).mockScenario == nil)
        #expect(DebugLaunchOptions(arguments: ["-noctisInitialRoute", "insights"]).initialRoute == .insights)
        #expect(DebugLaunchOptions(arguments: ["-mockUnauthorized"]).unauthorized)
        #expect(DebugLaunchOptions(arguments: ["-homeMode", "evening"]).homeMode == .evening)
        #expect(DebugLaunchOptions(arguments: ["-homeMode", "day"]).homeMode == .day)
        #expect(DebugLaunchOptions(arguments: []).homeMode == nil)
        #expect(DebugLaunchOptions(arguments: ["-mockLatency", "2.5"]).mockLatency == .milliseconds(2500))
        for scenario in MockScenario.allCases {
            #expect(DebugLaunchOptions(arguments: ["-mockScenario", scenario.rawValue]).mockScenario == scenario)
        }
    }
}
