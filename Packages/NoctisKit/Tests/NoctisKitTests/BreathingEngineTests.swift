import Foundation
import Testing

@testable import NightKit

// The breathing exercise's engine (APP_RULES.md R33): the patterns, the phase scheduler's exact
// boundaries and total durations, and the haptic plans.

nonisolated struct BreathingPatternTests {
    @Test func theConfigHoldsThreePatternsAndTheirNumbers() {
        #expect(BreathingPattern.all.map(\.id) == [.calm, .box, .relax])
        #expect(BreathingPattern.all.map(\.title) == ["Calm", "Box", "Relax"])
        #expect(BreathingPattern.all.map(\.rhythm) == ["4-2-6", "4-4-4-4", "4-7-8"])
        #expect(BreathingPattern.all.map(\.cycleSeconds) == [12, 16, 19])
        #expect(BreathingPattern.pattern(.box).holdEmpty == 4)
        #expect(BreathingPattern.defaultID == .calm)
    }

    @Test(arguments: BreathingPattern.all)
    func aBreathIsItsPhasesInOrderWithNoneThatLastNoTime(pattern: BreathingPattern) {
        let phases = pattern.phases
        #expect(phases.allSatisfy { $0.seconds > 0 })
        #expect(phases.first?.kind == .inhale)
        #expect(phases.contains { $0.kind == .exhale })
        #expect(phases.reduce(0) { $0 + $1.seconds } == pattern.cycleSeconds)
    }

    @Test(arguments: BreathingPattern.all)
    func theLungsAreFullOrEmptyWhereOnePhaseMeetsTheNext(pattern: BreathingPattern) {
        let phases = pattern.phases
        var index = 0
        while index < phases.count {
            let next = phases[(index + 1) % phases.count]
            #expect(phases[index].to == next.from)
            index += 1
        }
        for phase in phases where phase.kind == .hold {
            #expect(phase.from == phase.to)
        }
    }
}

nonisolated struct BreathingScheduleTests {
    struct Row: Sendable {
        let at: TimeInterval
        let kind: BreathingPhaseKind
        let countdown: Int
        let cycle: Int
    }

    static let calm: [Row] = [
        Row(at: 0, kind: .inhale, countdown: 4, cycle: 0),
        Row(at: 0.5, kind: .inhale, countdown: 4, cycle: 0),
        Row(at: 1, kind: .inhale, countdown: 3, cycle: 0),
        Row(at: 3.999, kind: .inhale, countdown: 1, cycle: 0),
        Row(at: 4, kind: .hold, countdown: 2, cycle: 0),
        Row(at: 5, kind: .hold, countdown: 1, cycle: 0),
        Row(at: 5.999, kind: .hold, countdown: 1, cycle: 0),
        Row(at: 6, kind: .exhale, countdown: 6, cycle: 0),
        Row(at: 11, kind: .exhale, countdown: 1, cycle: 0),
        Row(at: 11.999, kind: .exhale, countdown: 1, cycle: 0),
        Row(at: 12, kind: .inhale, countdown: 4, cycle: 1),
        Row(at: 16, kind: .hold, countdown: 2, cycle: 1),
    ]

    static let box: [Row] = [
        Row(at: 3.999, kind: .inhale, countdown: 1, cycle: 0),
        Row(at: 4, kind: .hold, countdown: 4, cycle: 0),
        Row(at: 7.999, kind: .hold, countdown: 1, cycle: 0),
        Row(at: 8, kind: .exhale, countdown: 4, cycle: 0),
        Row(at: 11.999, kind: .exhale, countdown: 1, cycle: 0),
        Row(at: 12, kind: .hold, countdown: 4, cycle: 0),
        Row(at: 15.999, kind: .hold, countdown: 1, cycle: 0),
        Row(at: 16, kind: .inhale, countdown: 4, cycle: 1),
    ]

    static let relax: [Row] = [
        Row(at: 3.999, kind: .inhale, countdown: 1, cycle: 0),
        Row(at: 4, kind: .hold, countdown: 7, cycle: 0),
        Row(at: 10.999, kind: .hold, countdown: 1, cycle: 0),
        Row(at: 11, kind: .exhale, countdown: 8, cycle: 0),
        Row(at: 18.999, kind: .exhale, countdown: 1, cycle: 0),
        Row(at: 19, kind: .inhale, countdown: 4, cycle: 1),
    ]

    static func check(_ rows: [Row], pattern: BreathingPattern.ID) {
        let schedule = BreathingSchedule(pattern: BreathingPattern.pattern(pattern), minutes: 10)
        for row in rows {
            let moment = schedule.moment(at: row.at)
            #expect(moment.kind == row.kind, Comment(rawValue: "\(pattern) at \(row.at): \(moment.kind)"))
            #expect(moment.countdown == row.countdown, Comment(rawValue: "\(pattern) at \(row.at): countdown \(moment.countdown)"))
            #expect(moment.cycle == row.cycle, Comment(rawValue: "\(pattern) at \(row.at): cycle \(moment.cycle)"))
            #expect(!moment.isComplete)
        }
    }

    @Test func calmChangesPhaseExactlyAtFourSixAndTwelveSeconds() { Self.check(Self.calm, pattern: .calm) }
    @Test func boxChangesPhaseEveryFourSeconds() { Self.check(Self.box, pattern: .box) }
    @Test func relaxChangesPhaseAtFourElevenAndNineteenSeconds() { Self.check(Self.relax, pattern: .relax) }

    @Test func theLungsFillThroughAnInhaleAndEmptyThroughAnExhale() {
        let schedule = BreathingSchedule(pattern: .pattern(.calm), minutes: 2)
        #expect(schedule.moment(at: 0).level == 0)
        #expect(abs(schedule.moment(at: 2).level - 0.5) < 1e-9)
        #expect(schedule.moment(at: 4).level == 1)
        #expect(schedule.moment(at: 5).level == 1)
        #expect(schedule.moment(at: 6).level == 1)
        #expect(abs(schedule.moment(at: 9).level - 0.5) < 1e-9)
        #expect(schedule.moment(at: 12).level == 0)
        #expect(schedule.moment(at: 4).target == 1)
        #expect(schedule.moment(at: 0).target == 1)
        #expect(schedule.moment(at: 6).target == 0)
    }

    @Test func aBoxBreathHoldsFullThenEmpty() {
        let schedule = BreathingSchedule(pattern: .pattern(.box), minutes: 2)
        #expect(schedule.moment(at: 5).level == 1)
        #expect(schedule.moment(at: 13).level == 0)
        #expect(schedule.moment(at: 13).kind == .hold)
    }

    @Test(arguments: BreathingPattern.all)
    func theLevelDoesNotJumpAtAnyBoundary(pattern: BreathingPattern) {
        let schedule = BreathingSchedule(pattern: pattern, minutes: 2)
        var boundary = 0
        while boundary <= pattern.cycleSeconds * 2 {
            let before = schedule.moment(at: Double(boundary) - 1e-9).level
            let after = schedule.moment(at: Double(boundary)).level
            #expect(abs(before - after) < 1e-6, Comment(rawValue: "\(pattern.id) jumps at \(boundary)"))
            boundary += 1
        }
    }

    // MARK: Total length

    struct Length: Sendable {
        let pattern: BreathingPattern.ID
        let minutes: Int
        let seconds: Int
    }

    static let lengths: [Length] = [
        Length(pattern: .calm, minutes: 2, seconds: 120), Length(pattern: .calm, minutes: 5, seconds: 300), Length(pattern: .calm, minutes: 10, seconds: 600),
        Length(pattern: .box, minutes: 2, seconds: 128), Length(pattern: .box, minutes: 5, seconds: 304), Length(pattern: .box, minutes: 10, seconds: 608),
        Length(pattern: .relax, minutes: 2, seconds: 133), Length(pattern: .relax, minutes: 5, seconds: 304),
        Length(pattern: .relax, minutes: 10, seconds: 608),
    ]

    @Test(arguments: lengths)
    func theTotalIsWholeBreathsJustReachingTheChosenLength(length: Length) {
        let schedule = BreathingSchedule(pattern: .pattern(length.pattern), minutes: length.minutes)
        #expect(schedule.totalSeconds == length.seconds)
        let cycle = schedule.pattern.cycleSeconds
        #expect(schedule.totalSeconds % cycle == 0)
        #expect(schedule.totalSeconds >= length.minutes * 60)
        #expect(schedule.totalSeconds - length.minutes * 60 < cycle)
        #expect(schedule.cycles * cycle == schedule.totalSeconds)
    }

    @Test(arguments: lengths)
    func itIsCompleteAtTheTotalAndNotASecondBefore(length: Length) {
        let schedule = BreathingSchedule(pattern: .pattern(length.pattern), minutes: length.minutes)
        let total = Double(schedule.totalSeconds)
        #expect(!schedule.moment(at: total - 0.001).isComplete)
        #expect(schedule.moment(at: total).isComplete)
        #expect(schedule.moment(at: total + 30).isComplete)
        #expect(schedule.moment(at: total).countdown == 0)
        #expect(schedule.moment(at: total).level == 0)
    }

    @Test func theChosenLengthsAreTwoFiveAndTenMinutes() {
        #expect(BreathingSchedule.durations == [2, 5, 10])
        #expect(BreathingSchedule.durations.contains(BreathingSchedule.defaultMinutes))
    }

    // MARK: Walking through it

    @Test(arguments: BreathingPattern.all)
    func walkingThroughAnExerciseVisitsEveryPhaseInOrderOnce(pattern: BreathingPattern) {
        let schedule = BreathingSchedule(pattern: pattern, minutes: 2)
        let perCycle = schedule.phasesPerCycle
        var last = -1
        var changes = 0
        var t = 0.0
        while t < Double(schedule.totalSeconds) {
            let moment = schedule.moment(at: t)
            let number = moment.phaseNumber(phasesPerCycle: perCycle)
            #expect(number == last || number == last + 1, Comment(rawValue: "\(pattern.id) skips a phase at \(t)"))
            if number != last { changes += 1 }
            last = number
            #expect((1...moment.phaseSeconds).contains(moment.countdown))
            #expect(moment.kind == schedule.phases[moment.phaseIndex].kind)
            #expect((0.0...1.0).contains(moment.level))
            t += 0.25
        }
        #expect(changes == schedule.cycles * perCycle)
    }

    @Test func aMomentBeforeTheStartIsTheStart() {
        let moment = BreathingSchedule(pattern: .pattern(.calm), minutes: 2).moment(at: -3)
        #expect(moment.kind == .inhale && moment.countdown == 4 && moment.level == 0)
    }
}

nonisolated struct BreathingHapticPlanTests {
    @Test func anInhaleSwellsFromGentleToItsPeakOverTheWholePhase() {
        let plan = BreathingHapticPlan.plan(for: .inhale, seconds: 4)
        #expect(plan.style == .swell)
        #expect(plan.duration == 4)
        #expect(plan.curve.first?.intensity == BreathingHapticPlan.swellRange.lowerBound)
        #expect(plan.curve.last?.intensity == BreathingHapticPlan.swellRange.upperBound)
        #expect(plan.curve.first?.time == 0)
        #expect(plan.curve.last?.time == 4)
        #expect(zip(plan.curve, plan.curve.dropFirst()).allSatisfy { $0.intensity <= $1.intensity && $0.time < $1.time })
    }

    @Test func aHoldIsOneSoftTick() {
        let plan = BreathingHapticPlan.plan(for: .hold, seconds: 7)
        #expect(plan.style == .tick)
        #expect(plan.duration == 0)
        #expect(plan.curve == [BreathingHapticPlan.Point(time: 0, intensity: BreathingHapticPlan.tickIntensity)])
    }

    @Test func anExhaleFadesToNothingAtTheEndOfThePhase() {
        let plan = BreathingHapticPlan.plan(for: .exhale, seconds: 6)
        #expect(plan.style == .fade)
        #expect(plan.duration == 6)
        #expect(plan.curve.first?.intensity == BreathingHapticPlan.fadePeak)
        #expect(plan.curve.last?.intensity == 0)
        #expect(zip(plan.curve, plan.curve.dropFirst()).allSatisfy { $0.intensity >= $1.intensity })
    }

    @Test func joiningAPhaseHalfwayPlaysOnlyItsRest() {
        let plan = BreathingHapticPlan.plan(for: .inhale, seconds: 4, into: 2)
        #expect(plan.duration == 2)
        // Half-way up an eased swell is half-way between low and peak.
        let middle = (BreathingHapticPlan.swellRange.lowerBound + BreathingHapticPlan.swellRange.upperBound) / 2
        #expect(abs((plan.curve.first?.intensity ?? 0) - middle) < 1e-9)
        #expect(plan.curve.last?.intensity == BreathingHapticPlan.swellRange.upperBound)
    }

    @Test(arguments: BreathingPhaseKind.allCases, [1, 4, 8])
    func everyPlanStaysInsideWhatCoreHapticsTakes(kind: BreathingPhaseKind, seconds: Int) {
        let plan = BreathingHapticPlan.plan(for: kind, seconds: seconds)
        #expect(plan.curve.count <= 16 && !plan.curve.isEmpty)
        #expect(plan.curve.allSatisfy { (0.0...1.0).contains($0.intensity) && $0.time >= 0 && $0.time <= max(plan.duration, 0) })
        #expect((0.0...1.0).contains(plan.sharpness))
        #expect(plan.duration <= 30)
    }
}

nonisolated struct SessionClockTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func itCountsFromTheStartAndStopsAtThePlannedLength() {
        var clock = SessionClock(seconds: 120)
        #expect(clock.elapsed(at: start) == 0)
        #expect(!clock.hasStarted)
        clock.start(at: start)
        #expect(clock.elapsed(at: start.addingTimeInterval(30)) == 30)
        #expect(clock.remaining(at: start.addingTimeInterval(30)) == 90)
        #expect(!clock.isComplete(at: start.addingTimeInterval(119.9)))
        #expect(clock.isComplete(at: start.addingTimeInterval(120)))
        #expect(clock.elapsed(at: start.addingTimeInterval(500)) == 120)
    }

    @Test func timePausedDoesNotCount() {
        var clock = SessionClock(seconds: 300)
        clock.start(at: start)
        clock.pause(at: start.addingTimeInterval(10))
        #expect(clock.isPaused)
        #expect(clock.elapsed(at: start.addingTimeInterval(100)) == 10)
        clock.resume(at: start.addingTimeInterval(100))
        #expect(!clock.isPaused)
        #expect(clock.elapsed(at: start.addingTimeInterval(105)) == 15)
        clock.pause(at: start.addingTimeInterval(110))
        clock.pause(at: start.addingTimeInterval(150))
        clock.resume(at: start.addingTimeInterval(160))
        #expect(clock.elapsed(at: start.addingTimeInterval(160)) == 20)
    }

    @Test func itWaitsForTheNextWholeSecondOfTheSession() {
        var clock = SessionClock(seconds: 60)
        clock.start(at: start)
        #expect(abs(clock.secondsToNextWholeSecond(at: start.addingTimeInterval(2.25)) - 0.75) < 1e-9)
        #expect(abs(clock.secondsToNextWholeSecond(at: start.addingTimeInterval(3)) - 1) < 1e-9)
        #expect(clock.secondsToNextWholeSecond(at: start.addingTimeInterval(2.9999)) >= 0.005)
    }
}
