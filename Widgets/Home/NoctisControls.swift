import AppIntents
import NoctisIntentKit
import NoctisWidgetKit
import SwiftUI
import WidgetKit

/// NOCTIS's two controls for Control Center, the Lock Screen and the Action button (APP_RULES.md R48). The extension draws them and holds
/// nothing: "Wind down" asks the app to open the wind-down and begin it, and "Sleep sounds" asks the app to play or stop its one sound
/// player. What the toggle shows is one small file the app keeps true in the App Group, read here and nowhere else; the intents run in the
/// app, never here.

/// The extension names the intents' package, so the system finds the intents the controls run.
struct NoctisWidgetsIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [NoctisIntentKitPackage.self] }
}

/// A button: opens NOCTIS at the wind-down and begins it with the length the person last chose.
struct NoctisWindDownControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.windDown) {
            ControlWidgetButton(action: StartWindDownIntent()) {
                Label("Wind down", systemImage: "moon.stars.fill")
            }
            .tint(ControlStyle.tint)
        }
        .displayName("Wind down")
        .description("Starts your wind-down in NOCTIS.")
    }
}

/// A toggle: on while a sleep sound plays. The app redraws it when the sound starts, stops or its timer changes.
struct NoctisSleepSoundsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.sleepSounds, provider: SleepSoundsValueProvider()) { isPlaying in
            ControlWidgetToggle(isOn: isPlaying, action: SleepSoundsToggleIntent()) {
                Label("Sleep sounds", systemImage: "waveform")
            } valueLabel: { isOn in
                Text(isOn ? "Playing" : "Off")
            }
            .tint(ControlStyle.tint)
        }
        .displayName("Sleep sounds")
        .description("Plays and stops your sleep sound.")
    }
}

/// Whether a sound is playing, from the app's record. No file, or a record whose sleep timer has ended, means nothing is.
struct SleepSoundsValueProvider: ControlValueProvider {
    /// What the Controls gallery shows before it is added.
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        SleepSoundsStore()?.isPlaying() ?? false
    }
}
