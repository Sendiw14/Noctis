import Foundation
import RecoveryKit

/// Every number the bedtime recommendation uses, in one place, under a version
/// (APP_RULES.md R30). A change to any of them is a new model, never an edit.
public struct BedtimeParameters: Sendable, Equatable {
    /// Nights of history the recommendation needs to say more than "a starting point".
    public let minimumNights: Int
    /// Nights for high confidence, with every input present (the same tiers as Recovery).
    public let highConfidenceNights: Int
    /// Inputs (sleep need, wake time, balance, usual bedtime) for moderate confidence.
    public let moderateConfidenceInputs: Int
    /// The 7-night balance this far behind (minutes) moves the center earlier.
    public let catchUpBehindMinutes: Double
    /// How much of the balance one night asks for: a quarter of it...
    public let catchUpShareDivisor: Double
    /// ...but never more than this (minutes).
    public let catchUpLimitMinutes: Int
    /// A center this far from the usual bedtime (more than, in minutes) is brought back toward it.
    public let gradualDistanceMinutes: Int
    /// ...to this far from the usual bedtime, on the side of the target.
    public let gradualStepMinutes: Int
    /// The window is the center plus and minus this (minutes).
    public let windowHalfWidthMinutes: Int
    /// Window ends and catch-up shifts are rounded to this (minutes).
    public let roundingMinutes: Int

    public init(
        minimumNights: Int, highConfidenceNights: Int, moderateConfidenceInputs: Int, catchUpBehindMinutes: Double, catchUpShareDivisor: Double,
        catchUpLimitMinutes: Int, gradualDistanceMinutes: Int, gradualStepMinutes: Int, windowHalfWidthMinutes: Int, roundingMinutes: Int
    ) {
        self.minimumNights = minimumNights
        self.highConfidenceNights = highConfidenceNights
        self.moderateConfidenceInputs = moderateConfidenceInputs
        self.catchUpBehindMinutes = catchUpBehindMinutes
        self.catchUpShareDivisor = catchUpShareDivisor
        self.catchUpLimitMinutes = catchUpLimitMinutes
        self.gradualDistanceMinutes = gradualDistanceMinutes
        self.gradualStepMinutes = gradualStepMinutes
        self.windowHalfWidthMinutes = windowHalfWidthMinutes
        self.roundingMinutes = roundingMinutes
    }
}

/// The versions of the bedtime model. `current` is what the app shows.
public enum BedtimeModel: String, Sendable, CaseIterable, Codable {
    case v1 = "bedtime-v1"

    public static let current: BedtimeModel = .v1

    public var version: String { rawValue }

    public var parameters: BedtimeParameters {
        switch self {
        case .v1: BedtimeModelV1.parameters
        }
    }
}

public enum BedtimeModelV1 {
    /// Tiers match Recovery's: high needs every input and 14 nights, moderate needs 3 of the 4
    /// inputs and 7 nights, and the sleep need and wake time are always two of them.
    public static let parameters = BedtimeParameters(
        minimumNights: RecoveryModelV1.moderateConfidenceNights,
        highConfidenceNights: RecoveryModelV1.highConfidenceNights,
        moderateConfidenceInputs: RecoveryModelV1.moderateConfidenceFactors,
        catchUpBehindMinutes: 60,
        catchUpShareDivisor: 4,
        catchUpLimitMinutes: 30,
        gradualDistanceMinutes: 45,
        gradualStepMinutes: 45,
        windowHalfWidthMinutes: 15,
        roundingMinutes: 5
    )
}
