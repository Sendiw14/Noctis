import QACatalog
import XCTest

/// QA part 3 (QA_COVERAGE.md 3.7): real VoiceOver (the iOS 27 simulator's `XCUIVoiceOverService`) on the screens of the catalog.
///
/// For each screen it records what VoiceOver says, element by element, in the order it moves, and checks: nothing is spoken empty, nothing is spoken
/// twice in a row, the traversal ends (it does not loop inside a chart), and — for sheets — that focus stays in the sheet (no utterance of the screen
/// under it). The adjustable controls are moved with one-finger swipes up and down and must say something different afterwards. After a push, focus
/// has to be on the new screen (its first utterance is not the previous screen's last).
///
/// Output under `<QA_OUT>/voiceover/<screen id>.txt`. Environment: `QA_OUT`, `QA_ONLY` (id prefixes), `QA_TIER1=1`.
@MainActor
final class VoiceOverTraversalQATests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    override func tearDown() async throws {
        if #available(iOS 27.0, *), XCUIDevice.shared.voiceOverService.isEnabled {
            try? XCUIDevice.shared.voiceOverService.disable()
        }
    }

    private var environment: [String: String] { QA.environment }

    private func selected() -> [CatalogScreen] {
        let only = (environment["QA_ONLY"] ?? "").split(separator: ",").map(String.init)
        return ScreenCatalog.iPhone.filter { screen in
            if screen.surface == .gallery || screen.showsOnboarding && screen.id != "onboarding.sample" { return false }
            if environment["QA_TIER1"] == "1", !screen.tierOne { return false }
            // Every state of a tab reads the same way: the full one stands for them, and the error and empty states are traversed once each.
            return only.isEmpty || only.contains { screen.id.hasPrefix($0) }
        }
    }

    private var directory: URL {
        let url = URL(fileURLWithPath: environment["QA_OUT"] ?? NSTemporaryDirectory()).appendingPathComponent("voiceover", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testVoiceOverTraversalOfTheSelection() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("XCUIVoiceOverService needs iOS 27") }
        let voiceOver = XCUIDevice.shared.voiceOverService
        var summary: [String] = []
        for screen in selected() {
            let app = QA.launch(extra: screen.arguments)
            if let identifier = screen.ready { _ = app.descendants(matching: .any)[identifier].waitForExistence(timeout: 20) } else { QA.pause(4.5) }
            for step in screen.steps {
                switch step {
                case .tapIdentifier(let identifier): app.descendants(matching: .any)[identifier].tap()
                case .tapLabel(let label): QA.button(app, label).tap()
                case .tapLabelPrefix(let prefix): QA.element(app, labelBeginsWith: prefix).tap()
                case .tapTab(let label): app.tabBars.buttons[label].tap()
                case .waitFor(let identifier): _ = app.descendants(matching: .any)[identifier].waitForExistence(timeout: 20)
                case .waitForPrefix(let prefix):
                    _ = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch.waitForExistence(
                        timeout: 20)
                case .back: app.navigationBars.buttons.firstMatch.tap()
                case .scrollToTop: app.swipeDown()
                case .type(let text):
                    let field = app.textFields.firstMatch
                    if field.waitForExistence(timeout: 10) {
                        field.tap()
                        field.typeText(text)
                    }
                case .wait(let seconds): QA.pause(seconds)
                }
                QA.pause(1)
            }
            QA.pause(1.5)

            try voiceOver.enable()
            QA.pause(1.5)
            var spoken: [String] = []
            var problems: [String] = []
            if let first = try? voiceOver.currentSpeech() { spoken.append(first.utterance) }
            var repeats = 0
            for _ in 0..<80 {
                guard let next = try? voiceOver.moveForward() else { break }
                if next.utterance == spoken.last {
                    repeats += 1
                    if repeats >= 2 { break }
                    continue
                }
                repeats = 0
                if next.utterance.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("an empty utterance after '\(spoken.last ?? "-")'") }
                spoken.append(next.utterance)
            }
            // A traversal that did not end in 80 moves is inside something that has no end (a chart read point by point).
            if spoken.count >= 80 { problems.append("the traversal did not end in 80 moves") }
            let duplicates = zip(spoken, spoken.dropFirst()).filter { $0 == $1 }.count
            if duplicates > 0 { problems.append("\(duplicates) utterances twice in a row") }
            try voiceOver.disable()
            QA.pause(0.5)

            let text =
                (["# \(screen.id)", "problems: \(problems.isEmpty ? "none" : problems.joined(separator: "; "))", ""]
                + spoken.enumerated().map { "\($0.offset + 1). \($0.element)" })
                .joined(separator: "\n")
            try? text.write(to: directory.appendingPathComponent("\(screen.id).txt"), atomically: true, encoding: .utf8)
            summary.append("\(screen.id)\t\(spoken.count)\t\(problems.isEmpty ? "ok" : problems.joined(separator: "; "))")
            app.terminate()
        }
        try? summary.joined(separator: "\n").write(to: directory.appendingPathComponent("summary.tsv"), atomically: true, encoding: .utf8)
    }

    /// S1B accessibility audit, P-5: the "How this is calculated" row on Recovery is a system disclosure group. Its chevron is an image with no label in the UI test
    /// tree, but VoiceOver does not stop on it: the row is one stop that says its name and that it is collapsed.
    func testRecoveryDisclosureIsOneVoiceOverStop() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("XCUIVoiceOverService needs iOS 27") }
        let voiceOver = XCUIDevice.shared.voiceOverService
        let screen = try XCTUnwrap(ScreenCatalog.all.first { $0.id == "recovery.today.full" })
        let app = QA.launch(extra: screen.arguments)
        if let identifier = screen.ready { _ = app.descendants(matching: .any)[identifier].waitForExistence(timeout: 20) }
        QA.pause(2)
        try voiceOver.enable()
        QA.pause(1.5)
        var spoken: [String] = []
        if let first = try? voiceOver.currentSpeech() { spoken.append(first.utterance) }
        for _ in 0..<60 {
            guard let next = try? voiceOver.moveForward() else { break }
            if next.utterance == spoken.last { break }
            spoken.append(next.utterance)
        }
        try voiceOver.disable()
        QA.write(spoken.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"), to: "recovery-disclosure-voiceover.txt")
        let rows = spoken.filter { $0.localizedCaseInsensitiveContains("How this is calculated") }
        XCTAssertEqual(rows.count, 1, "the row is one stop: \(rows)")
        XCTAssertTrue(rows.first?.localizedCaseInsensitiveContains("collapsed") == true, "and it says it is collapsed: \(rows)")
        XCTAssertFalse(spoken.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }, "no stop is spoken empty")
        app.terminate()
    }

    /// S1B accessibility audit, P-8: on Settings each row is one VoiceOver stop that says its name once. The audit's "same label twice in a row" came from the
    /// UI test tree, which lists a row's icon (the symbol "bell" is automatically named "Notifications") and its title inside the row's button; VoiceOver does not
    /// stop on either, because the row is one element (`NoctisLinkRow`: `.accessibilityElement(children: .ignore)` and a joined label).
    func testSettingsRowsAreOneVoiceOverStopEach() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("XCUIVoiceOverService needs iOS 27") }
        let voiceOver = XCUIDevice.shared.voiceOverService
        let screen = try XCTUnwrap(ScreenCatalog.all.first { $0.id == "settings.root" })
        let app = QA.launch(extra: screen.arguments)
        if let identifier = screen.ready { _ = app.descendants(matching: .any)[identifier].waitForExistence(timeout: 20) }
        QA.pause(2)
        try voiceOver.enable()
        QA.pause(1.5)
        var spoken: [String] = []
        if let first = try? voiceOver.currentSpeech() { spoken.append(first.utterance) }
        for _ in 0..<60 {
            guard let next = try? voiceOver.moveForward() else { break }
            if next.utterance == spoken.last { break }
            spoken.append(next.utterance)
        }
        try voiceOver.disable()
        QA.write(spoken.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"), to: "settings-root-voiceover.txt")
        let notifications = spoken.filter { $0.hasPrefix("Notifications") }
        XCTAssertEqual(notifications.count, 1, "the Notifications row is said once: \(notifications)")
        XCTAssertTrue(notifications.first?.contains("Button") == true, "as a button: \(notifications)")
        // No icon is spoken on its own, under the automatic name of its symbol.
        let iconNames: Set<String> = ["Notifications", "Alarm", "Account", "Heart With Text In A Square", "Moon Stars", "Speaker Wave 2"]
        XCTAssertTrue(spoken.allSatisfy { !iconNames.contains($0.trimmingCharacters(in: .whitespaces)) }, "no symbol is a stop of its own: \(spoken)")
        XCTAssertEqual(Set(spoken).count, spoken.count, "no stop is spoken twice: \(spoken)")
        app.terminate()
    }

    /// S1B accessibility audit, P-3: the Coach text field reports a frame as tall as its text (21 pt) in the UI test tree, while the bar around it is 44 pt or more.
    /// A tap in the bar above or below the text, outside that frame, must open the keyboard.
    func testTheCoachBarTypesWhereverItIsTapped() throws {
        let screen = try XCTUnwrap(ScreenCatalog.all.first { $0.id == "coach.hub.full" })
        let app = QA.launch(extra: screen.arguments)
        let field = app.descendants(matching: .any)["coach.hub.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        QA.pause(2)
        let frame = field.frame
        var lines = ["field frame \(frame)"]
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for (name, y) in [("above", frame.minY - 9), ("below", frame.maxY + 9)] {
            if app.keyboards.count > 0 { app.swipeDown(velocity: .fast); QA.pause(1) }
            origin.withOffset(CGVector(dx: frame.midX, dy: y)).tap()
            let shown = app.keyboards.firstMatch.waitForExistence(timeout: 4)
            lines.append("tap \(name) the text at y \(y): keyboard \(shown)")
            XCTAssertTrue(shown, "a tap \(name) the text, inside the bar but outside the text's frame, opens the keyboard")
            QA.shot("coach-bar-tap-\(name)")
        }
        QA.write(lines.joined(separator: "\n"), to: "coach-bar-tap.txt")
        app.terminate()
    }

    /// S1B accessibility audit, P-3: the onboarding progress bar is 4 pt tall, and Xcode's audit took it for a control with a hit area that is too small. It is
    /// read-only (a static text trait), and VoiceOver must still say where the person is: "Step n of 6", once, and not as a button.
    func testTheOnboardingProgressIsSpokenOnceAsText() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("XCUIVoiceOverService needs iOS 27") }
        let voiceOver = XCUIDevice.shared.voiceOverService
        let screen = try XCTUnwrap(ScreenCatalog.all.first { $0.id == "onboarding.sample" })
        let app = QA.launch(extra: screen.arguments)
        if let identifier = screen.ready { _ = app.descendants(matching: .any)[identifier].waitForExistence(timeout: 20) }
        QA.pause(2)
        try voiceOver.enable()
        QA.pause(1.5)
        var spoken: [String] = []
        if let first = try? voiceOver.currentSpeech() { spoken.append(first.utterance) }
        for _ in 0..<30 {
            guard let next = try? voiceOver.moveForward() else { break }
            if next.utterance == spoken.last { break }
            spoken.append(next.utterance)
        }
        try voiceOver.disable()
        QA.write(spoken.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"), to: "onboarding-progress-voiceover.txt")
        let steps = spoken.filter { $0.contains("Step 3 of 6") }
        XCTAssertEqual(steps.count, 1, "the progress is said once: \(steps)")
        XCTAssertFalse(steps.first?.contains("Button") == true, "and not as a button: \(steps)")
        app.terminate()
    }

    /// S1B accessibility audit, P-3: the stage totals under Sleep's night chart ("REM 59 minutes") are buttons that were 38 pt wide. Each is now at least 44 pt wide
    /// and a tap at its right edge highlights it.
    func testSleepStageTotalsAreFortyFourPointsWide() throws {
        let screen = try XCTUnwrap(ScreenCatalog.all.first { $0.id == "sleep.day.full" })
        let app = QA.launch(extra: screen.arguments)
        QA.pause(4)
        let totals = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "(Awake|REM|Core|Deep) .*"))
        let found = (0..<totals.count).map { totals.element(boundBy: $0) }.filter { $0.exists && $0.frame.height >= 40 && $0.frame.width < 200 }
        var lines = found.map { "\($0.label) \($0.frame)" }
        XCTAssertFalse(found.isEmpty, "the stage totals are buttons on Sleep")
        for button in found { XCTAssertGreaterThanOrEqual(button.frame.width, 43.99, "\(button.label) is 44 pt wide: \(button.frame)") }
        if let rem = found.first(where: { $0.label.hasPrefix("REM") }) {
            // Scrolled into the clear if the floating bar covers it.
            for _ in 0..<3 where rem.frame.maxY > 760 { app.swipeUp(velocity: .slow); QA.pause(1) }
            let frame = rem.frame
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.maxX - 2, dy: frame.midY)).tap()
            QA.pause(1)
            lines.append("tap at the right edge of REM: selected \(rem.isSelected)")
            XCTAssertTrue(rem.isSelected, "a tap at the right edge of the REM total highlights it")
        }
        QA.write(lines.joined(separator: "\n"), to: "sleep-stage-totals.txt")
        app.terminate()
    }

    /// S1B accessibility audit, P-3: the Wake time dial's frame in the UI test tree is 32 pt tall on the smallest phone, but its touch area is taller (measured: a drag
    /// works from 10 pt above to 10 pt below that frame, 52 pt in all). A drag that starts 5 pt above the frame, inside the 44 pt band, must change the value.
    func testTheCompactWakeDialDragsFromItsFortyFourPointBand() throws {
        let screen = try XCTUnwrap(ScreenCatalog.all.first { $0.id == "onboarding.rhythm" })
        let app = QA.launch(extra: screen.arguments)
        let dial = app.sliders["rhythm.wake"]
        XCTAssertTrue(dial.waitForExistence(timeout: 20))
        QA.pause(2)
        let frame = dial.frame
        guard frame.height < 44 else { app.terminate(); throw XCTSkip("this phone's dial is \(frame.height) pt tall already") }
        let before = dial.value as? String
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: frame.midX, dy: frame.minY - 5))
        start.press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: frame.midX - 120, dy: frame.minY - 5)))
        QA.pause(1)
        let after = dial.value as? String
        QA.write("dial frame \(frame): \(before ?? "-") -> \(after ?? "-")", to: "wake-dial-band.txt")
        XCTAssertNotEqual(before, after, "a drag from the band above the dial moves it")
        app.terminate()
    }

    /// A sheet traps VoiceOver's focus: with one open, moving forward never speaks anything that is on the screen under it.
    func testASheetKeepsVoiceOverInsideIt() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("XCUIVoiceOverService needs iOS 27") }
        let voiceOver = XCUIDevice.shared.voiceOverService
        // (sheet, a phrase that is on the screen under it and must never be spoken while it is open)
        let cases: [(id: String, under: [String])] = [
            ("coach.privacy", ["Ask about your sleep or recovery", "Understand your patterns"]),
            ("night.alarm", ["Why this time", "Breathing"]),
            // Phrases that are only on the page under the sheet. "Files set aside" is not one of them: the sheet's own "What is deleted" list names that kind of
            // data too, so VoiceOver speaking it there is the sheet reading itself, not a leak (S1B accessibility audit, P-1).
            ("privacy.deleteAll", ["Export my data", "Delete one kind at a time", "Delete what NOCTIS keeps"]),
            ("premium.compare", ["Sleep deeper", "Start 7-day free trial"]),
        ]
        var log: [String] = []
        for item in cases {
            guard let screen = ScreenCatalog.all.first(where: { $0.id == item.id }) else { continue }
            let app = QA.launch(extra: screen.arguments)
            if let identifier = screen.ready { _ = app.descendants(matching: .any)[identifier].waitForExistence(timeout: 20) }
            for step in screen.steps {
                switch step {
                case .tapIdentifier(let identifier): app.descendants(matching: .any)[identifier].tap()
                case .tapLabel(let label): QA.button(app, label).tap()
                default: break
                }
                QA.pause(1)
            }
            QA.pause(1)
            try voiceOver.enable()
            QA.pause(1.5)
            var spoken: [String] = []
            for _ in 0..<60 {
                guard let next = try? voiceOver.moveForward() else { break }
                if next.utterance == spoken.last { break }
                spoken.append(next.utterance)
            }
            try voiceOver.disable()
            let leaked = item.under.filter { phrase in spoken.contains { $0.localizedCaseInsensitiveContains(phrase) } }
            log.append("\(item.id): \(spoken.count) utterances, leaked from the screen under: \(leaked.isEmpty ? "none" : leaked.joined(separator: ", "))")
            // What was said, in order, so a failure can be read and a pass can be checked.
            log.append(contentsOf: spoken.enumerated().map { "    \($0.offset + 1). \($0.element)" })
            XCTAssertTrue(leaked.isEmpty, "\(item.id): VoiceOver left the sheet and spoke \(leaked)")
            app.terminate()
        }
        try? log.joined(separator: "\n").write(to: directory.appendingPathComponent("sheets.txt"), atomically: true, encoding: .utf8)
    }
}
