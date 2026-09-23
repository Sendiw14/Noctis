import Foundation
import HealthProviding
import Testing
@testable import RecoveryKit

struct BaselineEngineTests {
    @Test func emptyValuesProduceNoFabricatedAverage() {
        let baseline = BaselineEngine.baseline(from: [])
        #expect(baseline.averageValue == nil)
        #expect(baseline.sampleCount == 0)
        #expect(baseline.confidence == .low)
    }

    @Test func singleValueAveragesToItself() {
        let baseline = BaselineEngine.baseline(from: [55.0])
        #expect(baseline.averageValue == 55.0)
        #expect(baseline.sampleCount == 1)
    }

    @Test func averageIsComputedExactly() {
        let baseline = BaselineEngine.baseline(from: [40.0, 50.0, 60.0])
        #expect(baseline.averageValue == 50.0)
        #expect(baseline.sampleCount == 3)
    }

    @Test func zeroAndNegativeValuesAverageCorrectly() {
        // Not every real-world signal is positive-only (e.g. a balance-style
        // metric); the engine shouldn't special-case or reject these.
        let baseline = BaselineEngine.baseline(from: [-10.0, 0.0, 10.0])
        #expect(baseline.averageValue == 0.0)
    }

    // MARK: - Confidence boundaries (fullAt: 30 by default)

    @Test func confidenceIsHighAtOrAboveEightyPercentOfWindow() {
        let atBoundary = BaselineEngine.baseline(from: Array(repeating: 1.0, count: 24)) // 24/30 = 0.80
        let above = BaselineEngine.baseline(from: Array(repeating: 1.0, count: 30))
        #expect(atBoundary.confidence == .high)
        #expect(above.confidence == .high)
    }

    @Test func confidenceIsModerateBelowHighBoundary() {
        let justBelow = BaselineEngine.baseline(from: Array(repeating: 1.0, count: 23)) // 23/30 ≈ 0.767
        #expect(justBelow.confidence == .moderate)
    }

    @Test func confidenceIsModerateAtOrAboveFortyPercentOfWindow() {
        let atBoundary = BaselineEngine.baseline(from: Array(repeating: 1.0, count: 12)) // 12/30 = 0.40
        #expect(atBoundary.confidence == .moderate)
    }

    @Test func confidenceIsLowBelowFortyPercentOfWindow() {
        let justBelow = BaselineEngine.baseline(from: Array(repeating: 1.0, count: 11)) // 11/30 ≈ 0.367
        #expect(justBelow.confidence == .low)
    }

    @Test func confidenceRespectsCustomFullAtParameter() {
        let baseline = BaselineEngine.baseline(from: Array(repeating: 1.0, count: 7), fullAt: 7)
        #expect(baseline.confidence == .high)
    }

    @Test func windowDaysMatchesDocumentedDefault() {
        #expect(BaselineEngine.windowDays == 30)
    }
}
