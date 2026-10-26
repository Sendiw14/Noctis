import DesignSystem
import Foundation
import Observation
@_exported import PremiumKit
import PremiumKit
import SoundKit
import SwiftUI

/// The one thing screens ask about tiers (APP_RULES.md R57, R59): `isUnlocked(_:)`. It asks `FeatureTable`, which is the only source of tier decisions, and
/// the tier it reads is `EntitlementManager`'s (the cached tier until the App Store has answered, then its answer). It is `@Observable`, so a change of tier
/// reaches every screen that read it and locked views unlock in place; the change is animated by the screens with a spring, and says so with one soft haptic.
///
/// It also holds the free Coach questions (`CoachQuota`): three a day, counted only when a real answer is delivered.
@MainActor
@Observable
public final class FeatureGate {
    private let entitlements: EntitlementManager?
    private let fixedTier: Tier?
    @ObservationIgnored private let quotaStore: CoachQuotaStore
    @ObservationIgnored private let calendar: () -> Calendar
    @ObservationIgnored private let clock: () -> Date
    /// The free Coach questions used today, as stored.
    private var quota: CoachQuotaState

    public init(
        entitlements: EntitlementManager, quotaStore: CoachQuotaStore = CoachQuotaStore(), calendar: @escaping () -> Calendar = { .autoupdatingCurrent },
        clock: @escaping () -> Date = { Date() }
    ) {
        self.entitlements = entitlements
        fixedTier = nil
        self.quotaStore = quotaStore
        self.calendar = calendar
        self.clock = clock
        quota = quotaStore.read()
        // A change of tier says so with one soft haptic (and the screens animate it with a spring).
        let previous = entitlements.onTierChange
        entitlements.onTierChange = { new, old in
            previous?(new, old)
            NoctisHaptics.soft()
        }
    }

    /// A gate with a fixed tier: a preview, a test, the DEBUG `-forceTier`.
    public init(
        tier: Tier, quotaStore: CoachQuotaStore = .inMemory(), calendar: @escaping () -> Calendar = { .autoupdatingCurrent },
        clock: @escaping () -> Date = { Date() }
    ) {
        entitlements = nil
        fixedTier = tier
        self.quotaStore = quotaStore
        self.calendar = calendar
        self.clock = clock
        quota = quotaStore.read()
    }

    public var tier: Tier { fixedTier ?? entitlements?.tier ?? .free }
    public var state: EntitlementState { fixedTier.map { $0 == .premium ? .premium(.purchased) : .free } ?? entitlements?.state ?? .free }
    public var isPremium: Bool { tier == .premium }

    /// Whether `feature` is shown in full to this person.
    public func isUnlocked(_ feature: Feature) -> Bool { FeatureTable.isIncluded(feature, in: tier) }

    // MARK: Sounds

    /// The sounds of `tier`: Brown noise, Rain and Ocean are free; Wind, Fireplace and Ambient are Premium (a Premium person has all six).
    public static func sounds(for tier: Tier) -> [SoundKind] { SoundAccess.kinds(for: tier) }

    public static let freeSounds: [SoundKind] = SoundAccess.freeKinds

    public func isUnlocked(_ sound: SoundKind) -> Bool { Self.sounds(for: tier).contains(sound) }

    // MARK: Coach

    /// The free questions left today; nil with Premium (no limit).
    public var coachQuestionsRemaining: Int? {
        guard !isUnlocked(.coachUnlimited) else { return nil }
        return CoachQuota.remaining(quota, now: clock(), calendar: calendar())
    }

    /// Whether Coach can take another question now.
    public var canAskCoach: Bool { coachQuestionsRemaining.map { $0 > 0 } ?? true }

    /// A real answer was delivered (never a scripted medical, crisis or unknown reply): one free question used.
    public func recordCoachAnswer() {
        guard !isUnlocked(.coachUnlimited) else { return }
        quota = CoachQuota.recording(quota, now: clock(), calendar: calendar())
        quotaStore.write(quota)
    }

}

// MARK: - Where the views find it

private struct FeatureGateKey: EnvironmentKey {
    @MainActor static let defaultValue = FeatureGate(tier: .free)
}

extension EnvironmentValues {
    /// The app's feature gate; a free one where the app has not put it (a preview or a test).
    public var featureGate: FeatureGate {
        get { self[FeatureGateKey.self] }
        set { self[FeatureGateKey.self] = newValue }
    }
}
