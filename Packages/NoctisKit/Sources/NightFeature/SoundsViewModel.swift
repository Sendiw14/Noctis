import DesignSystem
import Foundation
import Observation
import SoundKit

/// What the Sounds screen reads (APP_RULES.md R20, R31): the player's state through an observable
/// facade, the meter's last 24 bars, and the sleep timer's time left. The player is the one object
/// that holds the engine; this only asks it things.
@MainActor
@Observable
public final class SoundsViewModel {
    public private(set) var state: SoundPlayerState
    public private(set) var meter = SoundMeterHistory()
    /// Seconds left on the sleep timer; nil without one.
    public private(set) var remaining: TimeInterval?
    public var isTimerSheetPresented = false

    @ObservationIgnored private let player: SoundPlayer
    @ObservationIgnored private let now: () -> Date
    /// The timer a sound starts with when it begins from silence (a preference; off unless Settings says).
    @ObservationIgnored private let defaultTimer: () -> SleepTimerChoice
    @ObservationIgnored private let sleeper: @Sendable (TimeInterval) async -> Void
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var ticker: Task<Void, Never>?

    public init(
        player: SoundPlayer, now: @escaping () -> Date = { Date() }, haptic: @escaping () -> Void = { NoctisHaptics.soft() },
        defaultTimer: @escaping () -> SleepTimerChoice = { .off },
        sleeper: @escaping @Sendable (TimeInterval) async -> Void = { seconds in try? await Task.sleep(for: .seconds(seconds)) }
    ) {
        self.player = player
        self.now = now
        self.defaultTimer = defaultTimer
        self.sleeper = sleeper
        state = player.state
        player.onChange = { [weak self] state in self?.apply(state) }
        player.onLevel = { [weak self] level in self?.receive(level) }
        // The timer ran out: one soft haptic. (The caption is the state's `timerFinished`.)
        player.onTimerFinished = { haptic() }
        refreshRemaining()
    }

    // MARK: Content

    public var tiles: [SoundTileContent] { SoundsBuilder.tiles(state) }
    public var nowPlaying: NowPlayingContent? { SoundsBuilder.nowPlaying(state, remaining: remaining) }
    public var timerChoices: [(choice: SleepTimerChoice, isSelected: Bool)] { SoundsBuilder.timerChoices(state) }
    /// "Sleep well.": the timer ran out and the sound has faded.
    public var showsSleepWell: Bool { state.timerFinished && state.phase == .stopped }
    /// 24 bars for the waveform, or flat while nothing plays.
    public var bars: [Float] { state.phase == .playing ? meter.bars : [Float](repeating: 0, count: SoundMeterScale.barCount) }
    public var level: Float { state.phase == .playing ? meter.latest : 0 }

    // MARK: The person's controls

    /// A tile: plays that sound, or pauses it if it is the one playing, or plays it again if it is paused.
    public func tap(_ kind: SoundKind) {
        let startsFromSilence = state.phase == .stopped
        defer {
            // A sound that begins from silence takes the timer Settings says it should; one that takes
            // over from another keeps the timer that is running.
            if startsFromSilence, player.state.phase != .stopped {
                let timer = defaultTimer()
                if timer != .off { player.setTimer(timer) }
            }
        }
        if state.kind == kind, state.phase != .stopped {
            switch state.phase {
            case .playing: player.pause()
            case .paused, .interrupted: player.resume()
            case .stopped: player.play(kind)
            }
        } else {
            player.play(kind)
        }
        NoctisHaptics.selection()
    }

    /// Plays `kind` and never pauses it: a request from Siri, Shortcuts or a control, where "play" must not stop a sound that is playing. A sound
    /// that begins from silence takes the default timer, as a tile does; nothing is felt (the phone may be locked).
    public func play(_ kind: SoundKind) {
        let startsFromSilence = state.phase == .stopped
        switch (state.kind == kind, state.phase) {
        case (true, .playing): return
        case (true, .paused), (true, .interrupted): player.resume()
        default: player.play(kind)
        }
        if startsFromSilence, player.state.phase != .stopped {
            let timer = defaultTimer()
            if timer != .off { player.setTimer(timer) }
        }
    }

    /// Stops what plays, with the short fade the Sounds screen uses: a request from a control.
    public func stopPlaying() {
        guard player.state.isLoaded else { return }
        player.fadeOutAndStop(over: 1)
    }

    public func togglePlayPause() {
        switch state.phase {
        case .playing: player.pause()
        case .paused, .interrupted: player.resume()
        case .stopped: break
        }
        NoctisHaptics.selection()
    }

    public func setGain(_ gain: Float) {
        guard let kind = state.kind else { return }
        player.setGain(gain, for: kind)
    }

    public func selectTimer(_ choice: SleepTimerChoice) {
        player.setTimer(choice)
        NoctisHaptics.selection()
        isTimerSheetPresented = false
    }

    public func presentTimer() {
        isTimerSheetPresented = true
    }

    // MARK: Appearing

    /// The screen is showing: the meter and the countdown run, and nothing runs when it isn't.
    public func appear() {
        isVisible = true
        player.reconcile()
        player.setMeterEnabled(true)
        refreshRemaining()
        restartTicker()
    }

    public func disappear() {
        isVisible = false
        player.setMeterEnabled(false)
        meter.reset()
        ticker?.cancel()
        ticker = nil
    }

    // MARK: Following the player

    private func apply(_ new: SoundPlayerState) {
        state = new
        if new.phase != .playing { meter.reset() }
        refreshRemaining()
        restartTicker()
    }

    private func receive(_ level: Float) {
        guard isVisible, state.phase == .playing else { return }
        meter.push(rms: level)
    }

    private func refreshRemaining() {
        remaining = state.timer.map { $0.remaining(at: now()) }
    }

    /// One tick a second while the timer's time is on screen; none otherwise.
    private func restartTicker() {
        ticker?.cancel()
        ticker = nil
        guard isVisible, state.timer != nil else { return }
        ticker = Task { [weak self, sleeper] in
            while !Task.isCancelled {
                await sleeper(1)
                if Task.isCancelled { return }
                guard let self else { return }
                refreshRemaining()
                if state.timer == nil { return }
            }
        }
    }
}
