import Foundation
import NightKit
import NightFeature
import NoctisCore
import NoctisIntentKit
import NoctisWidgetKit
import SoundKit

/// Where an intent's destination goes in the app (APP_RULES.md R47): the three plain screens through the strict URL router the widgets use
/// (recovery, sleep, bedtime), the rest as the `AppRoute` they are. `AppModel.open` is the one place any of them is opened; an intent holds no
/// navigation logic of its own.
public enum IntentRouting {
    public static func route(for destination: IntentDestination) -> AppRoute {
        switch destination {
        case .recovery: WidgetURLRouter.route(for: .recovery)
        case .sleep: WidgetURLRouter.route(for: .sleep)
        case .bedtime: WidgetURLRouter.route(for: .bedtime)
        case .windDown(let autostart): .windDown(autostart: autostart)
        case .alarm: .alarm
        case .coach: .coach()
        }
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

    init(model: AppModel, preferences: AppPreferences, player: SoundPlayer, sounds: SoundsViewModel, alarm: AlarmService) {
        self.model = model
        self.preferences = preferences
        self.player = player
        self.sounds = sounds
        self.alarm = alarm
    }

    func open(_ destination: IntentDestination) {
        model.open(IntentRouting.route(for: destination))
    }

    func startWindDown(minutes: Int?) {
        // The length is the wind-down's own preference (what the screen starts with), then the screen begins it as it opens.
        if let minutes, WindDownClock.options.contains(minutes) { preferences.update { $0.windDownMinutes = minutes } }
        model.open(.windDown(autostart: true))
    }

    func playSleepSounds(_ kind: SoundKind?) -> SoundKind {
        let chosen = kind ?? player.lastKind ?? .rain
        sounds.play(chosen)
        return chosen
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

    func askCoach(_ text: String) {
        model.askCoach(text)
    }
}
