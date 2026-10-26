import Foundation
import Testing

@testable import NoctisCore
@testable import OnboardingFeature
@testable import QACatalog
import RecoveryKit

// QA part 3 (QA_COVERAGE.md, APP_RULES.md R67): the catalog of every screen is one list, with no entry twice, every route of the app on it, and every
// launch flag it names one the app reads. QAMatrixTests (the UI tests) visits what this list says; a screen that is not on the list is not in the matrix.

struct ScreenCatalogTests {
    /// The repository: Tests/NoctisKitTests -> Tests -> NoctisKit -> Packages -> repository.
    private nonisolated static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Every `AppRoute` case: the switch has no default, so a new case does not compile until it is listed here and given an entry.
    private static let allRoutes: [AppRoute] = {
        let samples: [AppRoute] = [
            .home, .sleep(), .recovery(), .insights(), .insight(id: "bedtimeShift-3fa9c2d1"), .reviews, .review(kind: .weekly), .coach(), .profile, .settings(),
            .tonight, .windDown(), .sounds, .alarm,
        ]
        for route in samples {
            switch route {
            case .home, .sleep, .recovery, .insights, .insight, .reviews, .review, .coach, .profile, .settings, .tonight, .windDown, .sounds, .alarm: break
            }
        }
        return samples
    }()

    @Test func noTwoEntriesShareAnIdAndEveryEntryIsNamed() {
        let ids = ScreenCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicates: \(Dictionary(grouping: ids, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted())")
        for screen in ScreenCatalog.all {
            #expect(!screen.title.isEmpty, "\(screen.id) has no title")
            #expect(screen.id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }, "\(screen.id) is not a plain dotted name")
            // Privacy Center and Data management are Settings pages the brief files under privacy.
            #expect(screen.id.hasPrefix(screen.area.rawValue) || screen.area == .privacy, "\(screen.id) is not under its area \(screen.area.rawValue)")
        }
    }

    @Test func everyAppRouteCaseIsOpenedByAtLeastOneEntry() {
        var opened: Set<String> = []
        for screen in ScreenCatalog.all {
            if let route = screen.route, let parsed = AppRoute(name: route) { opened.insert(parsed.name) }
            if let opens = screen.opens { opened.insert(opens) }
        }
        let missing = Self.allRoutes.map(\.name).filter { !opened.contains($0) }
        #expect(missing.isEmpty, "no catalog entry reaches \(missing)")
    }

    @Test func everyRouteAnEntryNamesParsesAndIsTheOneItsArgumentsPass() {
        for screen in ScreenCatalog.all {
            guard let route = screen.route else { continue }
            #expect(AppRoute(name: route) != nil, "\(screen.id): '\(route)' is not a route")
            guard let index = screen.arguments.firstIndex(of: "-noctisInitialRoute") else {
                Issue.record("\(screen.id) names the route \(route) but does not pass it")
                continue
            }
            #expect(screen.arguments.indices.contains(index + 1) && screen.arguments[index + 1] == route, "\(screen.id): the route argument is not \(route)")
        }
    }

    @Test func everySettingsPageHasAnEntryAndEveryRangeAndFactorIsOnTheList() {
        let routes = Set(ScreenCatalog.all.compactMap(\.route))
        for page in SettingsPage.allCases {
            let route = page == .root ? "settings" : "settings:\(page.token)"
            #expect(routes.contains(route), "no entry for Settings page \(page.rawValue)")
        }
        for range in ["sleep", "sleep:week", "sleep:month", "recovery", "recovery:7d", "recovery:30d", "recovery:90d"] {
            #expect(routes.contains(range), "no entry for \(range)")
        }
        for factor in ["sleepDuration", "sleepConsistency", "hrv", "restingHeartRate"] {
            #expect(routes.contains("recovery:30d:\(factor)"), "no entry for the \(factor) factor")
            let parsed = AppRoute(name: "recovery:30d:\(factor)")
            if case .recovery(let range, let kind)? = parsed {
                #expect(range == .month && kind?.rawValue.lowercased() == factor.lowercased())
            } else {
                Issue.record("recovery:30d:\(factor) did not parse as a factor's page")
            }
        }
    }

    @Test func everyOnboardingStepHasAnEntry() {
        let steps = Set(ScreenCatalog.all.filter { $0.area == .onboarding }.compactMap { screen -> String? in
            guard let index = screen.arguments.firstIndex(of: "-noctis.onboarding.step") else { return nil }
            return screen.arguments[index + 1]
        })
        #expect(steps == Set(OnboardingStep.allCases.map(\.rawValue)))
    }

    /// Off the main actor (the sources are megabytes and the suite's other tests wait on that actor), and each distinct flag looked up once.
    @Test nonisolated func aScenarioIsNamedOnceAndEveryFlagIsOneTheAppReads() throws {
        let sources = try Self.shippedSource()
        var flags: [String: [String]] = [:]
        for screen in ScreenCatalog.all {
            #expect(screen.arguments.filter { $0 == "-mockScenario" }.count <= 1, "\(screen.id) names two scenarios (the app reads the first)")
            for flag in screen.arguments where flag.hasPrefix("-") && flag.dropFirst().first?.isLetter == true { flags[flag, default: []].append(screen.id) }
        }
        for (flag, screens) in flags.sorted(by: { $0.key < $1.key }) {
            // A flag is read by name ("-mockScenario") or, for the defaults' argument domain, by its key ("noctis.coach.quota").
            // `-AppleLocale` is iOS's own argument (it sets the region the system reports), read by the system, not by the app: the one exception.
            let known = flag == "-AppleLocale" || sources.contains("\"\(flag)\"") || sources.contains("\"\(flag.dropFirst())\"")
            #expect(known, "no source reads the launch flag \(flag) (\(screens.first ?? ""))")
        }
    }

    @Test func theCatalogHasTheScreensTheBriefNames() {
        let areas = Set(ScreenCatalog.all.map(\.area))
        #expect(areas == Set(CatalogScreen.Area.allCases), "areas with no entry: \(Set(CatalogScreen.Area.allCases).subtracting(areas))")
        let ids = Set(ScreenCatalog.all.map(\.id))
        for required in [
            "home.day.full", "home.evening.full", "sleep.day.full", "recovery.today.full", "insights.all.full", "coach.hub.full", "night.tonight",
            "night.windDown.prestart", "night.windDown.running30", "night.windDown.running90", "night.windDown.finished", "premium.paywall.loaded",
            "premium.paywall.loading", "premium.paywall.unavailable", "premium.compare", "settings.root", "privacy.deleteAll", "reviews.list",
        ] {
            #expect(ids.contains(required), "\(required) is missing")
        }
        // Tier one: the tabs, Tonight, Wind-down, onboarding, the paywall and Settings.
        #expect(ScreenCatalog.all.filter(\.tierOne).count >= 20)
    }

    /// `QA_CATALOG_JSON=<path> swift test --filter ScreenCatalogTests` writes the catalog for `scripts/qa_coverage.py` (Docs/qa/coverage/catalog.json).
    @Test func theCatalogIsWrittenAsJSONWhenAsked() throws {
        guard let path = ProcessInfo.processInfo.environment["QA_CATALOG_JSON"] else { return }
        let list: [[String: Any]] = ScreenCatalog.all.map { screen in
            [
                "id": screen.id, "area": screen.area.rawValue, "title": screen.title, "tierOne": screen.tierOne, "scrolls": screen.scrolls,
                "platform": screen.platform.rawValue == "iPhone" ? "iPhone" : "watch", "surface": screen.surface.rawValue, "route": screen.route ?? "",
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// The Swift in the app, its extensions and the Watch (not the catalog itself).
    private nonisolated static func shippedSource() throws -> String {
        var text = ""
        let roots = ["Packages/NoctisKit/Sources", "App", "Widgets/Home", "Widgets/Alarm", "Watch/App", "Watch/Widgets"]
        for root in roots {
            let url = repository.appending(path: root, directoryHint: .isDirectory)
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in enumerator where file.pathExtension == "swift" && !file.path.contains("/QACatalog/") {
                text += (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                text += "\n"
            }
        }
        #expect(!text.isEmpty, "the sources were not found under \(repository.path)")
        return text
    }
}
