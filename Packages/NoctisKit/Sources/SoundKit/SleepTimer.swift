import Foundation

/// The sleep timer's choices.
public enum SleepTimerChoice: Int, CaseIterable, Sendable, Codable, Identifiable {
    case off = 0
    case minutes15 = 15
    case minutes30 = 30
    case minutes45 = 45
    case minutes60 = 60
    case minutes90 = 90

    public var id: Int { rawValue }
    public var minutes: Int { rawValue }

    public var title: String {
        self == .off ? "Off" : "\(rawValue) min"
    }
}

/// A sleep timer as plain dates: when it started, how long it runs, and the fade that closes it.
/// Everything is worked out from the clock, never counted, so a timer that kept running while the
/// phone was locked is exactly where it should be when it is looked at again.
public struct SleepTimerPlan: Sendable, Equatable {
    /// The last seconds of a timer are a fade to silence.
    public static let fadeSeconds: TimeInterval = 20

    public let start: Date
    public let duration: TimeInterval

    public init(start: Date, duration: TimeInterval) {
        self.start = start
        self.duration = duration
    }

    public init(start: Date, choice: SleepTimerChoice) {
        self.init(start: start, duration: TimeInterval(choice.minutes * 60))
    }

    public var end: Date { start.addingTimeInterval(duration) }
    public var fadeStart: Date { end.addingTimeInterval(-min(Self.fadeSeconds, duration)) }

    public enum Phase: Sendable, Equatable {
        case running
        /// The fade has begun; this much is left of it.
        case fading(remaining: TimeInterval)
        case finished
    }

    public func phase(at now: Date) -> Phase {
        if now >= end { return .finished }
        if now >= fadeStart { return .fading(remaining: end.timeIntervalSince(now)) }
        return .running
    }

    /// Time to the end, never negative.
    public func remaining(at now: Date) -> TimeInterval {
        max(end.timeIntervalSince(now), 0)
    }

    /// The next moment something has to happen: the fade starts, then the timer ends.
    public func nextWake(after now: Date) -> Date? {
        if now < fadeStart { return fadeStart }
        if now < end { return end }
        return nil
    }

    /// "29:41", or "1:29:41" over an hour; the countdown the sheet shows.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.up)), 0)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
