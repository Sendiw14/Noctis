import QACatalog
import StoreKitTest
import XCTest

/// QA part 3 (QA_COVERAGE.md, APP_RULES.md R67): every screen in `ScreenCatalog` visited under one configuration.
///
/// What a run does, per screen: launches the app with the entry's Debug flags, reads the environment probe (what the app itself sees of the
/// device's settings) and checks it against `QA_EXPECT`, takes the steps the entry names, photographs the top, scrolls to the bottom
/// photographing every page, and runs the hierarchy checks on the top and the bottom. Everything is written under
/// `<QA_OUT>/matrix/<QA_CONFIG>/<device>/` as `<screen id>__top.png`, `__p1.png`..., `__bottom.png`, `__env.txt`, `__checks.txt`, and one line
/// per screen in `manifest.jsonl`. The harness never says a screen was *viewed*: that is QA_COVERAGE.md's column, filled in by someone looking.
///
/// Environment (pass each as `TEST_RUNNER_<NAME>`):
///   QA_OUT        directory for the output (as for the other QA suites)
///   QA_CONFIG     the configuration's name in the file names: "A-light", "B-AX3-dark", ...
///   QA_EXPECT     `key=value;key=value` the environment probe must report (the configuration took effect)
///   QA_LAUNCH_EXTRA  extra launch arguments, space separated (the pseudolanguages, a region, a language)
///   QA_ONLY       comma-separated id prefixes to visit; QA_TIER1=1 only the tier-one screens; QA_RESUME=1 skips screens already produced
@MainActor
final class QAMatrixTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    // MARK: Configuration

    private var environment: [String: String] { QA.environment }
    private var configuration: String { environment["QA_CONFIG"] ?? "default" }
    /// The folder's name for the device: `QA_DEVICE_NAME` when a second simulator of the same model shares the work, else the simulator's own name.
    private var device: String { (environment["QA_DEVICE_NAME"] ?? environment["SIMULATOR_DEVICE_NAME"] ?? "device").replacingOccurrences(of: " ", with: "") }
    private var extraLaunch: [String] { (environment["QA_LAUNCH_EXTRA"] ?? "").split(separator: " ").map(String.init) }

    private var expectations: [(key: String, value: String)] {
        (environment["QA_EXPECT"] ?? "").split(separator: ";").compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            return parts.count == 2 ? (parts[0], parts[1]) : nil
        }
    }

    private var outputDirectory: URL {
        let base = URL(fileURLWithPath: environment["QA_OUT"] ?? NSTemporaryDirectory())
            .appendingPathComponent("matrix", isDirectory: true)
            .appendingPathComponent(configuration, isDirectory: true)
            .appendingPathComponent(device, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func entries(in area: CatalogScreen.Area) -> [CatalogScreen] {
        let only = (environment["QA_ONLY"] ?? "").split(separator: ",").map(String.init)
        return ScreenCatalog.iPhone.filter { screen in
            guard screen.area == area else { return false }
            if environment["QA_TIER1"] == "1", !screen.tierOne { return false }
            return only.isEmpty || only.contains { screen.id.hasPrefix($0) }
        }
    }

    // MARK: One screen

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func save(_ data: Data, _ name: String) {
        try? data.write(to: outputDirectory.appendingPathComponent(name))
    }

    private func saveText(_ text: String, _ name: String) {
        try? text.write(to: outputDirectory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func visit(_ screen: CatalogScreen) {
        let started = Date()
        let directory = outputDirectory
        // Resume skips a screen whose top was photographed and whose bottom was, or that was found not to scroll (a marker file).
        if environment["QA_RESUME"] == "1", FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(screen.id)__top.png").path) {
            let bottom = FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(screen.id)__bottom.png").path)
            let marker = FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(screen.id)__noscroll.txt").path)
            if bottom || marker || !screen.scrolls { return }
        }

        // The plans the paywall shows come from the App Store; on a simulator they come from `Noctis.storekit` through a test session that lives as long as
        // the visit (the session is the device's, not the app's: the app asks StoreKit as it always does).
        var store: SKTestSession?
        if screen.needsStore {
            let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Noctis.storekit")
            store = try? SKTestSession(contentsOf: file)
            store?.disableDialogs = true
            store?.resetToDefaultState()
            if store == nil { XCTFail("\(screen.id): no StoreKit test session for \(file.path)") }
        }
        defer { _ = store }
        let app = QA.launch(extra: screen.arguments + ["-noctisEnvironmentProbe"] + extraLaunch)
        defer { app.terminate() }

        // The environment first: it exists as soon as the window does, whichever screen the entry is.
        let probe = element(app, "debug.environment")
        var environmentText = "probe missing"
        if probe.waitForExistence(timeout: 20) { environmentText = probe.value as? String ?? "probe unreadable" }
        saveText(environmentText, "\(screen.id)__env.txt")
        var failures: [String] = []
        for (key, expected) in expectations where !environmentText.split(separator: ";").contains(Substring("\(key)=\(expected)")) {
            failures.append("\(key) is not \(expected) in the app: \(environmentText)")
        }
        if !failures.isEmpty { XCTFail("\(screen.id) under \(configuration): the configuration did not take effect: \(failures.joined(separator: " | "))") }

        // Ready, then the steps, then ready again.
        var ready = true
        if let identifier = screen.ready { ready = element(app, identifier).waitForExistence(timeout: 20) } else { QA.pause(4.5) }
        for step in screen.steps {
            switch step {
            case .tapTab(let label): tap(app.tabBars.buttons[label], in: app, what: "\(screen.id): the \(label) tab")
            case .tapLabel(let label): tap(QA.button(app, label), in: app, what: "\(screen.id): the '\(label)' button")
            case .tapIdentifier(let identifier): tap(element(app, identifier), in: app, what: "\(screen.id): \(identifier)")
            case .scrollToTop:
                for _ in 0..<6 { app.swipeDown() }
            case .waitFor(let identifier):
                if !element(app, identifier).waitForExistence(timeout: 20) { XCTFail("\(screen.id): \(identifier) did not appear") }
            case .back:
                tap(app.navigationBars.buttons.firstMatch, in: app, what: "\(screen.id): the back button")
            }
        }
        if !screen.steps.isEmpty, let identifier = screen.ready { ready = element(app, identifier).waitForExistence(timeout: 20) } else if !screen.steps.isEmpty { QA.pause(2) }
        QA.pause(1.0)

        var produced: [String] = []
        var issues: [String] = []
        let top = XCUIScreen.main.screenshot().pngRepresentation
        save(top, "\(screen.id)__top.png")
        produced.append("top")
        let checks = environment["QA_CHECKS"] != "0"
        if checks { issues += QA.hierarchyChecks(app, at: "top") }

        if screen.scrolls {
            let pages = scrollToTheBottom(app, maximum: screen.surface == .gallery ? 12 : 10)
            for (index, page) in pages.enumerated() {
                let name = index == pages.count - 1 ? "bottom" : "p\(index + 1)"
                save(page, "\(screen.id)__\(name).png")
                produced.append(name)
            }
            if !pages.isEmpty {
                if checks { issues += QA.hierarchyChecks(app, at: "bottom") }
            } else {
                saveText("the page did not move", "\(screen.id)__noscroll.txt")
            }
        }
        saveText(issues.isEmpty ? "none" : issues.joined(separator: "\n"), "\(screen.id)__checks.txt")

        let line: [String: Any] = [
            "id": screen.id, "config": configuration, "device": device, "ready": ready, "produced": produced, "issues": issues.count,
            "environmentOK": failures.isEmpty, "seconds": Int(Date().timeIntervalSince(started)),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) {
            append(text + "\n", to: directory.appendingPathComponent("manifest.jsonl"))
        }
        if !ready { XCTFail("\(screen.id): its ready element \(screen.ready ?? "-") did not appear (the screenshots were still taken)") }
    }

    private func append(_ text: String, to url: URL) {
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(text.utf8))
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func tap(_ target: XCUIElement, in app: XCUIApplication, what: String) {
        guard target.waitForExistence(timeout: 10) else {
            XCTFail("\(what) did not appear")
            return
        }
        var attempts = 0
        while !target.isHittable, attempts < 8 {
            let scrollView = app.scrollViews.firstMatch
            scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.8))
                .press(forDuration: 0.05, thenDragTo: scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.35)), withVelocity: .slow, thenHoldForDuration: 0.3)
            attempts += 1
        }
        target.tap()
        QA.pause(1.0)
    }

    /// The page's own scroller: the largest scroll view, table or collection view on screen (the first scroll view of Insights and Coach is a row of
    /// chips, which does not scroll the page).
    private func scroller(_ app: XCUIApplication) -> XCUIElement? {
        let candidates = [app.scrollViews, app.tables, app.collectionViews].flatMap { $0.allElementsBoundByIndex }
        return candidates.filter { $0.exists && $0.frame.height > 200 && $0.frame.width > 200 }.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    /// Drags the page's scroller up until the screen stops changing; every page after the top is returned (the last one is the bottom).
    private func scrollToTheBottom(_ app: XCUIApplication, maximum: Int) -> [Data] {
        guard let scrollView = scroller(app) else { return [] }
        var pages: [Data] = []
        var previous = XCUIScreen.main.screenshot().pngRepresentation
        for _ in 0..<maximum {
            // Starting in the 24 pt side margin: no ruler, ring or chart gesture is triggered.
            scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.85))
                .press(forDuration: 0.05, thenDragTo: scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.25)), withVelocity: .slow, thenHoldForDuration: 0.4)
            QA.pause(0.6)
            let current = XCUIScreen.main.screenshot().pngRepresentation
            if current == previous { break }
            pages.append(current)
            previous = current
        }
        return pages
    }

    // MARK: Tests, one per area

    private func run(_ area: CatalogScreen.Area) {
        for screen in entries(in: area) { visit(screen) }
    }

    func testOnboarding() { run(.onboarding) }
    func testHome() { run(.home) }
    func testSleep() { run(.sleep) }
    func testRecovery() { run(.recovery) }
    func testInsights() { run(.insights) }
    func testCoach() { run(.coach) }
    func testNight() { run(.night) }
    func testReviews() { run(.reviews) }
    func testPremium() { run(.premium) }
    func testProfile() { run(.profile) }
    func testSettings() { run(.settings) }
    func testPrivacy() { run(.privacy) }
    func testWidgets() { run(.widgets) }
}
