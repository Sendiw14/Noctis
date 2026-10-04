import Foundation

// The breathing exercise's engine (APP_RULES.md R33): the patterns, where in a pattern any moment
// falls, and what the haptics do in each phase. Pure and deterministic: a moment is a function of the
// seconds elapsed, so a test can check every boundary and the drawing only maps it.

public enum BreathingPhaseKind: String, Sendable, Equatable, CaseIterable {
    case inhale
    case hold
    case exhale
}

/// One stretch of a breath: what it is, how many whole seconds it lasts, and how full the lungs
/// are at its start and its end (0 empty, 1 full: the circle's size).
public struct BreathingPhase: Sendable, Equatable {
    public let kind: BreathingPhaseKind
    public let seconds: Int
    public let from: Double
    public let to: Double
}

/// A breathing pattern, from four whole-second numbers. All of them live in `all`, the one config.
public struct BreathingPattern: Sendable, Equatable, Hashable, Identifiable {
    public enum ID: String, Sendable, Equatable, Hashable, CaseIterable {
        case calm
        case box
        case relax
    }

    public let id: ID
    public let title: String
    public let inhale: Int
    /// Holding with full lungs, after the inhale (0 for none).
    public let holdFull: Int
    public let exhale: Int
    /// Holding with empty lungs, after the exhale (0 for none).
    public let holdEmpty: Int

    /// Calm 4-2-6, Box 4-4-4-4, Relax 4-7-8: the whole config.
    public static let all: [BreathingPattern] = [
        BreathingPattern(id: .calm, title: "Calm", inhale: 4, holdFull: 2, exhale: 6, holdEmpty: 0),
        BreathingPattern(id: .box, title: "Box", inhale: 4, holdFull: 4, exhale: 4, holdEmpty: 4),
        BreathingPattern(id: .relax, title: "Relax", inhale: 4, holdFull: 7, exhale: 8, holdEmpty: 0),
    ]

    public static let defaultID = ID.calm

    public static func pattern(_ id: ID) -> BreathingPattern {
        all.first { $0.id == id } ?? all[0]
    }

    /// The phases of one breath, in order, leaving out any that last no time.
    public var phases: [BreathingPhase] {
        var result = [BreathingPhase(kind: .inhale, seconds: inhale, from: 0, to: 1)]
        if holdFull > 0 { result.append(BreathingPhase(kind: .hold, seconds: holdFull, from: 1, to: 1)) }
        result.append(BreathingPhase(kind: .exhale, seconds: exhale, from: 1, to: 0))
        if holdEmpty > 0 { result.append(BreathingPhase(kind: .hold, seconds: holdEmpty, from: 0, to: 0)) }
        return result
    }

    public var cycleSeconds: Int { phases.reduce(0) { $0 + $1.seconds } }

    /// The numbers as people write them: "4-2-6", "4-4-4-4", "4-7-8".
    public var rhythm: String { phases.map { String($0.seconds) }.joined(separator: "-") }
}

/// Where in the exercise a moment falls.
public struct BreathingMoment: Sendable, Equatable {
    public let kind: BreathingPhaseKind
    /// The phase's place in its breath.
    public let phaseIndex: Int
    /// Which breath, from 0.
    public let cycle: Int
    public let phaseSeconds: Int
    public let secondsIntoPhase: Double
    /// The seconds the phase has left, as a number counting down: phaseSeconds at its start, 1 in
    /// its last second.
    public let countdown: Int
    /// How full the lungs are now (0...1), easing through an inhale or an exhale.
    public let level: Double
    /// How full they are when this phase ends.
    public let target: Double
    public let isComplete: Bool

    /// Unique across the exercise: it changes exactly when the phase does.
    public func phaseNumber(phasesPerCycle: Int) -> Int { cycle * phasesPerCycle + phaseIndex }

    public var secondsLeftInPhase: Double { Double(phaseSeconds) - secondsIntoPhase }
}

/// A pattern run for a length of time. The exercise is whole breaths: it ends at the end of the
/// breath that reaches the chosen length, so it is never shorter than asked and never stops mid-breath.
public struct BreathingSchedule: Sendable, Equatable {
    public static let durations = [2, 5, 10]
    public static let defaultMinutes = 5

    public let pattern: BreathingPattern
    public let minutes: Int
    public let phases: [BreathingPhase]
    public let cycles: Int
    public let totalSeconds: Int

    public init(pattern: BreathingPattern, minutes: Int) {
        self.pattern = pattern
        self.minutes = minutes
        phases = pattern.phases
        let cycle = pattern.cycleSeconds
        let wanted = max(minutes, 1) * 60
        cycles = (wanted + cycle - 1) / cycle
        totalSeconds = cycles * cycle
    }

    public var phasesPerCycle: Int { phases.count }

    /// The moment `elapsed` seconds in. A boundary belongs to the phase that begins there: at exactly
    /// 4 seconds of a 4-2-6 breath it is the hold, not the inhale.
    public func moment(at elapsed: TimeInterval) -> BreathingMoment {
        let cycleSeconds = pattern.cycleSeconds
        if elapsed >= Double(totalSeconds) {
            let last = phases.count - 1
            return BreathingMoment(
                kind: phases[last].kind, phaseIndex: last, cycle: cycles - 1, phaseSeconds: phases[last].seconds,
                secondsIntoPhase: Double(phases[last].seconds), countdown: 0, level: phases[last].to, target: phases[last].to, isComplete: true
            )
        }
        let t = max(elapsed, 0)
        let whole = Int(t.rounded(.down))
        let fraction = t - Double(whole)
        let cycle = whole / cycleSeconds
        let secondInCycle = whole % cycleSeconds
        var offset = 0
        var index = 0
        while index < phases.count - 1, secondInCycle >= offset + phases[index].seconds {
            offset += phases[index].seconds
            index += 1
        }
        let phase = phases[index]
        let into = Double(secondInCycle - offset) + fraction
        let progress = into / Double(phase.seconds)
        return BreathingMoment(
            kind: phase.kind, phaseIndex: index, cycle: cycle, phaseSeconds: phase.seconds, secondsIntoPhase: into,
            countdown: max(phase.seconds - (secondInCycle - offset), 1),
            level: phase.from + (phase.to - phase.from) * Self.ease(progress), target: phase.to, isComplete: false
        )
    }

    /// An inhale or an exhale eases in and out (a smoothstep), the way a breath does.
    public static func ease(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }
}

/// What the haptics do through one phase: a gentle swell on an inhale, a single tick on a hold, a
/// fade on an exhale. Plain numbers, so a test can check them; the Core Haptics side only plays them.
public struct BreathingHapticPlan: Sendable, Equatable {
    public enum Style: Sendable, Equatable {
        case swell
        case tick
        case fade
    }

    public struct Point: Sendable, Equatable {
        /// Seconds from the plan's start.
        public let time: Double
        public let intensity: Double
    }

    public let style: Style
    /// How long it lasts (0 for a tick).
    public let duration: Double
    public let sharpness: Double
    /// The intensity through `duration`, as control points (never more than Core Haptics takes: 16).
    public let curve: [Point]

    public static let swellRange = 0.08...0.5
    public static let fadePeak = 0.45
    public static let tickIntensity = 0.35
    public static let controlPoints = 5

    /// The plan for the rest of a phase: `into` seconds of its `seconds` have gone.
    public static func plan(for kind: BreathingPhaseKind, seconds: Int, into: Double = 0) -> BreathingHapticPlan {
        let total = Double(max(seconds, 1))
        let start = min(max(into, 0), total)
        let left = max(total - start, 0.1)
        let firstFraction = start / total
        func curve(_ intensity: (Double) -> Double) -> [Point] {
            var points: [Point] = []
            var i = 0
            while i < controlPoints {
                let u = Double(i) / Double(controlPoints - 1)
                points.append(Point(time: left * u, intensity: intensity(firstFraction + (1 - firstFraction) * u)))
                i += 1
            }
            return points
        }
        switch kind {
        case .inhale:
            let low = swellRange.lowerBound, high = swellRange.upperBound
            return BreathingHapticPlan(style: .swell, duration: left, sharpness: 0.2, curve: curve { low + (high - low) * BreathingSchedule.ease($0) })
        case .hold:
            return BreathingHapticPlan(style: .tick, duration: 0, sharpness: 0.5, curve: [Point(time: 0, intensity: tickIntensity)])
        case .exhale:
            return BreathingHapticPlan(style: .fade, duration: left, sharpness: 0.15, curve: curve { fadePeak * (1 - BreathingSchedule.ease($0)) })
        }
    }
}
