import XCTest

/// Real VoiceOver (iOS 27+ simulators only): reading order on every
/// onboarding screen, and the rulers' and ring's adjustable actions.
@MainActor
final class VoiceOverQATests: XCTestCase {
    private let goals = "betterSleep,moreEnergy"

    func testVoiceOverOrderAndAdjustables() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("XCUIVoiceOverService needs iOS 27") }
        let voiceOver = XCUIDevice.shared.voiceOverService
        let screens: [(step: String, goals: String?)] = [
            ("welcome", nil), ("goal", nil), ("rhythm", goals), ("sample", goals),
            ("health", goals), ("notifications", goals), ("plan", goals), ("paywall", goals),
        ]
        var log = ""
        for screen in screens {
            let app = QA.launch(step: screen.step, goals: screen.goals)
            QA.pause(screen.step == "plan" ? 6 : 3)
            try voiceOver.enable()
            QA.pause(1.5)
            var spoken: [String] = []
            if let first = try? voiceOver.currentSpeech() { spoken.append(first.utterance) }
            var repeats = 0
            for _ in 0..<45 {
                guard let next = try? voiceOver.moveForward() else { break }
                if next.utterance == spoken.last {
                    repeats += 1
                    if repeats >= 2 { break }
                    continue
                }
                repeats = 0
                spoken.append(next.utterance)
                // Adjustables: VoiceOver's one-finger swipe up/down on the
                // focused element is its increment/decrement.
                if next.utterance.hasPrefix("Wake time") || next.utterance.hasPrefix("Sleep need") || next.utterance.hasPrefix("Sample night") {
                    app.swipeUp()
                    QA.pause(1)
                    let up = (try? voiceOver.currentSpeech())?.utterance ?? "?"
                    app.swipeDown()
                    QA.pause(1)
                    let down = (try? voiceOver.currentSpeech())?.utterance ?? "?"
                    spoken.append("   ↑ swipe up → \(up)")
                    spoken.append("   ↓ swipe down → \(down)")
                }
            }
            log += "== \(screen.step)\n" + spoken.map { "  \($0)" }.joined(separator: "\n") + "\n"
            try voiceOver.disable()
            QA.pause(1)
            app.terminate()
        }
        QA.write(log, to: "voiceover-order.txt")
    }
}
