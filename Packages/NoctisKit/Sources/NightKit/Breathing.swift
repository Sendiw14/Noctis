import BreathingKit
// What the haptics do in each breathing phase on the iPhone (APP_RULES.md R33): the patterns and the schedule are in `BreathingKit` (the Apple Watch's
// breathing uses them too), re-exported here so every iPhone module sees them as it always did.
@_exported import BreathingKit
import Foundation

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
