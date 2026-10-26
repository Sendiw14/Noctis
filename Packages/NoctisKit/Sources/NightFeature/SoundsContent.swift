import DesignSystem
import Foundation
import NoctisText
import SoundKit

// What the Sounds screen says and shows, built from the player's state (APP_RULES.md R18, R20, R31).
// Views lay it out; the words are here.

/// The screen's fixed words. Plain: it says what the sounds are and nothing about what they do for
/// anyone's sleep, health or mood.
public enum SoundsCopy {
    public static let caption = "STEADY SOUNDS FOR WINDING DOWN"
    public static let summary = "Made on your iPhone. Nothing downloads."
    public static let sleepWell = "Sleep well."
    public static let timerTitle = "Sleep timer"
    public static let timerNote = "The sound fades out over the last 20 seconds, then stops."
    public static let interrupted = "Paused by iPhone"
    public static let paused = "Paused"
    public static let playing = "Playing"
    /// What a tile of a Premium sound says where "Playing" would be.
    public static let premium = "Premium"
    public static let lockedHint = "Opens what Premium includes."
}

/// Which block color a sound wears.
public enum SoundTone: Sendable, Equatable {
    case cocoa
    case lavender
    case sage
    case butter
    case orange
    case apricot
}

extension SoundKind {
    public var symbol: String {
        switch self {
        case .brown: "waveform"
        case .rain: "cloud.rain"
        case .ocean: "water.waves"
        case .wind: "wind"
        case .fireplace: "flame"
        case .ambient: "sparkles"
        }
    }

    public var tone: SoundTone {
        switch self {
        case .brown: .cocoa
        case .rain: .lavender
        case .ocean: .sage
        case .wind: .butter
        case .fireplace: .orange
        case .ambient: .apricot
        }
    }
}

public struct SoundTileContent: Sendable, Equatable, Identifiable {
    public let kind: SoundKind
    public let title: String
    public let symbol: String
    public let tone: SoundTone
    /// The sound that is loaded (playing, paused or interrupted).
    public let isCurrent: Bool
    /// Playing right now: the tile shows its border and its level.
    public let isPlaying: Bool
    /// "Playing", "Paused", "Paused by iPhone"; nil for a sound that isn't the current one.
    public let stateText: String?
    public let accessibilityLabel: String
    public let accessibilityHint: String
    /// A Premium sound on the free plan (APP_RULES.md R57): the tile wears a lock glyph and opens the paywall instead of playing.
    public var isLocked = false

    public var id: SoundKind { kind }
}

public struct NowPlayingContent: Sendable, Equatable {
    public let kind: SoundKind
    public let title: String
    public let symbol: String
    public let tone: SoundTone
    public let stateText: String
    public let isPlaying: Bool
    /// The sound's own gain, 0...1.
    public let gain: Float
    public let gainText: String
    /// "Timer" with none running, or the time left ("29:41").
    public let timerText: String
    public let timerIsRunning: Bool
    public let playPauseLabel: String
    public let timerLabel: String
}

public enum SoundsBuilder {
    /// `isLocked`: the sounds the person's plan does not include (`FeatureGate.sounds(for:)`); a locked sound is never "current" here, because a tile
    /// that is locked opens the paywall and does not play.
    public static func tiles(_ state: SoundPlayerState, isLocked: (SoundKind) -> Bool = { _ in false }) -> [SoundTileContent] {
        SoundKind.allCases.map { kind in
            if isLocked(kind), !(state.kind == kind && state.phase != .stopped) {
                return SoundTileContent(
                    kind: kind, title: kind.title, symbol: kind.symbol, tone: kind.tone, isCurrent: false, isPlaying: false, stateText: SoundsCopy.premium,
                    accessibilityLabel: "\(kind.title), \(SoundsCopy.premium)", accessibilityHint: SoundsCopy.lockedHint, isLocked: true
                )
            }
            let isCurrent = state.kind == kind && state.phase != .stopped
            let isPlaying = isCurrent && state.phase == .playing
            let text: String? = isCurrent ? stateText(state.phase) : nil
            let hint: String
            switch (isCurrent, state.phase) {
            case (true, .playing): hint = "Pauses \(kind.title)."
            case (true, _): hint = "Plays \(kind.title) again."
            default: hint = "Plays \(kind.title)."
            }
            return SoundTileContent(
                kind: kind, title: kind.title, symbol: kind.symbol, tone: kind.tone, isCurrent: isCurrent, isPlaying: isPlaying, stateText: text,
                accessibilityLabel: kind.title + (text.map { ", \($0)" } ?? ""), accessibilityHint: hint
            )
        }
    }

    public static func stateText(_ phase: SoundPlaybackPhase) -> String {
        switch phase {
        case .playing: SoundsCopy.playing
        case .paused: SoundsCopy.paused
        case .interrupted: SoundsCopy.interrupted
        case .stopped: ""
        }
    }

    /// The Now Playing card; nil when nothing is loaded. `remaining` is the sleep timer's time left.
    public static func nowPlaying(_ state: SoundPlayerState, remaining: TimeInterval?) -> NowPlayingContent? {
        guard let kind = state.kind, state.phase != .stopped else { return nil }
        let gain = state.gain(for: kind)
        let percent = Int((gain * 100).rounded())
        let isPlaying = state.phase == .playing
        let timerRunning = state.timer != nil
        let timerText = remaining.map { SleepTimerPlan.clock($0) } ?? "Timer"
        return NowPlayingContent(
            kind: kind, title: kind.title, symbol: kind.symbol, tone: kind.tone, stateText: stateText(state.phase), isPlaying: isPlaying,
            gain: gain, gainText: "\(percent)%", timerText: timerRunning ? timerText : "Timer", timerIsRunning: timerRunning,
            playPauseLabel: isPlaying ? "Pause \(kind.title)" : "Play \(kind.title)",
            timerLabel: timerRunning ? "Sleep timer, \(spokenRemaining(remaining ?? 0)) left" : "Sleep timer, off"
        )
    }

    /// "29 minutes", "1 minute", "45 seconds".
    public static func spokenRemaining(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        if total >= 60 {
            let minutes = (total + 59) / 60
            return NoctisCount.minutes(minutes)
        }
        return NoctisCount.seconds(total)
    }

    /// The timer sheet's rows, the chosen one marked.
    public static func timerChoices(_ state: SoundPlayerState) -> [(choice: SleepTimerChoice, isSelected: Bool)] {
        let current = state.timer.flatMap { plan in SleepTimerChoice(rawValue: Int((plan.duration / 60).rounded())) } ?? .off
        return SleepTimerChoice.allCases.map { ($0, $0 == current) }
    }
}

/// How the meter's RMS becomes a bar: decibels, from -50 dBFS (nothing) to -10 dBFS (full), so a
/// quiet sound still moves the bars and a loud one doesn't pin them.
public enum SoundMeterScale {
    public static let barCount = 24
    public static let floorDecibels: Float = -50
    public static let ceilingDecibels: Float = -10

    public static func display(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10f(rms)
        return min(max((decibels - floorDecibels) / (ceilingDecibels - floorDecibels), 0), 1)
    }
}

/// The last 24 levels, newest last: the bars of the waveform, 1.6 seconds of the real sound at
/// the meter's 15 readings a second.
public struct SoundMeterHistory: Sendable, Equatable {
    public private(set) var bars: [Float]

    public init() {
        bars = [Float](repeating: 0, count: SoundMeterScale.barCount)
    }

    public mutating func push(rms: Float) {
        bars.removeFirst()
        bars.append(SoundMeterScale.display(rms: rms))
    }

    public mutating func reset() {
        bars = [Float](repeating: 0, count: SoundMeterScale.barCount)
    }

    public var latest: Float { bars.last ?? 0 }
}
