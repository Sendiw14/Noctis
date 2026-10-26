import Foundation
import Testing

@testable import DesignSystem
@testable import HealthProviding
@testable import NoctisCore
@testable import OnboardingFeature

// Onboarding step 4 (Connect your signals), in the band style: the redesign changes how the step looks and not what it asks for. The three types are the
// same as before, the cards say what the design says, and the usage description in project.yml is the one the step shipped with (ConfigAuditTests holds
// the rest of the file to the keys the app needs).
struct HealthStepTests {
    @Test func theStepAsksForTheSameThreeTypesInTheSameOrder() {
        #expect(HealthStepFacts.requestedKinds == [.sleepAnalysis, .heartRate, .hrv])
    }

    @Test func theCardsSayWhatTheDesignSays() {
        #expect(HealthStepFacts.requestedKinds.map(HealthStepFacts.title) == ["Sleep", "Heart rate", "HRV"])
        #expect(
            HealthStepFacts.requestedKinds.map(HealthStepFacts.line) == [
                "How long and consistently you sleep", "Puts your recovery trend in context", "Your recovery signal vs your own baseline",
            ])
        #expect(HealthStepFacts.requestedKinds.map(\.systemImage) == ["bed.double.fill", "heart.fill", "waveform.path.ecg"])
    }

    @Test func voiceOverReadsTheTitleThenTheLine() {
        #expect(HealthStepFacts.spoken(.sleepAnalysis) == "Sleep, how long and consistently you sleep")
        #expect(HealthStepFacts.spoken(.hrv) == "HRV, your recovery signal vs your own baseline")
    }

    @Test func thePrivacyCardUsesTheInventorysSentence() throws {
        let note = try #require(PrivacyStatements.readOnlyNote(.shared))
        #expect(note.hasPrefix("Read-only."), "the card sets the first word in bold and needs the full stop to split on")
    }

    @Test func theUsageDescriptionIsTheOneTheStepShippedWith() throws {
        let yml = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("project.yml"), encoding: .utf8)
        let expected =
            "NOCTIS reads your sleep, heart rate, resting heart rate, heart rate variability and respiratory rate from Apple Health to build your sleep plan, show your recovery trends and keep your widgets up to date. It never writes to Health."
        #expect(yml.contains("INFOPLIST_KEY_NSHealthShareUsageDescription: \"\(expected)\""))
    }
}
