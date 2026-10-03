import Foundation
import RecoveryKit

/// What the engine reads. Times are minutes since midnight; a balance is signed minutes
/// (negative is behind the sleep need). All of it comes from tested engines: the profile,
/// `SleepBalanceEngine`, `SleepTimingEngine` and `ConsistencyEngine` (`BedtimeInputsBuilder`).
public struct BedtimeInputs: Sendable, Equatable {
    public let wakeMinutes: Int
    public let needMinutes: Int
    /// The 7-night balance; nil without 5 recorded nights of the 7.
    public let balanceMinutes: Double?
    /// The median bedtime of the last 14 nights; nil under 7 nights.
    public let usualBedtimeMinutes: Int?
    /// How much bedtime varies (SD, minutes). Shown as a reason; it never moves the center.
    public let bedtimeSpreadMinutes: Double?
    /// Nights with sleep recorded in the last 14.
    public let nights: Int
    /// How far the clock jumps between bedtime and waking tonight: +60 when clocks go forward,
    /// -60 when they go back, 0 on any other night. Real sleep is the clock gap minus this.
    public let clockChangeMinutes: Int

    public init(
        wakeMinutes: Int, needMinutes: Int, balanceMinutes: Double? = nil, usualBedtimeMinutes: Int? = nil,
        bedtimeSpreadMinutes: Double? = nil, nights: Int = 0, clockChangeMinutes: Int = 0
    ) {
        self.wakeMinutes = BedtimeClock.wrap(wakeMinutes)
        self.needMinutes = needMinutes
        self.balanceMinutes = balanceMinutes
        self.usualBedtimeMinutes = usualBedtimeMinutes.map(BedtimeClock.wrap)
        self.bedtimeSpreadMinutes = bedtimeSpreadMinutes
        self.nights = nights
        self.clockChangeMinutes = clockChangeMinutes
    }
}

/// A span of the clock, ends in minutes since midnight. `end` can be before `start`:
/// 11:45 PM to 12:15 AM.
public struct BedtimeWindow: Sendable, Equatable, Codable {
    public let startMinutes: Int
    public let endMinutes: Int

    public init(startMinutes: Int, endMinutes: Int) {
        self.startMinutes = BedtimeClock.wrap(startMinutes)
        self.endMinutes = BedtimeClock.wrap(endMinutes)
    }

    public var lengthMinutes: Int { BedtimeClock.forward(from: startMinutes, to: endMinutes) }
}

public enum BedtimeReasonKind: String, Sendable, CaseIterable, Codable {
    /// `value`: minutes of sleep wanted.
    case sleepNeed
    /// `value`: the wake time, minutes since midnight.
    case wakeTime
    /// `value`: the median bedtime, minutes since midnight. `shiftMinutes` is how far the limit
    /// on how fast bedtime may move changed the center.
    case usualBedtime
    /// `value`: signed minutes, negative behind. `shiftMinutes` is how far it moved the center.
    case balance
    /// `value`: how much bedtime varies, minutes. Informational.
    case consistency
}

/// One fact the recommendation rests on, with its value (the words are the screen's, R18).
public struct BedtimeReason: Sendable, Equatable, Codable {
    public let kind: BedtimeReasonKind
    public let value: Double
    /// Minutes this fact moved the center: negative is earlier, 0 when it didn't move it.
    public let shiftMinutes: Int

    public init(kind: BedtimeReasonKind, value: Double, shiftMinutes: Int = 0) {
        self.kind = kind
        self.value = value
        self.shiftMinutes = shiftMinutes
    }
}

public struct BedtimeRecommendation: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        /// 7 or more nights: a window around the center.
        case window
        /// Under 7 nights: one bedtime, "a starting point".
        case single
    }

    public let model: String
    public let kind: Kind
    /// The bedtime, or the middle of the window: minutes since midnight.
    public let centerMinutes: Int
    /// Nil for a single bedtime.
    public let window: BedtimeWindow?
    /// Real sleep between the center and waking, after any clock change.
    public let expectedSleepMinutes: Int
    public let wakeMinutes: Int
    public let needMinutes: Int
    public let nights: Int
    public let reasons: [BedtimeReason]
    /// How far earlier the balance moved the center (0 when it didn't).
    public let catchUpMinutes: Int
    /// Whether the center was held back from the target to move toward it gradually.
    public let isGradual: Bool
    public let clockChangeMinutes: Int
    public let confidence: RecoveryConfidence

    public func reason(_ kind: BedtimeReasonKind) -> BedtimeReason? {
        reasons.first { $0.kind == kind }
    }
}

/// Tonight's bedtime, from your sleep need, your wake time and your own recent nights.
/// Deterministic and pure: the same inputs give the same recommendation, and nothing here
/// knows what a `Date` is (APP_RULES.md R18, R30).
///
/// 1. The base is the wake time minus the sleep need.
/// 2. A 7-night balance 60 minutes or more behind moves the center earlier by a quarter of
///    it (at most 30 minutes, to the nearest 5). Ahead or in line: nothing changes.
/// 3. With a usual bedtime, a center more than 45 minutes from it is brought back to 45
///    minutes from it, on the side of the target: bedtime moves gradually.
/// 4. The window is the center plus and minus 15 minutes, to the nearest 5.
public enum BedtimeRecommendationEngine {
    public static func recommend(_ inputs: BedtimeInputs, model: BedtimeModel = .current) -> BedtimeRecommendation {
        let p = model.parameters
        let base = BedtimeClock.wrap(inputs.wakeMinutes - inputs.needMinutes - inputs.clockChangeMinutes)
        var reasons = [
            BedtimeReason(kind: .sleepNeed, value: Double(inputs.needMinutes)),
            BedtimeReason(kind: .wakeTime, value: Double(inputs.wakeMinutes)),
        ]

        guard inputs.nights >= p.minimumNights else {
            return BedtimeRecommendation(
                model: model.version, kind: .single, centerMinutes: base, window: nil,
                expectedSleepMinutes: expectedSleep(center: base, inputs: inputs), wakeMinutes: inputs.wakeMinutes,
                needMinutes: inputs.needMinutes, nights: inputs.nights, reasons: reasons, catchUpMinutes: 0, isGradual: false,
                clockChangeMinutes: inputs.clockChangeMinutes, confidence: .low
            )
        }

        var center = base

        // Catch-up: behind by 60 or more, so earlier by a quarter of it.
        var catchUp = 0
        if let balance = inputs.balanceMinutes, -balance >= p.catchUpBehindMinutes {
            let behind = -balance
            catchUp = BedtimeClock.rounded(min(Double(p.catchUpLimitMinutes), behind / p.catchUpShareDivisor), to: p.roundingMinutes)
            center = BedtimeClock.wrap(center - catchUp)
        }

        // Gradual: never more than 45 minutes from where you usually go to bed.
        var gradualShift = 0
        if let usual = inputs.usualBedtimeMinutes {
            let distance = BedtimeClock.signedDistance(from: usual, to: center)
            if abs(distance) > p.gradualDistanceMinutes {
                let held = BedtimeClock.wrap(usual + (distance > 0 ? p.gradualStepMinutes : -p.gradualStepMinutes))
                gradualShift = BedtimeClock.signedDistance(from: center, to: held)
                center = held
            }
        }

        if let usual = inputs.usualBedtimeMinutes {
            reasons.append(BedtimeReason(kind: .usualBedtime, value: Double(usual), shiftMinutes: gradualShift))
        }
        if let balance = inputs.balanceMinutes {
            reasons.append(BedtimeReason(kind: .balance, value: balance, shiftMinutes: -catchUp))
        }
        if let spread = inputs.bedtimeSpreadMinutes {
            reasons.append(BedtimeReason(kind: .consistency, value: spread))
        }

        let half = Double(p.windowHalfWidthMinutes)
        let window = BedtimeWindow(
            startMinutes: BedtimeClock.rounded(Double(center) - half, to: p.roundingMinutes),
            endMinutes: BedtimeClock.rounded(Double(center) + half, to: p.roundingMinutes)
        )
        return BedtimeRecommendation(
            model: model.version, kind: .window, centerMinutes: center, window: window,
            expectedSleepMinutes: expectedSleep(center: center, inputs: inputs), wakeMinutes: inputs.wakeMinutes,
            needMinutes: inputs.needMinutes, nights: inputs.nights, reasons: reasons, catchUpMinutes: catchUp, isGradual: gradualShift != 0,
            clockChangeMinutes: inputs.clockChangeMinutes, confidence: confidence(inputs, parameters: p)
        )
    }

    /// Real sleep from the center to waking: the clock gap, less any clock change in between.
    static func expectedSleep(center: Int, inputs: BedtimeInputs) -> Int {
        max(BedtimeClock.forward(from: center, to: inputs.wakeMinutes) - inputs.clockChangeMinutes, 0)
    }

    /// Recovery's tiers: high needs every input and 14 nights; moderate needs three of the four
    /// inputs and 7 nights; anything less is low.
    static func confidence(_ inputs: BedtimeInputs, parameters p: BedtimeParameters) -> RecoveryConfidence {
        let present = 2 + (inputs.balanceMinutes == nil ? 0 : 1) + (inputs.usualBedtimeMinutes == nil ? 0 : 1)
        if present == 4 && inputs.nights >= p.highConfidenceNights { return .high }
        if present >= p.moderateConfidenceInputs && inputs.nights >= p.minimumNights { return .moderate }
        return .low
    }
}
