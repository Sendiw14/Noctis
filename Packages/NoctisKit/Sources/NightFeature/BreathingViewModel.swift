import DesignSystem
import Foundation
import NightKit
import Observation
import SwiftUI
import UIKit

/// How the circle should move: from `level` now to `target` over `duration`. The view animates when
/// `token` changes, which it does exactly when a phase begins, and when the exercise is paused,
/// resumed or comes back to the front (`jumped`: start from `level` rather than where it was).
public struct BreathingRing: Sendable, Equatable {
    public var token = 0
    public var level = 0.0
    public var target = 0.0
    public var duration = 0.0
    public var jumped = false
}

/// Runs the breathing exercise (APP_RULES.md R33): the pattern and length, the clock, the haptics and
/// the announcements. Where the exercise is comes from the clock, read at every whole second of it
/// (which is where every phase changes), never counted, so coming back from the lock screen is exact.
@MainActor
@Observable
public final class BreathingViewModel {
    public enum State: Sendable, Equatable {
        /// The pattern, the length and "Begin".
        case setup
        case running
        case paused
        /// Ran its whole time: the card with "Again".
        case finished
    }

    public private(set) var state: State = .setup
    public var patternID: BreathingPattern.ID
    public var minutes: Int
    /// The haptics switch, remembered. Only offered where `hapticsAvailable`.
    public private(set) var hapticsOn: Bool
    public let hapticsAvailable: Bool
    /// Where the exercise is now; nil before it begins.
    public private(set) var moment: BreathingMoment?
    /// How full the lungs are at this whole second (for Reduce Motion's level bar).
    public private(set) var level = 0.0
    public private(set) var ring = BreathingRing()
    public private(set) var remaining: TimeInterval
    /// What was just done, for the finished card.
    public private(set) var finishedPattern: BreathingPattern?
    public private(set) var finishedMinutes = 0

    static let patternKey = "noctis.breathing.pattern"
    static let minutesKey = "noctis.breathing.minutes"
    static let hapticsKey = "noctis.breathing.haptics"

    @ObservationIgnored private var schedule: BreathingSchedule
    @ObservationIgnored private var clock: SessionClock
    @ObservationIgnored private var lastPhase: Int?
    @ObservationIgnored private let haptics: any BreathingHapticsPlaying
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleeper: @Sendable (TimeInterval) async -> Void
    @ObservationIgnored private let announce: (String) -> Void
    @ObservationIgnored private let completion: () -> Void
    @ObservationIgnored private var ticker: Task<Void, Never>?

    public init(
        haptics: any BreathingHapticsPlaying, defaults: UserDefaults = .standard, now: @escaping () -> Date = { Date() },
        sleeper: @escaping @Sendable (TimeInterval) async -> Void = { seconds in try? await Task.sleep(for: .seconds(seconds)) },
        announce: @escaping (String) -> Void = { AccessibilityNotification.Announcement($0).post() },
        completion: @escaping () -> Void = { NoctisHaptics.soft() }
    ) {
        self.haptics = haptics
        self.defaults = defaults
        self.now = now
        self.sleeper = sleeper
        self.announce = announce
        self.completion = completion
        let id = defaults.string(forKey: Self.patternKey).flatMap(BreathingPattern.ID.init(rawValue:)) ?? BreathingPattern.defaultID
        let saved = defaults.integer(forKey: Self.minutesKey)
        let length = BreathingSchedule.durations.contains(saved) ? saved : BreathingSchedule.defaultMinutes
        patternID = id
        minutes = length
        hapticsAvailable = haptics.isAvailable
        hapticsOn = haptics.isAvailable && defaults.bool(forKey: Self.hapticsKey)
        let planned = BreathingSchedule(pattern: .pattern(id), minutes: length)
        schedule = planned
        clock = SessionClock(seconds: Double(planned.totalSeconds))
        remaining = Double(planned.totalSeconds)
    }

    // MARK: Derived

    public var pattern: BreathingPattern { BreathingPattern.pattern(patternID) }
    public var isActive: Bool { state == .running || state == .paused }
    /// The phase's name and its seconds counting down; nil before it begins.
    public var phaseName: String? { moment.map { BreathingCopy.phaseName($0.kind) } }
    public var countdown: Int { moment?.countdown ?? 0 }

    // MARK: Before beginning

    public func choose(pattern id: BreathingPattern.ID) {
        guard state == .setup || state == .finished else { return }
        patternID = id
        prepareSchedule()
    }

    public func choose(minutes length: Int) {
        guard state == .setup || state == .finished, BreathingSchedule.durations.contains(length) else { return }
        minutes = length
        prepareSchedule()
    }

    /// The switch. Turning it on mid-exercise plays the rest of the phase; off is silence at once.
    public func setHaptics(_ on: Bool) {
        let allowed = on && hapticsAvailable
        hapticsOn = allowed
        defaults.set(allowed, forKey: Self.hapticsKey)
        guard state == .running, let moment else { return }
        if allowed { playHaptic(for: moment) } else { haptics.stop() }
    }

    private func prepareSchedule() {
        schedule = BreathingSchedule(pattern: pattern, minutes: minutes)
        clock = SessionClock(seconds: Double(schedule.totalSeconds))
        remaining = Double(schedule.totalSeconds)
    }

    // MARK: The exercise

    public func begin() {
        guard state == .setup || state == .finished else { return }
        prepareSchedule()
        defaults.set(patternID.rawValue, forKey: Self.patternKey)
        defaults.set(minutes, forKey: Self.minutesKey)
        clock.start(at: now())
        state = .running
        lastPhase = nil
        moment = nil
        level = 0
        ring = BreathingRing(token: ring.token, level: 0, target: 0, duration: 0, jumped: true)
        refresh()
        runTicker()
    }

    public func pause() {
        guard state == .running else { return }
        clock.pause(at: now())
        state = .paused
        ticker?.cancel()
        ticker = nil
        haptics.stop()
        refresh()
        // Freeze the circle where it is.
        emitRing(level: level, target: level, duration: 0, jumped: true)
    }

    public func resume() {
        guard state == .paused else { return }
        clock.resume(at: now())
        state = .running
        refresh()
        if let moment {
            emitRing(level: moment.level, target: moment.target, duration: moment.secondsLeftInPhase, jumped: true)
            playHaptic(for: moment)
        }
        runTicker()
    }

    /// The person ends it: back to the start, quietly.
    public func end() {
        guard isActive else { return }
        stopEverything()
        state = .setup
        reset()
    }

    /// The screen was left (back to the wind-down, or the wind-down ended): nothing keeps going.
    public func leave() {
        if isActive { end() } else if state == .finished { state = .setup; reset() }
    }

    /// The app came back to the front: the clock is read at once, and the circle starts again from
    /// where the exercise really is.
    public func sceneBecameActive() {
        guard state == .running else { return }
        refresh(forceRing: true)
    }

    // MARK: Clock

    func refresh(forceRing: Bool = false) {
        guard isActive else { return }
        let moment = schedule.moment(at: clock.elapsed(at: now()))
        remaining = clock.remaining(at: now())
        if moment.isComplete {
            finish()
            return
        }
        self.moment = moment
        level = moment.level
        let number = moment.phaseNumber(phasesPerCycle: schedule.phasesPerCycle)
        let changed = number != lastPhase
        lastPhase = number
        guard state == .running, changed || forceRing else { return }
        // A phase that is just beginning flows on from the last one; anything else starts from where it is.
        let beginning = moment.secondsIntoPhase < 0.5 && !forceRing
        emitRing(level: moment.level, target: moment.target, duration: moment.secondsLeftInPhase, jumped: !beginning)
        if changed {
            announce(BreathingCopy.announcement(moment.kind, seconds: moment.phaseSeconds))
        }
        playHaptic(for: moment)
    }

    private func runTicker() {
        ticker?.cancel()
        ticker = Task { [weak self, sleeper] in
            while !Task.isCancelled {
                guard let wait = self?.nextWait() else { return }
                await sleeper(wait)
                if Task.isCancelled { return }
                guard let self, state == .running else { return }
                refresh()
            }
        }
    }

    private func nextWait() -> TimeInterval? {
        guard state == .running else { return nil }
        return clock.secondsToNextWholeSecond(at: now())
    }

    private func emitRing(level: Double, target: Double, duration: Double, jumped: Bool) {
        ring = BreathingRing(token: ring.token + 1, level: level, target: target, duration: duration, jumped: jumped)
    }

    private func playHaptic(for moment: BreathingMoment) {
        guard hapticsOn, state == .running else { return }
        haptics.play(.plan(for: moment.kind, seconds: moment.phaseSeconds, into: moment.secondsIntoPhase))
    }

    private func finish() {
        stopEverything()
        finishedPattern = pattern
        finishedMinutes = minutes
        level = 0
        remaining = 0
        emitRing(level: 0, target: 0, duration: 0, jumped: true)
        state = .finished
        completion()
        announce("Finished")
    }

    private func stopEverything() {
        ticker?.cancel()
        ticker = nil
        haptics.stop()
    }

    private func reset() {
        moment = nil
        lastPhase = nil
        level = 0
        prepareSchedule()
        emitRing(level: 0, target: 0, duration: 0, jumped: true)
    }
}

#if DEBUG
extension BreathingViewModel {
    /// For `-mockBreathing running:calm:5`: an exercise that began `seconds` ago (and, paused, stays
    /// exactly there, so a screenshot can look at one moment of it).
    public func debugBegin(pattern id: BreathingPattern.ID, seconds: Double, minutes length: Int = BreathingSchedule.defaultMinutes, paused: Bool = false) {
        guard state == .setup else { return }
        patternID = id
        minutes = length
        begin()
        clock.start(at: now().addingTimeInterval(-seconds))
        refresh(forceRing: true)
        if paused { pause() }
    }
}
#endif
