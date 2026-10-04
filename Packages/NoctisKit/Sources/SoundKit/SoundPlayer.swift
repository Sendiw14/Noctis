import Foundation

// The player and the three things it talks to. The protocols exist so the player's logic (what
// plays, what fades, what the system's interruptions do) can be tested without a speaker.

public enum SoundSessionEvent: Sendable, Equatable {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case routeLost
    case mediaServicesReset
}

public enum SoundRemoteCommand: Sendable, Equatable {
    case play
    case pause
    case toggle
}

/// The audio engine, as the player needs it.
@MainActor
public protocol SoundEngineDriving: AnyObject {
    func start() throws
    func pause()
    /// Stops the engine and lets it go; nothing is left running.
    func stop()
    func send(_ command: SoundCommand)
    /// Starts (a handler) or stops (nil) the level meter: a tap on the mixer, only while asked.
    func setMeter(_ handler: (@Sendable (Float) -> Void)?)
    /// Builds the engine again, after the system reset its audio services.
    func rebuild()
}

/// The audio session: playback, and the system's word about it.
@MainActor
public protocol SoundSessionDriving: AnyObject {
    var onEvent: ((SoundSessionEvent) -> Void)? { get set }
    func activate() throws
    func deactivate()
}

/// The lock screen and the headphones' controls.
@MainActor
public protocol SoundNowPlayingDriving: AnyObject {
    var onCommand: ((SoundRemoteCommand) -> Void)? { get set }
    func show(title: String, isPlaying: Bool)
    func clear()
}

public struct SoundPlayerState: Sendable, Equatable {
    public var kind: SoundKind?
    public var phase: SoundPlaybackPhase
    /// Each sound's own gain, 0...1.
    public var gains: [SoundKind: Float]
    public var timer: SleepTimerPlan?
    /// The timer ran out and the sound faded to nothing: "Sleep well".
    public var timerFinished: Bool

    public init(kind: SoundKind? = nil, phase: SoundPlaybackPhase = .stopped, gains: [SoundKind: Float] = [:], timer: SleepTimerPlan? = nil, timerFinished: Bool = false) {
        self.kind = kind
        self.phase = phase
        self.gains = gains
        self.timer = timer
        self.timerFinished = timerFinished
    }

    public func gain(for kind: SoundKind) -> Float {
        gains[kind] ?? soundDefaultGain
    }

    public var isPlaying: Bool { phase == .playing }
    public var isLoaded: Bool { kind != nil && phase != .stopped }
}

/// Where a sound's gain starts, until its slider moves: 40%.
public let soundDefaultGain: Float = 0.4

/// Plays the sleep sounds (APP_RULES.md R31). It is the one object that holds the engine: play,
/// pause, stop, a gain for each sound, a crossfade when one sound gives way to another, a sleep
/// timer with a 20 second fade, and the system's interruptions. Nothing runs when nothing plays:
/// no timer, no tap, no engine.
@MainActor
public final class SoundPlayer {
    public static let defaultGain = soundDefaultGain
    public static let crossfadeSeconds: Double = 1.5
    /// A fade in or out of a pause, a stop or a play: long enough not to click.
    public static let rampSeconds: Double = 0.3
    static let gainsKey = "noctis.sounds.gains"

    public private(set) var state: SoundPlayerState {
        didSet { if state != oldValue { onChange?(state) } }
    }
    public var onChange: ((SoundPlayerState) -> Void)?
    /// A level from the meter, at 15 Hz while the meter is on.
    public var onLevel: ((Float) -> Void)?
    /// The timer ran out (a soft haptic, once).
    public var onTimerFinished: (() -> Void)?

    private let engine: any SoundEngineDriving
    private let session: any SoundSessionDriving
    private let nowPlaying: any SoundNowPlayingDriving
    private let defaults: UserDefaults
    private let now: () -> Date
    private let sleeper: @Sendable (TimeInterval) async -> Void
    private var meterWanted = false
    private var timerTask: Task<Void, Never>?
    private var fading = false
    /// Bumped by every change of mind, so a pause or a stop that was waiting for its fade to end
    /// does nothing if the person has played again.
    private var token = 0

    public init(
        engine: any SoundEngineDriving, session: any SoundSessionDriving, nowPlaying: any SoundNowPlayingDriving,
        defaults: UserDefaults = .standard, now: @escaping () -> Date = { Date() },
        sleeper: @escaping @Sendable (TimeInterval) async -> Void = { seconds in try? await Task.sleep(for: .seconds(seconds)) }
    ) {
        self.engine = engine
        self.session = session
        self.nowPlaying = nowPlaying
        self.defaults = defaults
        self.now = now
        self.sleeper = sleeper
        state = SoundPlayerState(gains: Self.loadGains(defaults))
        session.onEvent = { [weak self] event in self?.handle(event) }
        nowPlaying.onCommand = { [weak self] command in self?.handle(command) }
    }

    // MARK: The person's controls

    /// Plays `kind`: from nothing, from a pause, or crossing from the sound that is playing.
    public func play(_ kind: SoundKind) {
        let switching = state.kind != nil && state.kind != kind
        if state.phase == .playing, switching {
            token += 1
            state.kind = kind
            state.timerFinished = false
            send(fader: 1, faderSeconds: 0, crossfade: Self.crossfadeSeconds)
            nowPlaying.show(title: kind.title, isPlaying: true)
            return
        }
        // From a pause or nothing the new sound simply begins.
        state.kind = kind
        state.timerFinished = false
        perform(SoundPlaybackPolicy.reduce(state.phase, .play))
        updateMeter()
    }

    public func pause() {
        perform(SoundPlaybackPolicy.reduce(state.phase, .pause))
        updateMeter()
    }

    public func resume() {
        guard state.kind != nil else { return }
        perform(SoundPlaybackPolicy.reduce(state.phase, .play))
        updateMeter()
    }

    public func stop() {
        perform(SoundPlaybackPolicy.reduce(state.phase, .stop))
        updateMeter()
    }

    public func setGain(_ gain: Float, for kind: SoundKind) {
        let value = min(max(gain, 0), 1)
        state.gains[kind] = value
        Self.saveGains(state.gains, to: defaults)
        if state.kind == kind, state.phase != .stopped {
            send(fader: nil, faderSeconds: 0, crossfade: 0)
        }
    }

    /// Starts, changes or (with `.off`) cancels the sleep timer. It only makes sense while a
    /// sound is loaded.
    public func setTimer(_ choice: SleepTimerChoice) {
        timerTask?.cancel()
        timerTask = nil
        // A timer that had begun its fade is called off or restarted: the sound comes back.
        let wasFading = fading
        fading = false
        if wasFading, state.phase == .playing { send(fader: 1, faderSeconds: 0.5, crossfade: 0) }
        guard choice != .off, state.isLoaded else {
            state.timer = nil
            return
        }
        state.timer = SleepTimerPlan(start: now(), choice: choice)
        runTimer()
    }

    /// Turns the level meter on or off: on only while the Sounds screen is showing and playing.
    public func setMeterEnabled(_ enabled: Bool) {
        meterWanted = enabled
        updateMeter()
    }

    /// The app came back to the front: a timer that ended while it was away has ended.
    public func reconcile() {
        guard let plan = state.timer else { return }
        if plan.phase(at: now()) == .finished { finishTimer() }
    }

    // MARK: The system's

    func handle(_ event: SoundSessionEvent) {
        let mapped: SoundPlaybackEvent = switch event {
        case .interruptionBegan: .interruptionBegan
        case .interruptionEnded(let shouldResume): .interruptionEnded(shouldResume: shouldResume)
        case .routeLost: .routeLost
        case .mediaServicesReset: .mediaServicesReset
        }
        perform(SoundPlaybackPolicy.reduce(state.phase, mapped))
        updateMeter()
    }

    func handle(_ command: SoundRemoteCommand) {
        // The lock screen's play button with nothing loaded has nothing to play.
        if state.kind == nil, state.phase == .stopped { return }
        let mapped: SoundPlaybackEvent = switch command {
        case .play: .remotePlay
        case .pause: .remotePause
        case .toggle: .remoteToggle
        }
        perform(SoundPlaybackPolicy.reduce(state.phase, mapped))
        updateMeter()
    }

    // MARK: Doing it

    private func perform(_ result: SoundPlaybackPolicy.Result) {
        let wasPhase = state.phase
        state.phase = result.phase
        switch result.action {
        case .none:
            break
        case .start:
            token += 1
            do {
                try session.activate()
                try engine.start()
            } catch {
                // It could not start (no audio hardware, the system said no): nothing is playing.
                state.phase = .stopped
                state.kind = nil
                session.deactivate()
                return
            }
            send(fader: 1, faderSeconds: Self.rampSeconds, crossfade: 0)
            show(isPlaying: true)
        case .resume:
            token += 1
            do {
                try session.activate()
                try engine.start()
            } catch {
                state.phase = wasPhase
                return
            }
            send(fader: 1, faderSeconds: Self.rampSeconds, crossfade: 0)
            show(isPlaying: true)
        case .fadeAndPause:
            send(fader: 0, faderSeconds: Self.rampSeconds, crossfade: 0)
            show(isPlaying: false)
            let mine = bump()
            Task { [weak self, sleeper] in
                await sleeper(Self.rampSeconds + 0.05)
                guard let self, token == mine, state.phase == .paused else { return }
                engine.pause()
            }
        case .pauseNow:
            send(fader: 0, faderSeconds: 0, crossfade: 0)
            engine.pause()
            show(isPlaying: false)
            _ = bump()
        case .fadeAndStop:
            send(fader: 0, faderSeconds: Self.rampSeconds, crossfade: 0)
            state.kind = nil
            cancelTimer()
            nowPlaying.clear()
            let mine = bump()
            Task { [weak self, sleeper] in
                await sleeper(Self.rampSeconds + 0.05)
                guard let self, token == mine, state.phase == .stopped else { return }
                shutDown()
            }
        case .stopNow:
            state.kind = nil
            cancelTimer()
            nowPlaying.clear()
            _ = bump()
            shutDown()
        case .rebuildAndResume:
            engine.rebuild()
            do {
                try session.activate()
                try engine.start()
            } catch {
                state.phase = .paused
                return
            }
            send(fader: 1, faderSeconds: Self.rampSeconds, crossfade: 0)
        case .rebuild:
            engine.rebuild()
        }
    }

    private func bump() -> Int {
        token += 1
        return token
    }

    /// The engine off, the session released: nothing of ours left running.
    private func shutDown() {
        engine.setMeter(nil)
        engine.stop()
        session.deactivate()
    }

    private func show(isPlaying: Bool) {
        if let kind = state.kind { nowPlaying.show(title: kind.title, isPlaying: isPlaying) }
    }

    private func send(fader: Float?, faderSeconds: Double, crossfade: Double) {
        guard let kind = state.kind else { return }
        engine.send(SoundCommand(kind: kind, gain: state.gain(for: kind), fader: fader, faderSeconds: faderSeconds, crossfadeSeconds: crossfade))
    }

    // MARK: The sleep timer

    private func runTimer() {
        timerTask = Task { [weak self, sleeper] in
            while !Task.isCancelled {
                guard let self, let plan = state.timer, let wake = plan.nextWake(after: now()) else { return }
                await sleeper(max(wake.timeIntervalSince(now()), 0))
                if Task.isCancelled { return }
                tick()
            }
        }
    }

    private func tick() {
        guard let plan = state.timer else { return }
        switch plan.phase(at: now()) {
        case .running:
            break
        case .fading(let remaining):
            guard !fading else { return }
            fading = true
            send(fader: 0, faderSeconds: remaining, crossfade: 0)
        case .finished:
            finishTimer()
        }
    }

    private func finishTimer() {
        cancelTimer()
        let was = state.phase
        perform(SoundPlaybackPolicy.reduce(was, .timerFinished))
        state.timerFinished = was != .stopped
        updateMeter()
        if was != .stopped { onTimerFinished?() }
    }

    private func cancelTimer() {
        timerTask?.cancel()
        timerTask = nil
        fading = false
        state.timer = nil
    }

    // MARK: The meter

    private func updateMeter() {
        if meterWanted, state.phase == .playing {
            engine.setMeter { [weak self] level in
                Task { @MainActor [weak self] in self?.onLevel?(level) }
            }
        } else {
            engine.setMeter(nil)
        }
    }

    // MARK: Remembering the gains

    private static func loadGains(_ defaults: UserDefaults) -> [SoundKind: Float] {
        guard let raw = defaults.dictionary(forKey: gainsKey) as? [String: Double] else { return [:] }
        var gains: [SoundKind: Float] = [:]
        for (key, value) in raw {
            if let kind = SoundKind(rawValue: key) { gains[kind] = min(max(Float(value), 0), 1) }
        }
        return gains
    }

    private static func saveGains(_ gains: [SoundKind: Float], to defaults: UserDefaults) {
        defaults.set(Dictionary(uniqueKeysWithValues: gains.map { ($0.key.rawValue, Double($0.value)) }), forKey: gainsKey)
    }
}
