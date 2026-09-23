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
        app.launchArguments = arguments + extra
        app.launch()
        return app
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
            issues.append("\(issue.auditType.rawValue)\t\(issue.compactDescription)\t\(element?.label ?? "-")\t\(element.map { NSCoder.string(for: $0.frame) } ?? "-")")
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
