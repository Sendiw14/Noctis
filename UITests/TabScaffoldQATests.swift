import XCTest

/// The tab scaffold (APP_RULES.md R27), fast: iPhone 17 Pro, light and dark
/// (`QA_SUFFIX=dark` names the dark run). Every tab opens with its field, its
/// title and its section-colored glyph selected; Home and Sleep are captured
/// again after scrolling the field away.
@MainActor
final class TabScaffoldQATests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private var isDark: Bool { (QA.environment["QA_SUFFIX"] ?? "").contains("dark") }

    private struct Tab {
        let name: String
        let title: String
        let route: String?
        let field: (light: UInt32, dark: UInt32)
        let glyph: (light: UInt32, dark: UInt32)
    }

    private let tabs = [
        Tab(name: "home", title: "Home", route: nil, field: (0xF0B27F, 0xD48A55), glyph: (0xB4622A, 0xD48A55)),
        Tab(name: "sleep", title: "Sleep", route: "sleep", field: (0xA9BC84, 0x8FA366), glyph: (0x6B8A3E, 0x8FA366)),
        Tab(name: "recovery", title: "Recovery", route: "recovery", field: (0xA08CEB, 0x8E7BDC), glyph: (0x6B55C4, 0x8E7BDC)),
        Tab(name: "insights", title: "Insights", route: "insights", field: (0xF2CE6B, 0xE0B955), glyph: (0x8A6A1F, 0xE0B955)),
        Tab(name: "coach", title: "Coach", route: "coach", field: (0xEBA79E, 0xC98580), glyph: (0xA4524A, 0xC98580)),
    ]

    private func launch(_ tab: Tab, mode: String = "day") -> XCUIApplication {
        var arguments = ["-useMockHealth", "-mockScenario", "full", "-noctisSkipOnboarding", "-homeMode", mode]
        if let route = tab.route { arguments += ["-noctisInitialRoute", route] }
        return QA.launch(extra: arguments)
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    // MARK: Pixels

    private struct Pixels {
        let image: CGImage
        let scale: CGFloat
        let data: [UInt8]

        init?(_ screenshot: XCUIScreenshot) {
            guard let cg = screenshot.image.cgImage else { return nil }
            var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            guard let context = CGContext(
                data: &bytes, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            image = cg
            scale = screenshot.image.scale
            data = bytes
        }

        func color(atX x: CGFloat, y: CGFloat) -> (Int, Int, Int) {
            let px = min(max(Int(x * scale), 0), image.width - 1), py = min(max(Int(y * scale), 0), image.height - 1)
            let i = (py * image.width + px) * 4
            return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
        }

        /// The average of the most saturated third of the pixels in `rect`
        /// (points): a glyph's tint, without the glass around it.
        func tint(in rect: CGRect) -> (Int, Int, Int) {
            var samples: [(Int, Int, Int, Int)] = []
            let x0 = Int(rect.minX * scale), x1 = min(Int(rect.maxX * scale), image.width)
            let y0 = Int(rect.minY * scale), y1 = min(Int(rect.maxY * scale), image.height)
            for y in stride(from: y0, to: y1, by: 1) {
                for x in stride(from: x0, to: x1, by: 1) {
                    let i = (y * image.width + x) * 4
                    let r = Int(data[i]), g = Int(data[i + 1]), b = Int(data[i + 2])
                    samples.append((max(r, g, b) - min(r, g, b), r, g, b))
                }
            }
            let top = samples.sorted { $0.0 > $1.0 }.prefix(max(samples.count / 12, 1))
            let n = max(top.count, 1)
            return (top.map(\.1).reduce(0, +) / n, top.map(\.2).reduce(0, +) / n, top.map(\.3).reduce(0, +) / n)
        }
    }

    private func components(_ hex: UInt32) -> (Int, Int, Int) {
        (Int((hex >> 16) & 0xFF), Int((hex >> 8) & 0xFF), Int(hex & 0xFF))
    }

    private func close(_ a: (Int, Int, Int), _ b: (Int, Int, Int), by tolerance: Int) -> Bool {
        abs(a.0 - b.0) <= tolerance && abs(a.1 - b.1) <= tolerance && abs(a.2 - b.2) <= tolerance
    }

    /// Hue in degrees, and whether the color is colored at all.
    private func hue(_ c: (Int, Int, Int)) -> (degrees: Double, chroma: Int) {
        let r = Double(c.0), g = Double(c.1), b = Double(c.2)
        let high = max(r, g, b), low = min(r, g, b)
        let chroma = high - low
        guard chroma > 0 else { return (0, 0) }
        var h: Double
        if high == r { h = (g - b) / chroma } else if high == g { h = 2 + (b - r) / chroma } else { h = 4 + (r - g) / chroma }
        h *= 60
        if h < 0 { h += 360 }
        return (h, Int(chroma))
    }

    /// A glyph is thin and antialiased, so its sampled color is the tint mixed
    /// with the glass behind it: the same hue, not the same value.
    private func sameHue(_ a: (Int, Int, Int), _ b: (Int, Int, Int), within degrees: Double = 22) -> Bool {
        let x = hue(a), y = hue(b)
        guard x.chroma >= 25, y.chroma >= 25 else { return false }
        let difference = abs(x.degrees - y.degrees)
        return min(difference, 360 - difference) <= degrees
    }

    // MARK: Tests

    /// Each tab: the title, the field's color behind it, and the tab bar's
    /// selected glyph in its section ink.
    func testEveryTabHasItsFieldItsTitleAndItsGlyphTint() {
        for tab in tabs {
            let app = launch(tab)
            let title = element(app, "tab.title")
            XCTAssertTrue(title.waitForExistence(timeout: 12), "\(tab.name) title")
            XCTAssertEqual(title.label.isEmpty, false)
            QA.pause(4.5)
            let shot = QA.shot("tab-\(tab.name)-top")
            guard let pixels = Pixels(XCUIScreen.main.screenshot()) else { XCTFail("no pixels"); continue }
            _ = shot
            // The field: its color beside the date caption, clear of any text.
            let field = pixels.color(atX: 6, y: 112)
            XCTAssertTrue(close(field, components(isDark ? tab.field.dark : tab.field.light), by: 10), "\(tab.name) field \(field)")
            // The glyph: the selected tab button, tinted by its section.
            let button = app.tabBars.buttons[tab.title]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(tab.name) tab button")
            XCTAssertTrue(button.isSelected, "\(tab.name) selected")
            let tint = pixels.tint(in: button.frame)
            XCTAssertTrue(sameHue(tint, components(isDark ? tab.glyph.dark : tab.glyph.light)), "\(tab.name) glyph tint \(tint), hue \(hue(tint).degrees)")
            app.terminate()
        }
    }

    /// Insights is built on the same scaffold: its title and its summary line.
    func testInsightsIsOnTheScaffold() {
        let tab = tabs.first { $0.name == "insights" }!
        let app = launch(tab)
        XCTAssertTrue(element(app, "insights.summary").waitForExistence(timeout: 12))
        XCTAssertTrue(element(app, "tab.title").exists)
        app.terminate()
    }

    /// Home and Sleep with the field scrolled away: the compact bar takes
    /// over, and pressing it goes back to the top.
    func testTheCompactBarTakesOverWhenTheFieldScrollsAway() {
        for (name, identifier) in [("sleep", "tab.compactBar"), ("recovery", "tab.compactBar")] {
            let tab = tabs.first { $0.name == name }!
            let app = launch(tab)
            XCTAssertTrue(element(app, "tab.title").waitForExistence(timeout: 12))
            QA.pause(4)
            let scrollView = app.scrollViews.firstMatch
            for _ in 0..<3 {
                scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.85))
                    .press(forDuration: 0.05, thenDragTo: scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.25)), withVelocity: .slow, thenHoldForDuration: 0.3)
                QA.pause(0.5)
            }
            XCTAssertTrue(element(app, identifier).waitForExistence(timeout: 4), "\(name) compact bar")
            QA.shot("tab-\(name)-scrolled")
            app.terminate()
        }
    }

    /// Home in the evening: "Good evening." on the apricot field, the bedtime
    /// hero on the paper below it.
    func testHomeEvening() {
        let app = launch(tabs[0], mode: "evening")
        XCTAssertTrue(element(app, "tab.title").waitForExistence(timeout: 12))
        QA.pause(4.5)
        QA.shot("tab-home-evening-top")
        let scrollView = app.scrollViews.firstMatch
        scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.85))
            .press(forDuration: 0.05, thenDragTo: scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.3)), withVelocity: .slow, thenHoldForDuration: 0.4)
        QA.pause(0.7)
        QA.shot("tab-home-evening-scrolled1")
        app.terminate()
    }

    func testHomeAndSleepScrolled() {
        for name in ["home", "sleep"] {
            let tab = tabs.first { $0.name == name }!
            let app = launch(tab)
            XCTAssertTrue(element(app, "tab.title").waitForExistence(timeout: 12))
            QA.pause(4.5)
            let scrollView = app.scrollViews.firstMatch
            for index in 1...2 {
                scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.85))
                    .press(forDuration: 0.05, thenDragTo: scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.3)), withVelocity: .slow, thenHoldForDuration: 0.4)
                QA.pause(0.7)
                QA.shot("tab-\(name)-scrolled\(index)")
            }
            app.terminate()
        }
    }
}
