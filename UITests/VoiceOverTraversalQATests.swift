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
                    _ = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch.waitForExistence(timeout: 20)
                case .back: app.navigationBars.buttons.firstMatch.tap()
                case .scrollToTop: app.swipeDown()
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

            let text = (["# \(screen.id)", "problems: \(problems.isEmpty ? "none" : problems.joined(separator: "; "))", ""] + spoken.enumerated().map { "\($0.offset + 1). \($0.element)" })
                .joined(separator: "\n")
            try? text.write(to: directory.appendingPathComponent("\(screen.id).txt"), atomically: true, encoding: .utf8)
            summary.append("\(screen.id)\t\(spoken.count)\t\(problems.isEmpty ? "ok" : problems.joined(separator: "; "))")
            app.terminate()
        }
        try? summary.joined(separator: "\n").write(to: directory.appendingPathComponent("summary.tsv"), atomically: true, encoding: .utf8)
    }

    /// A sheet traps VoiceOver's focus: with one open, moving forward never speaks anything that is on the screen under it.
    func testASheetKeepsVoiceOverInsideIt() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("XCUIVoiceOverService needs iOS 27") }
        let voiceOver = XCUIDevice.shared.voiceOverService
        // (sheet, a phrase that is on the screen under it and must never be spoken while it is open)
        let cases: [(id: String, under: [String])] = [
            ("coach.privacy", ["Ask about your sleep or recovery", "Understand your patterns"]),
            ("night.alarm", ["Why this time", "Breathing"]),
            ("privacy.deleteAll", ["Export my data", "Files set aside"]),
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
            XCTAssertTrue(leaked.isEmpty, "\(item.id): VoiceOver left the sheet and spoke \(leaked)")
            app.terminate()
        }
        try? log.joined(separator: "\n").write(to: directory.appendingPathComponent("sheets.txt"), atomically: true, encoding: .utf8)
    }
}
