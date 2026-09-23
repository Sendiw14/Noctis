import Foundation
import HealthProviding

public struct SleepStageSegment: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let stage: SleepStageValue
    public let interval: DateInterval

    public init(id: UUID = UUID(), stage: SleepStageValue, interval: DateInterval) {
        self.id = id
        self.stage = stage
        self.interval = interval
    }
}

public enum SleepSessionKind: Sendable {
    case main
    case nap
}

public struct SleepSession: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let kind: SleepSessionKind
    public let bedtime: Date
    public let wakeTime: Date
    public let segments: [SleepStageSegment]
    public let sourceName: String

    public init(id: UUID = UUID(), kind: SleepSessionKind, bedtime: Date, wakeTime: Date, segments: [SleepStageSegment], sourceName: String) {
        self.id = id
        self.kind = kind
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.segments = segments
        self.sourceName = sourceName
    }

    public var timeInBed: TimeInterval { wakeTime.timeIntervalSince(bedtime) }

    public func duration(of stages: Set<SleepStageValue>) -> TimeInterval {
        segments.filter { stages.contains($0.stage) }.reduce(0) { $0 + $1.interval.duration }
    }

    public var totalAsleep: TimeInterval { duration(of: [.core, .rem, .deep, .unspecified]) }
    public var remDuration: TimeInterval { duration(of: [.rem]) }
    public var coreDuration: TimeInterval { duration(of: [.core]) }
    public var deepDuration: TimeInterval { duration(of: [.deep]) }
    public var awakeDuration: TimeInterval { duration(of: [.awake]) }

    public var sleepEfficiency: Double {
        guard timeInBed > 0 else { return 0 }
        return min(totalAsleep / timeInBed, 1)
    }

    public var awakeningsCount: Int {
        segments.enumerated().filter { index, segment in
            segment.stage == .awake && index != 0
        }.count
    }

    public static func == (lhs: SleepSession, rhs: SleepSession) -> Bool { lhs.id == rhs.id }
}
