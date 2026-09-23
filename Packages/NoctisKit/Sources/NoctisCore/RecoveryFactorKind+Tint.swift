import DesignSystem
import HealthProviding
import InsightsKit
import RecoveryKit
import SwiftUI

extension RecoveryFactorKind {
    public var tint: Color {
        switch self {
        case .sleep: NoctisColor.factorSleep
        case .hrv: NoctisColor.factorHRV
        case .restingHeartRate: NoctisColor.factorRestingHR
        case .consistency: NoctisColor.factorConsistency
        case .load: NoctisColor.factorLoad
        }
    }
}

extension SleepStageValue {
    public var tint: Color {
        switch self {
        case .awake, .inBed: NoctisColor.stageAwake
        case .rem: NoctisColor.stageREM
        case .core, .unspecified: NoctisColor.stageCore
        case .deep: NoctisColor.stageDeep
        }
    }

    public var displayName: String {
        switch self {
        case .awake: "Awake"
        case .inBed: "In Bed"
        case .rem: "REM"
        case .core: "Core"
        case .deep: "Deep"
        case .unspecified: "Asleep"
        }
    }

    /// Vertical position for the NOCTIS Flowing Sleep Landscape: 0 is the
    /// surface (closest to waking), 1 is the deepest point — the
    /// conventional hypnogram reading of sleep depth.
    public var landscapeDepth: CGFloat {
        switch self {
        case .awake, .inBed: 0.12
        case .rem: 0.45
        case .core, .unspecified: 0.68
        case .deep: 1.0
        }
    }
}

extension InsightCategory {
    public var tint: Color {
        switch self {
        case .sleep: NoctisColor.factorSleep
        case .recovery: NoctisColor.terracotta
        case .timing: NoctisColor.violet
        case .consistency: NoctisColor.amber
        case .longTerm: NoctisColor.textSecondary
        }
    }
}

extension PrimaryGoal {
    /// The color identity this goal carries through onboarding — the
    /// goal tile, the sleep-window gradient, the profile card, and the
    /// completion wash all key off this single mapping.
    public var tint: Color {
        switch self {
        case .betterSleep: NoctisColor.indigo
        case .moreEnergy: NoctisColor.coral
        case .betterRecovery: NoctisColor.sage
        case .betterConsistency: NoctisColor.amber
        case .betterFocus: NoctisColor.cyanAccent
        }
    }
}
