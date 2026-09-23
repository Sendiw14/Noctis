import Foundation
import Testing
@testable import RecoveryKit

struct RecoveryEngineTests {
    @Test func missingInputsAreOmittedNotInvented() {
        let input = RecoveryInput(sleepQualityOverall: 80, sleepHours: 8)
        let score = RecoveryEngine.computeScore(input)

        #expect(score.factors.count == 1)
        #expect(score.factors.first?.kind == .sleep)
        #expect(score.confidence == .low)
    }

    @Test func higherHRVRelativeToBaselineIncreasesHRVFactorScore() {
        let baseline = Baseline(averageValue: 50, sampleCount: 20, confidence: .high)
        let lowInput = RecoveryInput(hrvToday: 45, hrvBaseline: baseline)
        let highInput = RecoveryInput(hrvToday: 65, hrvBaseline: baseline)

        let lowScore = RecoveryEngine.computeScore(lowInput).factors.first { $0.kind == .hrv }?.score ?? 0
        let highScore = RecoveryEngine.computeScore(highInput).factors.first { $0.kind == .hrv }?.score ?? 0

        #expect(highScore > lowScore)
    }

    @Test func fullInputSetYieldsHighConfidence() {
        let hrvBaseline = Baseline(averageValue: 50, sampleCount: 30, confidence: .high)
        let rhrBaseline = Baseline(averageValue: 58, sampleCount: 30, confidence: .high)
        let input = RecoveryInput(
            sleepQualityOverall: 85,
            sleepHours: 8,
            hrvToday: 55,
            hrvBaseline: hrvBaseline,
            restingHRToday: 54,
            restingHRBaseline: rhrBaseline,
            consistencyScore: 90
        )

        let score = RecoveryEngine.computeScore(input)

        #expect(score.confidence == .high)
        #expect(score.overall > 0 && score.overall <= 100)
    }
}
