import DesignSystem
import Foundation
import NightKit
import NoctisCore
import NoctisWidgetKit
import Observation
import SoundKit
import UIKit

/// Runs a wind-down session (APP_RULES.md R32): the state machine and the clock, the sound, the
/// screen staying awake, and what is remembered. Progress is read from the clock once a second,
/// never counted, so locking the phone loses nothing and coming back catches up at once.
@MainActor
@Observable
public final class WindDownViewModel {
    public private(set) var state: WindDownState = .idle
    /// 0...1, from the clock.
    public private(set) var progress: Double = 0
    public private(set) var remaining: TimeInterval
    public var plannedMinutes: Int
    /// The sound chosen before beginning; nil for none.
    public var sound: SoundKind?
    /// A sound was started for this session (the toggle's last word; the player knows what plays).
    public private(set) var soundIsOn = false
    /// The person ended it before its time.
    public private(set) var endedEarly = false
    /// For the finish card.
    public private(set) var alarm: AlarmStatus?

    public static let soundFadeSeconds = 4.0
    public static let endingSeconds = 2.5
    /// "Wind-down complete" stays on the Lock Screen this long (when the time ran out) before the Live Activity goes.
    public static let activityDismissSeconds = 10.0
    static let minutesKey = AppPreferences.Key.windDownMinutes
    static let soundKey = AppPreferences.Key.windDownSound

    @ObservationIgnored private var clock: WindDownClock
    @ObservationIgnored private let player: SoundPlayer
    @ObservationIgnored private let alarmService: AlarmService
    @ObservationIgnored private let store: any WindDownSessionStoring
    @ObservationIgnored private let idle: any IdleTimerControlling
    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleeper: @Sendable (TimeInterval) async -> Void
    @ObservationIgnored private let haptic: () -> Void
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var ending: Task<Void, Never>?
    @ObservationIgnored private var sessionID: UUID?
    @ObservationIgnored private var storeTask: Task<Void, Never>?
    /// The Live Activity (APP_RULES.md R49): started with the session, kept in step with pausing and resuming, ended when it ends. Nil where
    /// there is none (a test that does not look, an app that has not set it up).
    @ObservationIgnored public var activity: (any WindDownActivityHosting)?
    @ObservationIgnored var reducedMotionOverride: Bool?
    #if DEBUG
    /// For `-mockWindDown running:0.1:breathing`: an activity to open as the screen appears.
    @ObservationIgnored var debugOpensActivity: WindDownActivity?
    #endif

    public init(
        player: SoundPlayer, alarm: AlarmService, store: any WindDownSessionStoring, idle: any IdleTimerControlling,
        preferences: AppPreferences, now: @escaping () -> Date = { Date() }, haptic: @escaping () -> Void = { NoctisHaptics.soft() },
        sleeper: @escaping @Sendable (TimeInterval) async -> Void = { seconds in try? await Task.sleep(for: .seconds(seconds)) }
    ) {
        self.player = player
        self.alarmService = alarm
        self.store = store
        self.idle = idle
        self.preferences = preferences
        self.now = now
        self.haptic = haptic
        self.sleeper = sleeper
        let minutes = preferences.values.windDownMinutes
        plannedMinutes = minutes
        sound = preferences.values.windDownSound
        clock = WindDownClock(minutes: minutes)
        remaining = clock.plannedSeconds
    }

    // MARK: Derived

    public var stage: WindDownStage { WindDownStage.stage(for: progress) }
    public var countdown: NoctisMetricValue { WindDownCountdown.metric(remaining: remaining) }
    public var isActive: Bool { state == .running || state == .paused }

    // MARK: Before beginning

    /// The screen opened. `autostart` (a Siri-ready route) begins at once; a session already
    /// under way is left as it is, and a finished one starts over.
    public func prepare(autostart: Bool) {
        if state == .finished { reset() }
        // Settings may have changed the defaults since the last time the screen opened.
        if state == .idle { refreshFromPreferences() }
        if autostart, state == .idle { begin() }
    }

    /// The length and the sound the wind-down starts with: the person's last choice, or what Settings says.
    func refreshFromPreferences() {
        let minutes = preferences.values.windDownMinutes
        plannedMinutes = minutes
        sound = preferences.values.windDownSound
        clock = WindDownClock(minutes: minutes)
        remaining = clock.plannedSeconds
    }

    public func choose(minutes: Int) {
        guard state == .idle, WindDownClock.options.contains(minutes) else { return }
        plannedMinutes = minutes
        clock = WindDownClock(minutes: minutes)
        remaining = clock.plannedSeconds
    }

    public func choose(sound: SoundKind?) {
        guard state == .idle else { return }
        self.sound = sound
    }

    // MARK: The session

    public func begin() {
        guard state == .idle else { return }
        state = WindDownMachine.reduce(state, .begin)
        clock = WindDownClock(minutes: plannedMinutes)
        clock.start(at: now())
        progress = 0
        remaining = clock.plannedSeconds
        endedEarly = false
        idle.setDisabled(true)
        preferences.update {
            $0.windDownMinutes = plannedMinutes
            $0.windDownSound = sound
        }
        haptic()
        if let sound {
            player.play(sound)
            soundIsOn = true
        } else {
            soundIsOn = false
        }
        let start = now()
        let minutes = plannedMinutes
        if let state = activityState(.running) { activity?.start(WindDownActivityAttributes(plannedMinutes: minutes, startedAt: start), state: state) }
        storeTask = Task { [store] in
            let id = await store.begin(start: start, plannedMinutes: minutes)
            self.sessionID = id
        }
        runTicker()
    }

    public func pause() {
        guard state == .running else { return }
        state = WindDownMachine.reduce(state, .pause)
        clock.pause(at: now())
        ticker?.cancel()
        ticker = nil
        refresh()
        if self.state == .paused, let state = activityState(.paused) { activity?.update(state) }
    }

    public func resume() {
        guard state == .paused else { return }
        state = WindDownMachine.reduce(state, .resume)
        clock.resume(at: now())
        refresh()
        runTicker()
        if let state = activityState(.running) { activity?.update(state) }
    }

    public func toggleSound() {
        // The player knows what is playing (the person may have changed it in the Sounds panel).
        if player.state.phase == .playing {
            player.fadeOutAndStop(over: 1)
            soundIsOn = false
        } else {
            let kind = sound ?? .brown
            sound = kind
            player.play(kind)
            soundIsOn = true
        }
        NoctisHaptics.selection()
    }

    /// The person ends it early.
    public func end() {
        guard isActive else { return }
        finish(completed: false)
    }

    /// The app came back to the front: the clock is read at once, whatever happened meanwhile.
    public func sceneBecameActive() {
        refresh()
    }

    /// After the finish card.
    public func done() {
        reset()
    }

    func reset() {
        // A session still under way that is reset (not ended) takes its Live Activity with it.
        if isActive { activity?.end(finalState: nil, dismissAfter: 0) }
        ticker?.cancel()
        ticker = nil
        ending?.cancel()
        ending = nil
        state = WindDownMachine.reduce(state, .reset)
        progress = 0
        endedEarly = false
        clock = WindDownClock(minutes: plannedMinutes)
        remaining = clock.plannedSeconds
        sessionID = nil
    }

    // MARK: Clock

    /// Reads the clock: progress and time left, and the end if its time has come.
    func refresh() {
        guard isActive else { return }
        let moment = now()
        progress = clock.progress(at: moment)
        remaining = clock.remaining(at: moment)
        if clock.isComplete(at: moment) { finish(completed: true) }
    }

    /// The Live Activity's state for the session as its clock holds it: one place works the window out (`WindDownActivityState`).
    private func activityState(_ phase: WindDownActivityAttributes.ContentState.Phase) -> WindDownActivityAttributes.ContentState? {
        guard let startedAt = clock.startedAt else { return nil }
        return WindDownActivityState.make(phase: phase, startedAt: startedAt, pausedTotal: clock.pausedTotal, plannedSeconds: clock.plannedSeconds, pausedAt: clock.pausedAt)
    }

    private func runTicker() {
        ticker?.cancel()
        ticker = Task { [weak self, sleeper] in
            while !Task.isCancelled {
                await sleeper(1)
                if Task.isCancelled { return }
                guard let self, state == .running else { return }
                refresh()
            }
        }
    }

    private func finish(completed: Bool) {
        guard isActive else { return }
        ticker?.cancel()
        ticker = nil
        state = WindDownMachine.reduce(state, completed ? .reachedEnd : .endEarly)
        endedEarly = !completed
        if completed {
            progress = 1
            remaining = 0
        }
        // The Live Activity: "Wind-down complete" for a moment when the time ran out, gone at once when the person ended it.
        if completed {
            activity?.end(finalState: activityState(.ending), dismissAfter: Self.activityDismissSeconds)
        } else {
            activity?.end(finalState: nil, dismissAfter: 0)
        }
        // A soft haptic, the sound fading, the screen free to sleep again.
        haptic()
        if player.state.isLoaded { player.fadeOutAndStop(over: Self.soundFadeSeconds) }
        soundIsOn = false
        idle.setDisabled(false)
        ending = Task { [weak self, sleeper] in
            await sleeper(Self.endingSeconds)
            if Task.isCancelled { return }
            await self?.settle(completed: completed)
        }
    }

    private func settle(completed: Bool) async {
        state = WindDownMachine.reduce(state, .endingDone)
        ending = nil
        await storeTask?.value
        if let sessionID { await store.finish(sessionID, completed: completed) }
        alarm = await alarmService.status()
    }
}

#if DEBUG
extension WindDownViewModel {
    /// For `-mockWindDown running:0.3`: a session that began `progress` of its time ago.
    public func debugBegin(progress: Double, reducedMotion: Bool = false, opening words: [String] = []) {
        guard state == .idle else { return }
        debugOpensActivity = words.compactMap(WindDownActivity.init(rawValue:)).first
        begin()
        clock = WindDownClock(minutes: plannedMinutes)
        clock.start(at: now().addingTimeInterval(-progress * clock.plannedSeconds))
        reducedMotionOverride = reducedMotion ? true : nil
        refresh()
    }

    /// For `-mockWindDown finished`: a session that has just ended early.
    public func debugFinish() {
        begin()
        end()
    }
}
#endif

/// The real idle timer.
public struct ApplicationIdleTimer: IdleTimerControlling {
    public init() {}

    public func setDisabled(_ disabled: Bool) {
        Task { @MainActor in UIApplication.shared.isIdleTimerDisabled = disabled }
    }
}
