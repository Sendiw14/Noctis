import SwiftUI

/// A single illustrative sleep stage segment in `SampleNight.segments`.
public enum SampleSleepStage: CaseIterable, Sendable {
    case deep, core, rem, awake

    public var label: String {
        switch self {
        case .deep: "Deep"
        case .core: "Core"
        case .rem: "REM"
        case .awake: "Awake"
        }
    }

    public var color: Color {
        switch self {
        case .deep: NoctisPaper.stageDeep
        case .core: NoctisPaper.stageCore
        case .rem: NoctisPaper.stageREM
        case .awake: NoctisPaper.stageAwake
        }
    }
}

/// The shared illustrative hypnogram every onboarding "Sample" moment (and,
/// later, the real Sleep screen) draws from — always clearly labeled
/// "Sample" per R13, never presented as real data. 14 segments totaling
/// 505 minutes starting 11:00 PM: deep sleep front-loaded, REM back-loaded,
/// the conventional shape of a real night.
public enum SampleNight {

    public static let segments: [(stage: SampleSleepStage, minutes: Int)] = [
        (.awake, 6),
        (.core, 26),
        (.deep, 42),
        (.core, 40),
        (.deep, 34),
        (.core, 44),
        (.rem, 16),
        (.awake, 6),
        (.core, 60),
        (.deep, 16),
        (.rem, 36),
        (.core, 75),
        (.rem, 76),
        (.awake, 28),
    ]

    public static let totalMinutes = segments.reduce(0) { $0 + $1.minutes }

    public static func minutes(for stage: SampleSleepStage) -> Int {
        segments.filter { $0.stage == stage }.reduce(0) { $0 + $1.minutes }
    }

    /// A flattened, minute-by-minute stage timeline — convenient for a
    /// chart that draws one bar/point per minute rather than per segment.
    public static func timeline() -> [SampleSleepStage] {
        segments.flatMap { segment in Array(repeating: segment.stage, count: segment.minutes) }
    }
}
