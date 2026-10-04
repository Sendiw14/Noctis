import Foundation
import NoctisWidgetKit
import SoundKit

/// Keeps the Sleep sounds control true (APP_RULES.md R48). Watches the one sound player and, when what a control would draw changes (a sound
/// starts, stops, or its sleep timer moves), writes the record in the App Group and asks the system to redraw the control. The record
/// exists only while a sound plays; with no file the control shows off, so a stop, a deletion and a launch with nothing playing all look the
/// same and nothing is kept about what was played.
///
/// It writes only on a change, so the system's reload budget is spent on real changes. (A control's own intent also asks for the redraw
/// whatever happened, so a toggle the system flipped can never keep showing something that did not come true.)
@MainActor
public final class SleepSoundsPublisher {
    private let store: SleepSoundsStore?
    private let reload: () -> Void
    private var written: SleepSoundsState?
    private var latest: SleepSoundsState?
    private var isSuspended = false
    private let sleeper: @Sendable (TimeInterval) async -> Void
    /// A stop the control asked for is in its fade: the control already shows off, and the sound that is still audible for a second is not
    /// written back (that would flicker the toggle on again).
    private var isStopping = false
    private var stoppingToken = 0

    /// `store` is nil where the App Group is not available; the publisher then does nothing. What is on disk is where it starts from, so a
    /// record left by a process the system ended is corrected by the first state it sees.
    public init(
        store: SleepSoundsStore?, reload: @escaping () -> Void = {},
        sleeper: @escaping @Sendable (TimeInterval) async -> Void = { seconds in try? await Task.sleep(for: .seconds(seconds)) }
    ) {
        self.store = store
        self.reload = reload
        self.sleeper = sleeper
        // A file nothing can read (another version's, or damaged) says "off" and would never be corrected: remove it.
        if let store, store.exists, store.load() == nil { store.delete() }
        written = store?.load()
    }

    /// What a control should show for the player in `state`: playing, until when, or nothing. Paused, interrupted (a call, an alarm) and
    /// stopped are all "not playing": the control must not claim a sound is heard when it is not.
    public static func record(for state: SoundPlayerState) -> SleepSoundsState? {
        guard state.phase == .playing else { return nil }
        return SleepSoundsState(endsAt: state.timer?.end)
    }

    /// The player changed: write and redraw if what a control draws did.
    public func apply(_ state: SoundPlayerState) {
        let record = Self.record(for: state)
        latest = record
        if record == nil { isStopping = false }
        guard !isSuspended, record != written, !(isStopping && record != nil) else { return }
        write(record)
    }

    /// A control (or Siri) asked a sound to play: whatever fade was riding out is over, and the player's state is what the control shows.
    public func started() {
        isStopping = false
        stoppingToken += 1
        guard !isSuspended, latest != written else { return }
        write(latest)
    }

    /// A control asked the sound to stop. The sound fades for a second before the player says it has stopped, but the control was flipped off
    /// and must stay off: the record goes now and the control is redrawn. After the fade (`seconds`) the player's own state decides again, so a
    /// sound that was started again in the meantime shows as playing.
    public func stopping(within seconds: TimeInterval = 1.5) {
        guard !isSuspended else { return }
        // Nothing playing: there is no fade to ride out, and the control's own intent redraws it.
        guard latest != nil else { return }
        isStopping = true
        stoppingToken += 1
        let mine = stoppingToken
        write(nil)
        Task { [weak self, sleeper] in
            await sleeper(seconds)
            guard let self, stoppingToken == mine else { return }
            isStopping = false
            guard !isSuspended, latest != written else { return }
            write(latest)
        }
    }

    /// Deletes the record (Data management). A sound that plays afterwards is written again, by `apply`.
    public func forget() {
        store?.delete()
        written = nil
        reload()
    }

    /// Stops writing for good: the app is deleting its data and will start over.
    public func suspend() {
        isSuspended = true
    }

    private func write(_ record: SleepSoundsState?) {
        guard let store else { return }
        if let record {
            guard store.save(record) else { return }
        } else {
            store.delete()
        }
        written = record
        reload()
    }
}
