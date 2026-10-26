import Foundation
import SwiftData
import Testing

@testable import HealthProviding
@testable import NoctisCore

struct SettingsRouteTests {
    private func route(_ text: String) throws -> AppRoute? { AppRoute(url: try #require(URL(string: text))) }

    @Test func settingsHasAURLAndEveryPageHasOneToo() throws {
        #expect(AppRoute.settings().url.absoluteString == "noctis://settings")
        #expect(AppRoute.settings(section: .notifications).url.absoluteString == "noctis://settings?section=notifications")
        #expect(AppRoute.settings(section: .healthData).url.absoluteString == "noctis://settings?section=health-data")
        for page in SettingsPage.allCases {
            let route = AppRoute.settings(section: page)
            #expect(AppRoute(url: route.url) == route, "\(page)")
        }
        #expect(try route("noctis://settings?section=health-data") == .settings(section: .healthData))
        #expect(try route("noctis://settings?section=Wind_Down") == .settings(section: .windDown))
    }

    @Test func anUnreadableSectionOpensTheList() throws {
        #expect(try route("noctis://settings?section=billing") == .settings(section: .root))
        #expect(try route("noctis://settings") == .settings(section: .root))
    }

    @Test func aLaunchArgumentNamesAPageAfterAColon() {
        #expect(AppRoute(name: "settings") == .settings(section: .root))
        #expect(AppRoute(name: "settings:notifications") == .settings(section: .notifications))
        #expect(AppRoute(name: "settings:health-data") == .settings(section: .healthData))
        #expect(AppRoute(name: "settings:nope") == .settings(section: .root))
    }

    @Test func settingsLivesOnTheHomeTab() {
        #expect(AppRoute.settings(section: .about).tab == .home)
        #expect(AppRoute.profile.tab == .home)
    }

    @MainActor
    @Test func openingSettingsBuildsTheStackBackToProfileAndHome() throws {
        let container = try ModelContainer(for: Schema([UserProfileRecord.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let model = AppModel(healthProvider: MockHealthKitProvider(scenario: .empty), profileStore: ProfileStore(context: ModelContext(container)))
        model.selectedTab = .coach
        model.open(.settings(section: .notifications))
        #expect(model.selectedTab == .home)
        #expect(model.homePath == [.profile, .settings(.root), .settings(.notifications)], "back goes to the list, then Profile, then Home")
        model.open(.settings())
        #expect(model.homePath == [.profile, .settings(.root)])
        model.open(.settings(section: .healthData))
        #expect(model.homePath.last == .settings(.healthData))
        model.open(.profile)
        #expect(model.homePath == [.profile])
    }
}

/// Every screen that can have no Health data says so with a way to Settings, Health data (APP_RULES.md R36, R39): a
/// file that offers "Open Health" or "Connect Apple Health" as a state's action also holds the link.
nonisolated struct HealthStateLinkTests {
    static let sources = RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources")
    static let features = ["HomeFeature", "SleepFeature", "RecoveryFeature", "InsightsFeature", "CoachFeature"]

    static func swiftFiles(in feature: String) -> [URL] {
        let folder = sources.appendingPathComponent(feature)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".swift") }.map { folder.appendingPathComponent($0) }
    }

    @Test func everyStateWithAHealthActionAlsoLinksToHealthDataSettings() throws {
        var checked = 0
        for feature in Self.features {
            for file in Self.swiftFiles(in: feature) {
                let text = try String(contentsOf: file, encoding: .utf8)
                let actions =
                    text.components(separatedBy: "NoctisTextButton(\"Open Health\"").count - 1
                    + text.components(separatedBy: "NoctisCTA(\"Connect Apple Health\"").count - 1
                guard actions > 0 else { continue }
                let links = text.components(separatedBy: "HealthDataSettingsLink()").count - 1
                #expect(links >= 2, Comment(rawValue: "\(file.lastPathComponent): \(actions) Health actions, \(links) links"))
                checked += 1
            }
        }
        #expect(checked == 5, "Home, Sleep, Recovery, Insights and Coach each have one state view")
    }
}
