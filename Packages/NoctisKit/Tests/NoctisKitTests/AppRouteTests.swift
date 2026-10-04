import Foundation
import SwiftData
import Testing
@testable import AppRoot
@testable import HomeFeature
@testable import HealthProviding
@testable import InsightsKit
@testable import NoctisCore

struct AppRouteTests {
    @Test func everyRouteRoundTripsThroughItsURL() {
        for route in AppRoute.destinations {
            #expect(route.url.absoluteString == "noctis://\(route.name)")
            #expect(AppRoute(url: route.url) == route)
            #expect(AppRoute(name: route.name) == route)
        }
        #expect(AppRoute.destinations == [.home, .sleep(), .recovery(), .insights(), .coach(), .profile, .settings(), .tonight, .windDown(), .sounds, .alarm])
        #expect(AppRoute.destinations.map { $0.name } == ["home", "sleep", "recovery", "insights", "coach", "profile", "settings", "tonight", "wind-down", "sounds", "alarm"])
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
        #expect(try route("noctis://insights?range=week") == .insights())
    }

    @Test func recoveryCarriesARangeAndAFactorThroughItsURL() throws {
        let route = AppRoute.recovery(range: .month, factor: .hrv)
        #expect(route.url.absoluteString == "noctis://recovery?range=30d&factor=hrv")
        #expect(AppRoute(url: route.url) == route)
        #expect(AppRoute.recovery(range: .quarter, factor: nil).url.absoluteString == "noctis://recovery?range=90d")
        #expect(AppRoute.recovery(range: .today, factor: .sleepConsistency).url.absoluteString == "noctis://recovery?factor=sleepConsistency")
        #expect(AppRoute(url: try #require(URL(string: "noctis://recovery?range=7D&factor=RESTINGHEARTRATE"))) == .recovery(range: .week, factor: .restingHeartRate))
        // What can't be read is left out: Today, no factor.
        #expect(AppRoute(url: try #require(URL(string: "noctis://recovery?range=year&factor=mood"))) == .recovery())
        #expect(AppRoute(name: "recovery:30d") == .recovery(range: .month, factor: nil))
        #expect(AppRoute(name: "recovery:decade") == .recovery())
        for segment in RecoverySegment.allCases { #expect(RecoverySegment(token: segment.token) == segment) }
    }

    @Test func openingRecoveryHandsTheTabItsDestinationAndPushesAFactorsPage() throws {
        let container = try ModelContainer(for: Schema([UserProfileRecord.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let model = AppModel(healthProvider: MockHealthKitProvider(scenario: .empty), profileStore: ProfileStore(context: ModelContext(container)))
        model.open(.recovery(range: .month, factor: .hrv))
        #expect(model.selectedTab == .recovery)
        #expect(model.recoveryPath == [.factor(.hrv, range: .month)])
        let destination = try #require(model.takeRecoveryDestination())
        #expect(destination.segment == .month && destination.factor == .hrv)
        #expect(model.takeRecoveryDestination() == nil, "it's handed over once")
        // 7D and Today go with the 14-night chart.
        model.open(.recovery(range: .week, factor: .restingHeartRate))
        #expect(model.recoveryPath == [.factor(.restingHeartRate, range: .fortnight)])
        // Without a factor the stack goes back to the root.
        model.open(.recovery(range: .quarter, factor: nil))
        #expect(model.recoveryPath.isEmpty)
        #expect(model.takeRecoveryDestination()?.segment == .quarter)
    }

    @Test func aLaunchNameCanCarryASleepRange() {
        #expect(AppRoute(name: "sleep") == .sleep(night: nil, range: .day))
        #expect(AppRoute(name: "sleep:week") == .sleep(night: nil, range: .week))
        #expect(AppRoute(name: "Sleep:Month") == .sleep(night: nil, range: .month))
        #expect(AppRoute(name: "sleep:decade") == .sleep(night: nil, range: .day))
        #expect(AppRoute(name: "paywall") == nil)
    }

    @Test func foreignOrUnknownURLsAreNotRoutes() throws {
        #expect(AppRoute(url: try #require(URL(string: "noctis://paywall"))) == nil)
        #expect(AppRoute(url: try #require(URL(string: "https://example.com/home"))) == nil)
        #expect(AppRoute(url: try #require(URL(string: "NOCTIS://Recovery"))) == .recovery())
    }

    @Test func routesMapToTabsAndProfileLandsOnHome() {
        #expect(AppRoute.home.tab == .home)
        #expect(AppRoute.sleep().tab == .sleep)
        #expect(AppRoute.sleep(night: Date(), range: .month).tab == .sleep)
        #expect(AppRoute.recovery().tab == .recovery)
        #expect(AppRoute.recovery(range: .month, factor: .hrv).tab == .recovery)
        #expect(AppRoute.insights().tab == .insights)
        #expect(AppRoute.insights(category: .heart).tab == .insights)
        #expect(AppRoute.insight(id: "bedtimeShift-3fa9c2d1").tab == .insights)
        #expect(AppRoute.coach().tab == .coach)
        #expect(AppRoute.profile.tab == .home)
    }

    // MARK: - Insights routes

    private let insightID = "bedtimeShift-3fa9c2d1"

    private func route(_ text: String) throws -> AppRoute? { AppRoute(url: try #require(URL(string: text))) }

    @Test func insightsCarriesAChipThroughItsURL() throws {
        #expect(try route("noctis://insights?category=sleep") == .insights(category: .sleep))
        #expect(try route("noctis://insights?category=longTerm") == .insights(category: .longTerm))
        #expect(try route("noctis://insights?category=long-term") == .insights(category: .longTerm))
        #expect(try route("noctis://insights?category=HEART") == .insights(category: .heart))
        #expect(try route("noctis://insights?category=nonsense") == .insights(), "an unknown chip is All")
        #expect(try route("noctis://insights") == .insights())
        for category in InsightCategory.allCases {
            let route = AppRoute.insights(category: category)
            #expect(AppRoute(url: route.url) == route)
        }
        #expect(AppRoute.insights(category: .sleep).url.absoluteString == "noctis://insights?category=sleep")
        #expect(AppRoute.insights().url.absoluteString == "noctis://insights")
    }

    @Test func insightOpensOnePageByItsID() throws {
        #expect(try route("noctis://insight?id=\(insightID)") == .insight(id: insightID))
        #expect(AppRoute.insight(id: insightID).url.absoluteString == "noctis://insight?id=\(insightID)")
        #expect(AppRoute(url: AppRoute.insight(id: insightID).url) == .insight(id: insightID))
        #expect(AppRoute.insight(id: insightID).name == "insight")
    }

    @Test func anInsightIDIsATypeAndEightHexDigits() {
        #expect(AppRoute(url: URL(string: "noctis://insight")!) == nil)
        #expect(AppRoute(url: URL(string: "noctis://insight?id=")!) == nil)
        #expect(AppRoute(url: URL(string: "noctis://insight?id=bedtimeShift")!) == nil)
        #expect(AppRoute(url: URL(string: "noctis://insight?id=nonsense-3fa9c2d1")!) == nil, "no such type")
        #expect(AppRoute(url: URL(string: "noctis://insight?id=bedtimeShift-3fa9c2d")!) == nil, "seven digits")
        #expect(AppRoute(url: URL(string: "noctis://insight?id=bedtimeShift-3fa9c2dz")!) == nil, "not hex")
        #expect(AppRoute(url: URL(string: "noctis://insight?id=../../etc")!) == nil)
        for type in InsightType.allCases {
            #expect(AppRoute(url: URL(string: "noctis://insight?id=\(type.rawValue)-0123abcd")!) == .insight(id: "\(type.rawValue)-0123abcd"))
        }
    }

    @Test func launchArgumentsNameAChipAndAnInsight() {
        #expect(AppRoute(name: "insights:sleep") == .insights(category: .sleep))
        #expect(AppRoute(name: "insights:longTerm") == .insights(category: .longTerm))
        #expect(AppRoute(name: "insights:whatever") == .insights())
        // An insight's id keeps its case.
        #expect(AppRoute(name: "insight:\(insightID)") == .insight(id: insightID))
        #expect(AppRoute(name: "insight:nope") == nil)
        #expect(AppRoute(name: "insight") == nil)
    }

    @Test func openingInsightsRoutes() throws {
        let container = try ModelContainer(for: Schema([UserProfileRecord.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let model = AppModel(healthProvider: MockHealthKitProvider(scenario: .empty), profileStore: ProfileStore(context: ModelContext(container)))
        model.open(.insights(category: .heart))
        #expect(model.selectedTab == .insights)
        #expect(model.insightsPath.isEmpty)
        #expect(model.takeInsightsDestination()?.category == .heart)
        #expect(model.takeInsightsDestination() == nil, "it's handed over once")
        // The same chip twice is still a change the tab can see.
        model.open(.insights(category: .heart))
        let first = model.insightsDestination
        model.open(.insights(category: .heart))
        #expect(model.insightsDestination != first)
        // One insight's page is pushed over the tab, whichever tab asked.
        model.open(.home)
        model.open(.insight(id: insightID))
        #expect(model.selectedTab == .insights)
        #expect(model.insightsPath == [.insight(id: insightID)])
        // The tab's own chip route clears a page that was open.
        model.open(.insights())
        #expect(model.insightsPath.isEmpty)
    }

    @Test func tabsMatchTheSpecInOrder() {
        #expect(AppTab.allCases.map(\.title) == ["Home", "Sleep", "Recovery", "Insights", "Coach"])
        #expect(AppTab.allCases.map(\.systemImage) == ["house", "moon.zzz", "heart", "lightbulb", "sparkles"])
    }

    @Test func openingARouteSelectsItsTabAndHomeIsTheDefault() throws {
        let container = try ModelContainer(for: Schema([UserProfileRecord.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let model = AppModel(healthProvider: MockHealthKitProvider(scenario: .empty), profileStore: ProfileStore(context: ModelContext(container)))
        #expect(model.selectedTab == .home)
        model.open(.recovery())
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
        model.open(.recovery())
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
        #expect(DebugLaunchOptions(arguments: ["-noctisInitialRoute", "insights"]).initialRoute == .insights())
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
