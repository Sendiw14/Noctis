import QACatalog
import StoreKitTest
import UIKit
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
            // The core pass leaves out the states that lay a tab out as another state does (gap, sleep only, no permission, loading); a later pass
            // without the list does them.
            let skipped = (environment["QA_SKIP_STATES"] ?? "").split(separator: ",").map(String.init)
            if let last = screen.id.split(separator: ".").last, skipped.contains(String(last)), [.home, .sleep, .recovery, .insights].contains(screen.area) { return false }
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
        // A rewalk visits only the screens a walk found not to move (a marker file), with the walk that tries the page from three heights, and
        // keeps the top picture that was viewed.
        let rewalk = environment["QA_REWALK"] == "1"
        let markerURL = directory.appendingPathComponent("\(screen.id)__noscroll.txt")
        if rewalk {
            guard screen.scrolls, FileManager.default.fileExists(atPath: markerURL.path) else { return }
            try? FileManager.default.removeItem(at: markerURL)
        }
        // Resume skips a screen whose top was photographed and whose bottom was, or that was found not to scroll (a marker file).
        if environment["QA_RESUME"] == "1", FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(screen.id)__top.png").path) {
            let bottom = FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(screen.id)__bottom.png").path)
            let marker = FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(screen.id)__noscroll.txt").path)
            // A walk that stopped at the old page limit of 10 left a p9 and called the next page the bottom: it is walked again.
            let stale = FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(screen.id)__p9.png").path)
            if (bottom || marker || !screen.scrolls) && !stale { return }
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
        // Onboarding pins itself to Light whatever the system says (R5), and the widget gallery is a harness with no probe: neither is a
        // configuration that did not take effect.
        for (key, expected) in expectations where screen.surface != .gallery {
            let wanted = key == "colorScheme" && screen.showsOnboarding ? "light" : expected
            if !environmentText.split(separator: ";").contains(Substring("\(key)=\(wanted)")) {
                failures.append("\(key) is not \(wanted) in the app: \(environmentText)")
            }
        }
        if !failures.isEmpty { XCTFail("\(screen.id) under \(configuration): the configuration did not take effect: \(failures.joined(separator: " | "))") }

        // Ready, then the steps, then ready again.
        var ready = true
        if let identifier = screen.ready { ready = element(app, identifier).waitForExistence(timeout: 20) } else { QA.pause(4.5) }
        for step in screen.steps {
            switch step {
            case .tapTab(let label): tap(app.tabBars.buttons[label], in: app, what: "\(screen.id): the \(label) tab")
            case .tapLabel(let label): tap(QA.button(app, label), in: app, what: "\(screen.id): the '\(label)' button")
            case .tapLabelPrefix(let prefix): tap(QA.element(app, labelBeginsWith: prefix), in: app, what: "\(screen.id): the element labelled '\(prefix)…'")
            case .tapIdentifier(let identifier): tap(element(app, identifier), in: app, what: "\(screen.id): \(identifier)")
            case .scrollToTop:
                for _ in 0..<6 { app.swipeDown() }
            case .waitFor(let identifier):
                if !element(app, identifier).waitForExistence(timeout: 20) { XCTFail("\(screen.id): \(identifier) did not appear") }
            case .waitForPrefix(let prefix):
                let match = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
                if !match.waitForExistence(timeout: 20) { XCTFail("\(screen.id): nothing named \(prefix)… appeared") }
            case .back:
                tap(app.navigationBars.buttons.firstMatch, in: app, what: "\(screen.id): the back button")
            case .type(let text):
                let field = app.textFields.firstMatch
                if field.waitForExistence(timeout: 10) { field.tap(); field.typeText(text) } else { XCTFail("\(screen.id): no text field to type into") }
            case .wait(let seconds):
                QA.pause(seconds)
            }
        }
        if !screen.steps.isEmpty, let identifier = screen.ready { ready = element(app, identifier).waitForExistence(timeout: 20) } else if !screen.steps.isEmpty { QA.pause(2) }
        QA.pause(1.0)

        var produced: [String] = []
        var issues: [String] = []
        let top = XCUIScreen.main.screenshot().pngRepresentation
        if !rewalk { save(top, "\(screen.id)__top.png") }
        produced.append("top")
        let checks = environment["QA_CHECKS"] != "0"
        if checks { issues += QA.hierarchyChecks(app, at: "top") }

        if screen.scrolls {
            let result = scrollToTheBottom(app, maximum: screen.surface == .gallery ? 12 : 30)
            let pages = result.pages
            for (index, page) in pages.enumerated() {
                let name = index == pages.count - 1 && result.reachedEnd ? "bottom" : "p\(index + 1)"
                save(page, "\(screen.id)__\(name).png")
                produced.append(name)
            }
            if pages.isEmpty {
                saveText("the page did not move", "\(screen.id)__noscroll.txt")
            } else if !result.reachedEnd {
                saveText("stopped at the page limit, not at the bottom", "\(screen.id)__nobottom.txt")
            } else if checks {
                issues += QA.hierarchyChecks(app, at: "bottom")
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

    /// How different two screenshots of the middle of the screen are: a 48 x 96 grey picture of each, the mean difference out of 255.
    private static func meanDifference(_ a: Data, _ b: Data) -> Double {
        if a == b { return 0 }
        func picture(_ data: Data) -> [UInt8]? {
            guard let image = UIImage(data: data)?.cgImage else { return nil }
            let width = 48, height = 96
            var pixels = [UInt8](repeating: 0, count: width * height)
            guard let context = CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return nil }
            context.interpolationQuality = .medium
            // The middle of the screen only: the status bar, the tab bar and the bedtime accessory change by themselves while the page does not (the
            // accessory folds and unfolds with each swipe), and that kept a walk from ever saying it had reached the bottom.
            let crop = CGRect(x: 0, y: CGFloat(image.height) * 0.10, width: CGFloat(image.width), height: CGFloat(image.height) * 0.68)
            guard let middle = image.cropping(to: crop) else { return nil }
            context.draw(middle, in: CGRect(x: 0, y: 0, width: width, height: height))
            return pixels
        }
        guard let x = picture(a), let y = picture(b), x.count == y.count else { return 255 }
        var total = 0
        for index in 0..<x.count { total += abs(Int(x[index]) - Int(y[index])) }
        return Double(total) / Double(x.count)
    }

    private static func similar(_ a: Data, _ b: Data) -> Bool { meanDifference(a, b) < 2.0 }

    /// Flings the page's scroller up until the screen stops changing twice running. `reachedEnd` is false when the limit stopped it first: the last
    /// page is then not the bottom, and the matrix says so instead of calling it that. Every page between is returned only when `QA_PAGES=1` (the
    /// reference configuration); otherwise just the last one is.
    private func scrollToTheBottom(_ app: XCUIApplication, maximum: Int) -> (pages: [Data], reachedEnd: Bool) {
        guard let scrollView = scroller(app) else { return ([], true) }
        let everyPage = environment["QA_PAGES"] == "1"
        var pages: [Data] = []
        var last: Data?
        var previous = XCUIScreen.main.screenshot().pngRepresentation
        var unchanged = 0
        var beforePrevious: Data?
        var trace: [String] = []
        // Where the drag starts, as a fraction of the height. 70% first: below that sit the tab bar and, in the evening, the bedtime accessory,
        // which a drag that starts on it does not scroll under (a walk that began at 85% and 90% never moved the evening Home). A page that did
        // not move at all is tried again from 45% and 20%: on a small screen a pinned bar (the Coach's suggestions and field, a wheel picker) is
        // what is under 70%, and a drag that starts on it moves nothing behind it.
        let starts: [CGFloat] = [0.7, 0.45, 0.2]
        var startIndex = 0
        defer { if environment["QA_TRACE"] == "1" { saveText(trace.joined(separator: " "), "walk-trace.txt") } }
        for _ in 0..<maximum {
            let start = starts[startIndex]
            // Starting in the 24 pt side margin: no ruler, ring or chart gesture is triggered. A fast drag: the page flings and settles.
            scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: start))
                .press(
                    forDuration: 0.02,
                    thenDragTo: scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: everyPage ? max(0.02, start - 0.5) : max(0.02, start - 0.6))),
                    withVelocity: everyPage ? .slow : .fast, thenHoldForDuration: everyPage ? 0.4 : 0.1
                )
            QA.pause(everyPage ? 0.6 : 1.1)
            var current = XCUIScreen.main.screenshot().pngRepresentation
            // A page that is still settling (a fling's end, a rubber band coming back from the bottom) is looked at again before it is called moved:
            // a small difference is waited out, a large one is a page that moved.
            let difference = Self.meanDifference(current, previous)
            trace.append(String(format: "%.2f", difference))
            if difference >= 2.0, difference < 16.0 {
                QA.pause(1.6)
                current = XCUIScreen.main.screenshot().pngRepresentation
                trace.append(String(format: "(settled %.2f)", Self.meanDifference(current, previous)))
            }
            // The same page, give or take what moves by itself (a countdown, a drifting glow): compared as a small picture.
            // At the bottom the tab bar folds and unfolds with each swipe (the rubber band is a scroll back up), and that moves the page's end by the
            // height of the bar: the walk then alternates between two pictures. Back at the picture from two swipes ago is the end as well.
            let alternating = beforePrevious.map { Self.similar(current, $0) } ?? false
            if Self.similar(current, previous) || alternating {
                // Nothing has moved yet: the drag may have started on something that does not scroll the page. Higher up, then.
                if last == nil, startIndex < starts.count - 1 {
                    startIndex += 1
                    trace.append("(from \(starts[startIndex]))")
                    continue
                }
                // A drag that did not take is not the end: it has to fail twice.
                unchanged += 1
                if unchanged >= 2 || alternating { return (everyPage ? pages : (last.map { [$0] } ?? []), true) }
                continue
            }
            unchanged = 0
            if everyPage { pages.append(current) }
            last = current
            beforePrevious = previous
            previous = current
        }
        return (everyPage ? pages : (last.map { [$0] } ?? []), false)
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
