import CoachFeature
import Foundation
import NightFeature
import NightKit
import NoctisCore
import NoctisIntentKit
import NoctisWidgetKit
import SoundKit

/// Where an intent's destination goes in the app (APP_RULES.md R47): the three plain screens through the strict URL router the widgets use
/// (recovery, sleep, bedtime), the rest as the `AppRoute` they are. `AppModel.open` is the one place any of them is opened; an intent holds no
/// navigation logic of its own.
public enum IntentRouting {
    /// What a destination opens: a screen, or the paywall sheet naming a context (the free plan asking for a Premium thing, R62).
    public static func destination(for destination: IntentDestination) -> WidgetURLRouter.Destination {
        switch destination {
        case .recovery: .screen(WidgetURLRouter.route(for: .recovery))
        case .sleep: .screen(WidgetURLRouter.route(for: .sleep))
        case .bedtime: .screen(WidgetURLRouter.route(for: .bedtime))
        case .windDown(let autostart): .screen(.windDown(autostart: autostart))
        case .alarm: .screen(.alarm)
        case .coach: .screen(.coach())
        case .paywall(let context): .paywall(context)
        }
    }

    /// The screen a destination opens; nil for the paywall sheet, which is not one.
    public static func route(for destination: IntentDestination) -> AppRoute? {
        if case .screen(let route) = Self.destination(for: destination) { route } else { nil }
    }
}

/// The running app, for the intents: it starts the wind-down and the sound, sets the alarm and opens screens through the same objects the
/// screens use. Installed when the app starts, in the foreground or in the background (an audio intent can launch the app unseen).
@MainActor
final class AppIntentHost: IntentHost {
    private let model: AppModel
    private let preferences: AppPreferences
    private let player: SoundPlayer
    private let sounds: SoundsViewModel
    private let alarm: AlarmService
    /// The session the End button of the Live Activity ends (R49); nil in a test that does not look.
    private let windDown: WindDownViewModel?
    /// Redraws the Sleep sounds control after one asked for something (R48); nil in a test that does not look.
    private let controls: SleepSoundsPublisher?
    /// Coach, which counts the free questions (R60); nil in a test that does not look (nothing is limited).
    private let coach: CoachViewModel?

    init(
        model: AppModel, preferences: AppPreferences, player: SoundPlayer, sounds: SoundsViewModel, alarm: AlarmService, windDown: WindDownViewModel? = nil,
        controls: SleepSoundsPublisher? = nil, coach: CoachViewModel? = nil
    ) {
        self.coach = coach
        self.model = model
        self.preferences = preferences
        self.player = player
        self.sounds = sounds
        self.alarm = alarm
        self.windDown = windDown
        self.controls = controls
    }

    func open(_ destination: IntentDestination) {
        model.open(IntentRouting.destination(for: destination))
    }

    func startWindDown(minutes: Int?) {
        // The length is the wind-down's own preference (what the screen starts with), then the screen begins it as it opens.
        if let minutes, WindDownClock.options.contains(minutes) { preferences.update { $0.windDownMinutes = minutes } }
        model.open(.windDown(autostart: true))
    }

    var lastSleepSound: SoundKind? { player.lastKind }

    func playSleepSounds(_ kind: SoundKind) -> Bool {
        // The sounds screen's own guard (the plan's list, R57) has the last word: a sound it refuses plays nothing.
        guard !sounds.isLocked(kind) else { return false }
        sounds.play(kind)
        controls?.started()
        return true
    }

    func stopSleepSounds() {
        sounds.stopPlaying()
        // The fade lasts a second after the control was flipped off: it shows off now and the player's own state decides after the fade.
        controls?.stopping()
    }

    func endWindDown() {
        windDown?.end()
    }

    func setTonightAlarm(minutes: Int) async -> AlarmIntentOutcome {
        let status = await alarm.status()
        // Only with the system's yes already given: a question is never asked from a spoken request.
        guard status.authorization == .authorized else { return .needsAuthorization }
        var settings = status.settings
        settings.minutesSinceMidnight = minutes
        let result = status.isOn ? await alarm.update(settings) : await alarm.enable(settings)
        return result.isOn && result.settings.minutesSinceMidnight == minutes ? .set(minutes: minutes) : .couldNotSet
    }

    func askCoach(_ text: String) -> AskCoachOutcome {
        // Today's free questions used up: Coach opens on its card (it says why and what Premium has) and the words are not kept.
        guard coach?.mayAsk(text) ?? true else {
            model.open(.coach())
            return .limitReached
        }
        model.askCoach(text)
        return .asked
    }
}
