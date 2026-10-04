import DesignSystem
import Foundation
import NightKit
import NoctisCore
import Observation
import SoundKit
import SwiftUI

/// Runs a meditation (APP_RULES.md R34): the category and length, the clock, the line on screen, the
/// chimes, the voice if asked, and a quiet sound underneath if chosen. Where the session is comes from the
/// clock, read at every whole second and at every cue, never counted, so coming back from the lock screen
/// is exact: a cue that was missed is not played late, but the line on screen is the right one.
@MainActor
@Observable
public final class MeditationViewModel {
    public enum State: Sendable, Equatable {
        case setup
        case running
        case paused
        case finished
    }

    public private(set) var state: State = .setup
    public var categoryID: MeditationCategory
    public var minutes: Int
    /// "Spoken guidance", OFF until switched on, and only offered where `canSpeak`.
    public private(set) var spokenOn: Bool
    public let canSpeak: Bool
    /// The sleep sound chosen to play underneath, if any.
    public private(set) var sound: SoundKind?
    /// The catalog key of the line on screen; nil before the first line and for Quiet mind.
    public private(set) var lineKey: String?
    /// 0 at the start, 1 at the end, as of the last whole second.
    public private(set) var progress = 0.0
    public private(set) var remaining: TimeInterval
    public private(set) var finishedCategory: MeditationCategory?
    public private(set) var finishedMinutes = 0

    /// How loud a sound underneath is: quiet, and put back as it was when it is done.
    public static let underlayGain: Float = 0.2
    public static let underlayFadeSeconds = 4.0
    /// A cue this far past its time is not played late.
    static let staleSeconds = 3.0
    static let categoryKey = "noctis.meditation.category"
    static let minutesKey = "noctis.meditation.minutes"
    static let spokenKey = "noctis.meditation.spoken"
    static let soundKey = "noctis.meditation.sound"

    @ObservationIgnored private var schedule: MeditationSchedule
    @ObservationIgnored private var clock: SessionClock
    @ObservationIgnored private var nextCue = 0
    @ObservationIgnored private let audio: any MeditationAudioPlaying
    @ObservationIgnored private let player: SoundPlayer
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleeper: @Sendable (TimeInterval) async -> Void
    @ObservationIgnored private let announce: (String) -> Void
    @ObservationIgnored private let completion: () -> Void
    @ObservationIgnored private let localize: (String) -> String
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var releaseTask: Task<Void, Never>?
    @ObservationIgnored private var restoreTask: Task<Void, Never>?
    @ObservationIgnored private var startedUnderlay: SoundKind?
    @ObservationIgnored private var savedGain: (kind: SoundKind, gain: Float)?

    public init(
        audio: any MeditationAudioPlaying, player: SoundPlayer, defaults: UserDefaults = NoctisUserDefaults.standard, now: @escaping () -> Date = { Date() },
        sleeper: @escaping @Sendable (TimeInterval) async -> Void = { seconds in try? await Task.sleep(for: .seconds(seconds)) },
        announce: @escaping (String) -> Void = { AccessibilityNotification.Announcement($0).post() },
        completion: @escaping () -> Void = { NoctisHaptics.soft() },
        localize: @escaping (String) -> String = { MeditationCopy.string($0) }
    ) {
        self.audio = audio
        self.player = player
        self.defaults = defaults
        self.now = now
        self.sleeper = sleeper
        self.announce = announce
        self.completion = completion
        self.localize = localize
        let category = defaults.string(forKey: Self.categoryKey).flatMap(MeditationCategory.init(rawValue:)) ?? .sleep
        let saved = defaults.integer(forKey: Self.minutesKey)
        let length = MeditationSchedule.durations.contains(saved) ? saved : MeditationSchedule.defaultMinutes
        categoryID = category
        minutes = length
        canSpeak = audio.canSpeak
        spokenOn = audio.canSpeak && defaults.bool(forKey: Self.spokenKey)
        sound = defaults.string(forKey: Self.soundKey).flatMap(SoundKind.init(rawValue:))
        let planned = MeditationSchedule(category: category, minutes: length)
        schedule = planned
        clock = SessionClock(seconds: planned.totalSeconds)
        remaining = planned.totalSeconds
    }

    // MARK: Derived

    public var isActive: Bool { state == .running || state == .paused }
    public var line: String? { lineKey.map(localize) }
    /// The sound row is only offered when no sound is already playing (the wind-down's own).
    public var offersSound: Bool { player.state.phase != .playing }
    public var totalSeconds: TimeInterval { schedule.totalSeconds }

    // MARK: Before beginning

    public func choose(category: MeditationCategory) {
        guard state == .setup || state == .finished else { return }
        categoryID = category
        prepareSchedule()
    }

    public func choose(minutes length: Int) {
        guard state == .setup || state == .finished, MeditationSchedule.durations.contains(length) else { return }
        minutes = length
        prepareSchedule()
    }

    public func choose(sound kind: SoundKind?) {
        guard state == .setup || state == .finished else { return }
        sound = kind
    }

    /// The switch. Off is silence at once.
    public func setSpoken(_ on: Bool) {
        let allowed = on && canSpeak
        let wasOn = spokenOn
        spokenOn = allowed
        defaults.set(allowed, forKey: Self.spokenKey)
        if wasOn, !allowed { audio.silence() }
    }

    private func prepareSchedule() {
        schedule = MeditationSchedule(category: categoryID, minutes: minutes)
        clock = SessionClock(seconds: schedule.totalSeconds)
        remaining = schedule.totalSeconds
        progress = 0
        lineKey = nil
        nextCue = 0
    }

    // MARK: The session

    public func begin() {
        guard state == .setup || state == .finished else { return }
        prepareSchedule()
        defaults.set(categoryID.rawValue, forKey: Self.categoryKey)
        defaults.set(minutes, forKey: Self.minutesKey)
        defaults.set(sound?.rawValue ?? "none", forKey: Self.soundKey)
        releaseTask?.cancel()
        releaseTask = nil
        // "Again" straight after a finish: the last session's sound is still fading out, and would
        // stop under this one. Let it go now, so this one's own sound starts clean.
        if restoreTask != nil {
            restoreTask?.cancel()
            player.stop()
            restoreGain()
        }
        clock.start(at: now())
        state = .running
        audio.prepare()
        startUnderlay()
        refresh()
        runTicker()
    }

    public func pause() {
        guard state == .running else { return }
        clock.pause(at: now())
        state = .paused
        ticker?.cancel()
        ticker = nil
        audio.silence()
        refresh()
    }

    public func resume() {
        guard state == .paused else { return }
        clock.resume(at: now())
        state = .running
        refresh()
        runTicker()
    }

    /// The person ends it: back to the start, quietly.
    public func end() {
        guard isActive else { return }
        stopEverything()
        state = .setup
        prepareSchedule()
    }

    /// The screen was left (back to the wind-down, or the wind-down ended): nothing keeps going.
    public func leave() {
        if isActive {
            end()
        } else if state == .finished {
            state = .setup
            prepareSchedule()
        }
        releaseTask?.cancel()
        releaseTask = nil
        audio.release()
    }

    /// The app came back to the front: the clock is read at once.
    public func sceneBecameActive() {
        guard state == .running else { return }
        refresh()
    }

    // MARK: Clock

    func refresh() {
        guard isActive else { return }
        let moment = now()
        let elapsed = clock.elapsed(at: moment)
        remaining = clock.remaining(at: moment)
        progress = meditationProgress(elapsed: elapsed, total: schedule.totalSeconds)
        while nextCue < schedule.cues.count, schedule.cues[nextCue].at <= elapsed, schedule.cues[nextCue].chime != .end {
            fire(schedule.cues[nextCue], elapsed: elapsed)
            nextCue += 1
        }
        if clock.isComplete(at: moment) { finish() }
    }

    private func fire(_ cue: MeditationCue, elapsed: TimeInterval) {
        let stale = elapsed - cue.at > Self.staleSeconds
        if let key = cue.lineKey {
            lineKey = key
            if !stale {
                let text = localize(key)
                announce(text)
                if spokenOn { audio.speak(text) }
            }
        }
        if let chime = cue.chime, !stale { audio.chime(chime) }
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

    /// Until the next whole second of the session or the next cue, whichever is first.
    private func nextWait() -> TimeInterval? {
        guard state == .running else { return nil }
        let moment = now()
        let whole = clock.secondsToNextWholeSecond(at: moment)
        let elapsed = clock.elapsed(at: moment)
        if let cue = schedule.nextCueTime(after: elapsed), cue - elapsed < whole { return max(cue - elapsed, 0.005) }
        return whole
    }

    private func finish() {
        ticker?.cancel()
        ticker = nil
        audio.silence()
        audio.chime(.end)
        stopUnderlay()
        finishedCategory = categoryID
        finishedMinutes = minutes
        remaining = 0
        progress = 1
        state = .finished
        completion()
        announce("Finished")
        // The closing chime is let ring before the session is let go.
        releaseTask?.cancel()
        releaseTask = Task { [weak self, sleeper] in
            await sleeper(MeditationChimeKind.end.seconds + 1)
            if Task.isCancelled { return }
            self?.audio.release()
        }
    }

    private func stopEverything() {
        ticker?.cancel()
        ticker = nil
        audio.silence()
        stopUnderlay()
        audio.release()
    }

    // MARK: A sound underneath

    private func startUnderlay() {
        guard let kind = sound, player.state.phase != .playing else { return }
        if let saved = savedGain, saved.kind != kind {
            player.setGain(saved.gain, for: saved.kind)
            savedGain = nil
        }
        if savedGain == nil { savedGain = (kind, player.state.gain(for: kind)) }
        restoreTask?.cancel()
        restoreTask = nil
        player.setGain(Self.underlayGain, for: kind)
        player.play(kind)
        startedUnderlay = kind
    }

    /// Fades out the sound this session started and, once it is quiet, puts its volume back as the person had it.
    private func stopUnderlay() {
        guard startedUnderlay != nil else { return }
        startedUnderlay = nil
        player.fadeOutAndStop(over: Self.underlayFadeSeconds)
        restoreTask?.cancel()
        restoreTask = Task { [weak self, sleeper] in
            await sleeper(Self.underlayFadeSeconds + 0.3)
            if Task.isCancelled { return }
            self?.restoreGain()
        }
    }

    private func restoreGain() {
        guard let saved = savedGain else { return }
        player.setGain(saved.gain, for: saved.kind)
        savedGain = nil
        restoreTask = nil
    }
}

#if DEBUG
extension MeditationViewModel {
    /// For `-mockMeditation running:bodyScan:10:80`: a session of `minutes` that began `seconds` ago (and, paused, stays
    /// exactly there, so a screenshot can look at one moment of it).
    public func debugBegin(category: MeditationCategory, minutes length: Int, seconds: Double, paused: Bool = false) {
        guard state == .setup else { return }
        categoryID = category
        minutes = length
        begin()
        clock.start(at: now().addingTimeInterval(-seconds))
        refresh()
        if paused { pause() }
    }
}
#endif
