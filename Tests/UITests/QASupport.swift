import XCTest

/// Shared plumbing for the onboarding QA suite: launch configuration,
/// screenshots paged through the scroll view, accessibility dumps and audits,
/// all written under `QA_OUT` (pass it as `TEST_RUNNER_QA_OUT`).
@MainActor
enum QA {
    static var environment: [String: String] { ProcessInfo.processInfo.environment }
    static var isAX3: Bool { environment["QA_AX3"] == "1" }

    /// e.g. "iPhone17Pro-AX3" or "iPhoneSE(3rdgeneration)-default-RM".
    static var tag: String {
        let device = (environment["SIMULATOR_DEVICE_NAME"] ?? "device").replacingOccurrences(of: " ", with: "")
        let size = isAX3 ? "AX3" : "default"
        let suffix = environment["QA_SUFFIX"].map { "-\($0)" } ?? ""
        return "\(device)-\(size)\(suffix)"
    }

    static var outDirectory: URL {
        let base = URL(fileURLWithPath: environment["QA_OUT"] ?? NSTemporaryDirectory())
        let directory = base.appendingPathComponent(tag, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func launch(
        step: String? = nil,
        goals: String? = nil,
        extra: [String] = [],
        reset: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments: [String] = []
        if reset { arguments.append("-noctisResetState") }
        if let step { arguments += ["-noctis.onboarding.step", step] }
        if let goals { arguments += ["-noctis.onboarding.selectedGoals", goals] }
        if isAX3 { arguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"] }
        // The main app's QA suites were written before Premium: they run as Premium unless a test asks for a tier.
        if extra.contains("-noctisSkipOnboarding"), !extra.contains("-forceTier") { arguments += ["-forceTier", "premium"] }
        // The mock's last night only exists once it has ended, so a run at 8 AM and a run at 10 AM saw different data (a run between the
        // mock's wake-up and 9 AM found no "last night" at all: QA_LEDGER.md). Every run is pinned to a morning (or, for the evening
        // screens, an evening) of today in the device's zone, unless the test or QA_NOW says otherwise; the app's clock runs on from there.
        if !extra.contains("-noctisNow"), !arguments.contains("-noctisNow") {
            let evening = zip(extra, extra.dropFirst()).contains { $0 == "-homeMode" && $1 == "evening" }
            arguments += ["-noctisNow", environment["QA_NOW"] ?? pinnedNow(hour: evening ? 21 : 10, minute: evening ? 30 : 0)]
        }
        app.launchArguments = arguments + extra
        app.launch()
        return app
    }

    /// Today at `hour:minute` in the device's zone, as ISO 8601 with its offset.
    static func pinnedNow(hour: Int, minute: Int) -> String {
        let calendar = Calendar.current
        let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func pause(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @discardableResult
    static func shot(_ name: String) -> Data {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: outDirectory.appendingPathComponent("\(name).png"))
        return data
    }

    static func write(_ text: String, to name: String) {
        try? text.write(to: outDirectory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    /// Screenshots the screen, then drags the scroll view up by 60% of its
    /// height (starting in the 24pt side margin, so no ruler or ring gesture
    /// is triggered) and repeats until nothing moves.
    static func capturePages(_ app: XCUIApplication, _ name: String, maxPages: Int = 10) {
        var previous = shot("\(name)-p0")
        for page in 1..<maxPages {
            let scrollView = app.scrollViews.firstMatch
            guard scrollView.exists else { return }
            let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.85))
            let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.25))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.4)
            pause(0.6)
            let current = XCUIScreen.main.screenshot().pngRepresentation
            if current == previous { return }
            try? current.write(to: outDirectory.appendingPathComponent("\(name)-p\(page).png"))
            previous = current
        }
    }

    /// The accessibility tree (VoiceOver order, labels, values, traits,
    /// frames) plus Xcode's accessibility audit, recorded without failing.
    static func inspect(_ app: XCUIApplication, _ name: String) {
        write(app.debugDescription, to: "\(name)-tree.txt")
        var issues: [String] = []
        try? app.performAccessibilityAudit(for: .all) { issue in
            let element = issue.element
            issues.append(
                "\(issue.auditType.rawValue)\t\(issue.compactDescription)\t\(element?.label ?? "-")\t\(element.map { NSCoder.string(for: $0.frame) } ?? "-")")
            return true
        }
        write(issues.joined(separator: "\n"), to: "\(name)-audit.txt")
    }

    static func element(_ app: XCUIApplication, labelBeginsWith prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    static func text(_ app: XCUIApplication, containing fragment: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", fragment)).firstMatch
    }

    static func button(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Scrolls until `element` is hittable (it may sit below the fold at AX
    /// sizes), then taps it.
    static func tap(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        guard element.waitForExistence(timeout: 8) else {
            XCTFail("Missing element: \(element)", file: file, line: line)
            return
        }
        var attempts = 0
        while !element.isHittable && attempts < 8 {
            let scrollView = app.scrollViews.firstMatch
            let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.8))
            let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.35))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
            attempts += 1
        }
        element.tap()
    }

    static var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }
}

// MARK: - Hierarchy checks (QA part 3, QA_COVERAGE.md 3.7)

extension QA {
    /// The window's safe area by its height: iPhone SE (667 pt) has none at the bottom; the Dynamic Island phones (874, 956 pt) have 62 and 34.
    static func safeArea(windowHeight: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        windowHeight <= 700 ? (20, 0) : (62, 34)
    }

    static func hierarchyChecks(_ app: XCUIApplication, at position: String) -> [String] {
        guard let root = try? app.snapshot() else { return ["\(position): the accessibility snapshot could not be taken"] }
        let window = app.windows.firstMatch.frame
        let inset = safeArea(windowHeight: window.height)
        var found: [String] = []

        var leaves: [XCUIElementSnapshot] = []
        var tabBar: XCUIElementSnapshot?
        var insideTabBar = false
        func walk(_ node: XCUIElementSnapshot) {
            let wasInside = insideTabBar
            if node.elementType == .tabBar {
                tabBar = node
                insideTabBar = true
            }
            if node.children.isEmpty, !insideTabBar { leaves.append(node) }
            for child in node.children { walk(child) }
            insideTabBar = wasInside
        }
        walk(root)

        let interactive: Set<XCUIElement.ElementType> = [
            .button, .link, .switch, .slider, .stepper, .textField, .secureTextField, .searchField, .segmentedControl, .menuItem, .checkBox,
        ]
        func describe(_ s: XCUIElementSnapshot) -> String {
            let name = s.label.isEmpty ? (s.identifier.isEmpty ? "-" : "#\(s.identifier)") : "'\(s.label.prefix(40))'"
            return "\(s.elementType.rawValue) \(name) \(Int(s.frame.width))x\(Int(s.frame.height)) at \(Int(s.frame.minX)),\(Int(s.frame.minY))"
        }
        func onScreen(_ f: CGRect) -> Bool { f.width > 0 && f.height > 0 && f.intersects(window) }

        var all: [XCUIElementSnapshot] = []
        func collect(_ node: XCUIElementSnapshot) {
            all.append(node)
            for child in node.children { collect(child) }
        }
        collect(root)

        // R19: nothing reachable is unbuilt. Any text on screen that says so is a defect, wherever the screen was reached from.
        let unbuilt = ["coming soon", "not built", "under construction", "not available yet", "lorem ipsum", "todo", "placeholder"]
        for s in all where onScreen(s.frame) {
            let text = (s.label + " " + String(describing: s.value ?? "")).lowercased()
            if let word = unbuilt.first(where: { text.contains($0) }) { found.append("\(position): UNBUILT text (\(word)): \(describe(s))") }
        }
        for s in all where interactive.contains(s.elementType) && s.isEnabled && onScreen(s.frame) {
            // A container the whole width of the window that holds buttons is not a target of its own.
            if s.frame.width >= window.width - 1, s.frame.height > 200 { continue }
            if s.frame.width < 44 || s.frame.height < 44 { found.append("\(position): target under 44 pt: \(describe(s))") }
            // A text field is named by its placeholder.
            let named = !s.label.isEmpty || !(s.placeholderValue ?? "").isEmpty || !s.title.isEmpty
            if !named { found.append("\(position): control with no label: \(describe(s))") }
        }
        for s in all where s.elementType == .image && s.label.isEmpty && onScreen(s.frame) && s.frame.width > 8 {
            found.append("\(position): image with no label that is not hidden: \(describe(s))")
        }
        var previousLabel = ""
        for s in leaves where onScreen(s.frame) && !s.label.isEmpty {
            // Two day initials ("S", "S") or two numbers in a row are not a repeated label.
            if s.label == previousLabel, s.label.count >= 4, s.elementType == .staticText || s.elementType == .button {
                found.append("\(position): the same label twice in a row: \(describe(s))")
            }
            previousLabel = s.label
        }
        for s in all
        where onScreen(s.frame) && s.elementType != .window && s.elementType != .other && s.elementType != .scrollView && s.elementType != .application {
            // An element that is mostly on screen and cut by the edge (a chip peeking in from a scroller is less than a half).
            let visible = s.frame.intersection(window).width / max(s.frame.width, 1)
            if s.frame.minX < window.minX - 0.5 || s.frame.maxX > window.maxX + 0.5, s.frame.width < window.width * 1.5, visible >= 0.5, visible < 0.99 {
                found.append("\(position): reaches past the screen's edge: \(describe(s))")
            }
        }
        for s in leaves where onScreen(s.frame) && (s.elementType == .staticText || interactive.contains(s.elementType)) && s.frame.maxY > 0 {
            // At the top of a page; scrolled content passes under the status bar by design.
            if position == "top", s.frame.minY < inset.top - 1, s.frame.maxY > 4 { found.append("\(position): inside the status bar: \(describe(s))") }
            if inset.bottom > 0, s.frame.maxY > window.height - inset.bottom + 1, s.frame.minY < window.height {
                found.append("\(position): inside the home indicator's area: \(describe(s))")
            }
        }
        if position == "bottom", let tabBar {
            for s in leaves where s.elementType == .staticText || interactive.contains(s.elementType) {
                if onScreen(s.frame), s.frame.intersects(tabBar.frame), s.frame.minY < tabBar.frame.minY - 1 {
                    found.append("bottom: under the tab bar: \(describe(s))")
                }
            }
        }
        return Array(Set(found)).sorted()
    }
}
