import Foundation

/// What a sound is doing, as the person would put it.
public enum SoundPlaybackPhase: Sendable, Equatable {
    /// Nothing loaded; the engine is off.
    case stopped
    case playing
    /// The person paused it.
    case paused
    /// The system paused it (a call, Siri, an alarm, headphones unplugged). It starts again
    /// by itself only when the system says it should.
    case interrupted
}

public enum SoundPlaybackEvent: Sendable, Equatable {
    case play
    case pause
    case stop
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    /// The headphones (or whatever it was playing to) went away.
    case routeLost
    case mediaServicesReset
    case timerFinished
    case remotePlay
    case remotePause
    case remoteToggle
}

public enum SoundPlaybackAction: Sendable, Equatable {
    case none
    /// Start the engine from nothing and fade in.
    case start
    /// Fade out over a moment, then pause the engine.
    case fadeAndPause
    /// Pause the engine at once: the system already stopped the sound.
    case pauseNow
    /// Fade in from a pause.
    case resume
    /// Fade out over a moment, then stop the engine and let the session go.
    case fadeAndStop
    /// Stop the engine and let the session go at once (the timer's fade has already run).
    case stopNow
    /// The system rebuilt its audio services: build the engine again, and play if it was playing.
    case rebuildAndResume
    case rebuild
}

/// What happens when. One pure function (APP_RULES.md R31), so every case is in a test:
///
/// - A call, Siri or an alarm pauses the sound; it resumes by itself only if the system says
///   `shouldResume`, and never if the person had paused it first.
/// - Headphones unplugged pause it for good (a sound that was private must not move to the
///   speaker), and it doesn't come back by itself.
/// - A media services reset means the engine must be built again.
public enum SoundPlaybackPolicy {
    public struct Result: Sendable, Equatable {
        public let phase: SoundPlaybackPhase
        public let action: SoundPlaybackAction
    }

    public static func reduce(_ phase: SoundPlaybackPhase, _ event: SoundPlaybackEvent) -> Result {
        func result(_ p: SoundPlaybackPhase, _ a: SoundPlaybackAction) -> Result { Result(phase: p, action: a) }
        switch (phase, event) {
        // Play, from a pause or from nothing.
        case (.stopped, .play), (.stopped, .remotePlay):
            return result(.playing, .start)
        case (.paused, .play), (.paused, .remotePlay), (.interrupted, .play), (.interrupted, .remotePlay):
            return result(.playing, .resume)
        case (.playing, .play), (.playing, .remotePlay):
            return result(.playing, .none)

        // Pause.
        case (.playing, .pause), (.playing, .remotePause):
            return result(.paused, .fadeAndPause)
        case (.interrupted, .pause), (.interrupted, .remotePause):
            // Paused by the system, now by the person too: it will not come back by itself.
            return result(.paused, .none)

        case (.playing, .remoteToggle):
            return result(.paused, .fadeAndPause)
        case (.paused, .remoteToggle), (.interrupted, .remoteToggle):
            return result(.playing, .resume)

        // Stop.
        case (.stopped, .stop):
            return result(.stopped, .none)
        case (_, .stop):
            return result(.stopped, .fadeAndStop)
        case (.stopped, _) where event == .timerFinished:
            return result(.stopped, .none)
        case (_, .timerFinished):
            return result(.stopped, .stopNow)

        // The system takes over.
        case (.playing, .interruptionBegan):
            return result(.interrupted, .pauseNow)
        case (.interrupted, .interruptionEnded(let shouldResume)):
            return shouldResume ? result(.playing, .resume) : result(.interrupted, .none)
        case (.playing, .routeLost):
            return result(.paused, .pauseNow)

        // The system reset its audio services.
        case (.playing, .mediaServicesReset):
            return result(.playing, .rebuildAndResume)
        case (.paused, .mediaServicesReset), (.interrupted, .mediaServicesReset):
            return result(phase, .rebuild)

        default:
            return result(phase, .none)
        }
    }
}
