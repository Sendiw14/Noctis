import CoreHaptics
import Foundation
import NightKit
import OSLog

/// Plays the breathing haptics (APP_RULES.md R33). `BreathingHapticPlan` says what; this plays it.
@MainActor
public protocol BreathingHapticsPlaying: AnyObject {
    /// This device has a Taptic Engine. The Haptics switch is only offered where it is true.
    var isAvailable: Bool { get }
    /// Plays the plan, ending whatever played before it.
    func play(_ plan: BreathingHapticPlan)
    /// Silence, and the engine let go (a paused, ended or left exercise leaves nothing running).
    func stop()
}

/// Plays nothing. For devices and screens with no haptics, tests, and the simulator, which can pretend it has them.
@MainActor
public final class SilentBreathingHaptics: BreathingHapticsPlaying {
    public let isAvailable: Bool
    public private(set) var played: [BreathingHapticPlan] = []
    public private(set) var stops = 0

    public init(available: Bool = false) {
        isAvailable = available
    }

    public func play(_ plan: BreathingHapticPlan) { played.append(plan) }
    public func stop() { stops += 1 }
}

/// Core Haptics: a continuous event whose intensity follows the plan's curve (a swell, a fade) or one
/// soft transient (the tick). Haptics only, so it never touches the audio session the wind-down's sound
/// is playing through. A failure is silent: haptics are an extra, never a reason for the exercise to stop.
///
/// The system gives no way to read the "System Haptics" switch in Settings, so this does not try: it
/// offers the toggle only where the hardware can play haptics, and leaves the system to stay quiet when
/// the person has turned them off (to be checked on a real iPhone).
@MainActor
public final class CoreHapticsBreathing: BreathingHapticsPlaying {
    private static let log = Logger(subsystem: "com.noctis.app", category: "breathing-haptics")
    private var engine: CHHapticEngine?
    private var player: (any CHHapticAdvancedPatternPlayer)?
    private var engineIsRunning = false

    public init() {}

    public var isAvailable: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    public func play(_ plan: BreathingHapticPlan) {
        guard isAvailable else { return }
        do {
            let engine = try startedEngine()
            try? player?.stop(atTime: CHHapticTimeImmediate)
            let pattern = try Self.pattern(for: plan)
            let next = try engine.makeAdvancedPlayer(with: pattern)
            player = next
            try next.start(atTime: CHHapticTimeImmediate)
        } catch {
            Self.log.error("could not play a breathing haptic: \(String(describing: error), privacy: .public)")
        }
    }

    public func stop() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        if engineIsRunning {
            engine?.stop(completionHandler: nil)
            engineIsRunning = false
        }
    }

    private func startedEngine() throws -> CHHapticEngine {
        let engine = try self.engine ?? makeEngine()
        if !engineIsRunning {
            try engine.start()
            engineIsRunning = true
        }
        return engine
    }

    private func makeEngine() throws -> CHHapticEngine {
        let engine = try CHHapticEngine()
        engine.playsHapticsOnly = true
        engine.stoppedHandler = { [weak self] _ in
            Task { @MainActor in self?.engineStopped() }
        }
        engine.resetHandler = { [weak self] in
            Task { @MainActor in self?.engineReset() }
        }
        self.engine = engine
        return engine
    }

    private func engineStopped() {
        engineIsRunning = false
        player = nil
    }

    private func engineReset() {
        engineIsRunning = false
        player = nil
    }

    /// The plan as a Core Haptics pattern.
    static func pattern(for plan: BreathingHapticPlan) throws -> CHHapticPattern {
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(plan.sharpness))
        switch plan.style {
        case .tick:
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(plan.curve.first?.intensity ?? 0.3))
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
            return try CHHapticPattern(events: [event], parameters: [])
        case .swell, .fade:
            let base = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1)
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [base, sharpness], relativeTime: 0, duration: plan.duration)
            let points = plan.curve.map { CHHapticParameterCurve.ControlPoint(relativeTime: $0.time, value: Float($0.intensity)) }
            let curve = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: points, relativeTime: 0)
            return try CHHapticPattern(events: [event], parameterCurves: [curve])
        }
    }
}
