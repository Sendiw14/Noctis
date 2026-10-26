import AppIntents
import Foundation
import NoctisWidgetKit
import SoundCatalog

// The Sleep sounds control's intent (APP_RULES.md R48). The control is drawn by an extension, but sound is the app's: this is an
// `AudioPlaybackIntent`, so iOS runs it in the app's own process (starting the app in the background if it has to) and the sound plays
// through the one sound player, exactly as a tile on the Sounds screen would play it.

/// Turns the sleep sound on or off from Control Center, the Lock Screen or the Action button. On plays the last sound played (Rain before
/// any); off stops what plays. Not in the Shortcuts gallery: "Play sleep sounds" is the action to build with.
public struct SleepSoundsToggleIntent: SetValueIntent, AudioPlaybackIntent {
    public static let title: LocalizedStringResource = "Sleep sounds"
    public static let description = IntentDescription("Starts or stops your sleep sound.", categoryName: "Sleep")
    public static let isDiscoverable = false

    @Parameter(title: "Playing")
    public var value: Bool

    public init() {}

    public init(value: Bool) {
        self.value = value
    }

    /// On plays the last sound (the host knows which); off stops what plays.
    @MainActor
    public func perform() async throws -> some IntentResult {
        let runtime = IntentRuntime.current
        // The system has already flipped the control. Whatever happens next, it is told to read the truth again, so a flip that did not come
        // true (the app could not be reached, the sound would not start) cannot stay on the screen.
        defer { runtime.environment.reloadControl(ControlKind.sleepSounds) }
        guard let host = await runtime.host() else { return .result() }
        if value {
            // The last sound played if the plan still includes it, Brown noise if not: the control never starts a sound the plan does not include (R62).
            if case .play(let kind) = IntentGate.soundChoice(requested: nil, last: host.lastSleepSound, tier: runtime.environment.tier()) {
                _ = host.playSleepSounds(kind)
            }
        } else {
            host.stopSleepSounds()
        }
        return .result()
    }
}
