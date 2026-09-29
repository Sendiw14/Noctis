import Foundation
import SwiftData
import Testing
@testable import AppRoot
@testable import HomeFeature
@testable import HealthProviding
@testable import NoctisCore

struct AppRouteTests {
    @Test func everyRouteRoundTripsThroughItsURL() {
        for route in AppRoute.destinations {
            #expect(route.url.absoluteString == "noctis://\(route.name)")
            #expect(AppRoute(url: route.url) == route)
            #expect(AppRoute(name: route.name) == route)
        }
        #expect(AppRoute.destinations == [.home, .sleep(), .recovery, .insights, .coach, .profile])
        #expect(AppRoute.destinations.map(\.name) == ["home", "sleep", "recovery", "insights", "coach", "profile"])
    }

    @Test func sleepCarriesANightAndARangeThroughItsURL() throws {
        let night = Date(timeIntervalSince1970: 1_790_000_000)
        let route = AppRoute.sleep(night: night, range: .week)
        #expect(route.url.absoluteString == "noctis://sleep?range=week&night=\(night.formatted(.iso8601))")
        #expect(AppRoute(url: route.url) == route)
        // Day is the default range, so it isn't spelled out.
        #expect(AppRoute.sleep(night: night, range: .day).url.absoluteString == "noctis://sleep?night=\(night.formatted(.iso8601))")
        #expect(AppRoute.sleep(night: nil, range: .month).url.absoluteString == "noctis://sleep?range=month")
        #expect(AppRoute(url: route.url)?.tab == .sleep)
    }

    @Test func sleepURLsAreReadLeniently() throws {
        func route(_ text: String) throws -> AppRoute? { AppRoute(url: try #require(URL(string: text))) }
        #expect(try route("noctis://sleep") == .sleep(night: nil, range: .day))
        #expect(try route("noctis://sleep?range=MONTH") == .sleep(night: nil, range: .month))
        // What can't be read is left out: Sleep opens on its newest night, on Day.
        #expect(try route("noctis://sleep?range=year&night=yesterday") == .sleep(night: nil, range: .day))
        // A plain date is noon of that day: the night that evening starts.
        let plain = try #require(try route("noctis://sleep?night=2026-09-28"))
        guard case .sleep(let night?, _) = plain else { Issue.record("expected a night"); return }
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour], from: night)
        #expect((parts.year, parts.month, parts.day, parts.hour) == (2026, 9, 28, 12))
        // Other routes ignore a query.
        #expect(try route("noctis://recovery?range=week") == .recovery)
    }

    @Test func aLaunchNameCanCarryASleepRange() {
        #expect(AppRoute(name: "sleep") == .sleep(night: nil, range: .day))
        #expect(AppRoute(name: "sleep:week") == .sleep(night: nil, range: .week))
        #expect(AppRoute(name: "Sleep:Month") == .sleep(night: nil, range: .month))
        #expect(AppRoute(name: "sleep:decade") == .sleep(night: nil, range: .day))
        #expect(AppRoute(name: "settings") == nil)
    }

    @Test func foreignOrUnknownURLsAreNotRoutes() throws {
        #expect(AppRoute(url: try #require(URL(string: "noctis://settings"))) == nil)
        #expect(AppRoute(url: try #require(URL(string: "https://example.com/home"))) == nil)
        #expect(AppRoute(url: try #require(URL(string: "NOCTIS://Recovery"))) == .recovery)
    }

    @Test func routesMapToTabsAndProfileLandsOnHome() {
        #expect(AppRoute.home.tab == .home)
        #expect(AppRoute.sleep().tab == .sleep)
        #expect(AppRoute.sleep(night: Date(), range: .month).tab == .sleep)
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

    @Test func openingSleepHandsTheTabItsDestinationOnceAndAPressedTabIsARetap() throws {
        let container = try ModelContainer(for: Schema([UserProfileRecord.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let model = AppModel(healthProvider: MockHealthKitProvider(scenario: .empty), profileStore: ProfileStore(context: ModelContext(container)))
        #expect(model.sleepDestination == nil && model.tabRetap == nil)
        let night = Date(timeIntervalSince1970: 1_790_000_000)
        model.open(.sleep(night: night, range: .week))
        #expect(model.selectedTab == .sleep)
        let destination = try #require(model.takeSleepDestination())
        #expect(destination.night == night && destination.range == .week)
        #expect(model.takeSleepDestination() == nil, "it's handed over once")
        // The same place twice is still a change the tab can see.
        model.open(.sleep())
        let first = model.sleepDestination
        model.open(.sleep())
        #expect(model.sleepDestination != first)
        // Other routes carry nothing for Sleep.
        _ = model.takeSleepDestination()
        model.open(.recovery)
        #expect(model.sleepDestination == nil)
        model.retap(.sleep)
        let one = model.tabRetap
        model.retap(.sleep)
        #expect(model.tabRetap?.tab == .sleep && model.tabRetap != one)
    }

    @Test func mockScenarioLaunchArgumentsParse() {
        #expect(DebugLaunchOptions(arguments: ["-mockScenario", "learning"]).mockScenario == .learning)
        #expect(DebugLaunchOptions(arguments: ["-mockScenario", "sleepOnly"]).mockScenario == .sleepOnly)
        #expect(DebugLaunchOptions(arguments: ["-useMockHealth"]).mockScenario == .full)
        #expect(DebugLaunchOptions(arguments: []).mockScenario == nil)
        #expect(DebugLaunchOptions(arguments: ["-noctisInitialRoute", "insights"]).initialRoute == .insights)
        #expect(DebugLaunchOptions(arguments: ["-noctisInitialRoute", "sleep"]).initialRoute == .sleep())
        #expect(DebugLaunchOptions(arguments: ["-noctisInitialRoute", "sleep:week"]).initialRoute == .sleep(night: nil, range: .week))
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
