import Foundation

// The meditation's engine (APP_RULES.md R34): the categories, and the schedule of a session, which
// line is on screen and when each chime sounds. Pure and deterministic: where a session is comes
// from the seconds elapsed, so a test can check every length and the drawing only maps it.

public enum MeditationCategory: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case sleep
    case relax
    case breathing
    case bodyScan
    case quietMind

    public var id: String { rawValue }

    /// Quiet mind says nothing: a slow ring and a few soft chimes.
    public var hasLines: Bool { self != .quietMind }

    /// The String Catalog's keys for this category's lines, in the order they are said. Twelve each
    /// (the body scan's twelve are twelve places from the head to the feet).
    public var poolKeys: [String] {
        guard hasLines else { return [] }
        let prefix = "meditation.\(rawValue)."
        return (1...Self.poolSize).map { prefix + String(format: "%02d", $0) }
    }

    public static let poolSize = 12

    public var titleKey: String { "meditation.\(rawValue).title" }
    public var summaryKey: String { "meditation.\(rawValue).summary" }

    /// How many lines a session of `minutes` says. The body scan always walks all twelve places, a
    /// little slower in a longer session; the others say more in a longer one.
    public func lineCount(minutes: Int) -> Int {
        guard hasLines else { return 0 }
        if self == .bodyScan { return Self.poolSize }
        switch minutes {
        case ...5: return 6
        case 6...10: return 9
        default: return 12
        }
    }
}

public enum MeditationChimeKind: String, Sendable, Equatable, Hashable, CaseIterable {
    case start
    case transition
    case end
}

/// One moment of a session: a line to show and say, a chime to sound, or both.
public struct MeditationCue: Sendable, Equatable {
    public let at: TimeInterval
    /// The catalog key of the line, if this cue has one.
    public let lineKey: String?
    public let chime: MeditationChimeKind?
}

/// A category run for a length of time. The length is exact: 5, 10 or 20 minutes.
public struct MeditationSchedule: Sendable, Equatable {
    public static let durations = [5, 10, 20]
    public static let defaultMinutes = 10
    /// Seconds from the start chime to the first line.
    public static let leadIn: TimeInterval = 6
    /// Seconds of quiet between the last line's turn and the closing chime.
    public static let tail: TimeInterval = 24

    public let category: MeditationCategory
    public let minutes: Int
    public let totalSeconds: TimeInterval
    /// In time order: the start chime at 0, the lines (evenly spaced), the transitions, the end chime at the end.
    public let cues: [MeditationCue]
    /// How long each line stays before the next one (0 with no lines).
    public let lineGap: TimeInterval

    public init(category: MeditationCategory, minutes: Int) {
        self.category = category
        self.minutes = minutes
        let total = TimeInterval(max(minutes, 1) * 60)
        totalSeconds = total
        var cues = [MeditationCue(at: 0, lineKey: nil, chime: .start)]
        let count = category.lineCount(minutes: minutes)
        if count > 0 {
            let gap = (total - Self.leadIn - Self.tail) / Double(count)
            lineGap = gap
            let keys = Self.sample(category.poolKeys, count: count)
            // A soft chime as the second and the third part begin.
            let firstTransition = count / 3
            let secondTransition = 2 * count / 3
            let transitions: Set<Int> = count >= 3 && firstTransition > 0 && secondTransition > firstTransition ? [firstTransition, secondTransition] : []
            var index = 0
            while index < count {
                cues.append(MeditationCue(at: Self.leadIn + gap * Double(index), lineKey: keys[index], chime: transitions.contains(index) ? .transition : nil))
                index += 1
            }
        } else {
            lineGap = 0
            cues.append(MeditationCue(at: total / 3, lineKey: nil, chime: .transition))
            cues.append(MeditationCue(at: 2 * total / 3, lineKey: nil, chime: .transition))
        }
        cues.append(MeditationCue(at: total, lineKey: nil, chime: .end))
        self.cues = cues
    }

    /// `count` of the pool's lines, spread evenly from its first to its last, never repeating one.
    static func sample(_ pool: [String], count: Int) -> [String] {
        guard count < pool.count, count > 1 else { return Array(pool.prefix(count)) }
        let step = Double(pool.count - 1) / Double(count - 1)
        var result: [String] = []
        var index = 0
        while index < count {
            result.append(pool[Int((Double(index) * step).rounded())])
            index += 1
        }
        return result
    }

    /// The lines of the session, in order.
    public var lineCues: [MeditationCue] { cues.filter { $0.lineKey != nil } }

    /// The line on screen `elapsed` seconds in: the latest one begun, none before the first.
    public func lineKey(at elapsed: TimeInterval) -> String? {
        lineCues.last { $0.at <= elapsed }?.lineKey
    }

    /// The first cue after `elapsed`, if any.
    public func nextCueTime(after elapsed: TimeInterval) -> TimeInterval? {
        cues.first { $0.at > elapsed }?.at
    }
}

/// Where the session stands, for the ring: 0 at the start, 1 at the end.
public func meditationProgress(elapsed: TimeInterval, total: TimeInterval) -> Double {
    guard total > 0 else { return 0 }
    return min(max(elapsed / total, 0), 1)
}
