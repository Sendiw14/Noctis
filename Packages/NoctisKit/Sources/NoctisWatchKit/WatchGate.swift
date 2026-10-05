import Foundation
import NoctisWidgetKit

// What the Apple Watch does with the person's plan (APP_RULES.md R62). Pure: a page or a complication and a tier in, a decision and the words of a locked one out.
// The tier is the one word in the snapshot the iPhone sent (the Watch never calls StoreKit and has no purchase of its own); what a tier includes is the one feature
// table's (R59). With no snapshot the tier is unknown and nothing is claimed to be locked: the Watch says to open NOCTIS on the iPhone, as it always did.

public nonisolated enum WatchGate {
    /// What a locked page says, whole: nothing here sells or presses, and there is nothing to buy on the Watch.
    public static let lockedLine = "Part of NOCTIS Premium. Open NOCTIS on your iPhone to learn more."

    /// The feature that includes a page; nil for Settings, which is always free (R57).
    public static func feature(for page: WatchPage) -> Feature? {
        switch page {
        case .recovery, .sleep: .watchRecoverySleepPages
        case .heart, .tonight: .watchHeartTonightPages
        case .settings: nil
        }
    }

    /// The feature that includes a complication: Recovery (all four families) is free, the other three kinds are Premium.
    public static func feature(for kind: WatchComplicationKind) -> Feature {
        switch kind {
        case .recovery: .watchRecoveryComplication
        case .sleep, .bedtime, .quality: .watchOtherComplications
        }
    }

    /// Whether `page` is a locked card for `tier` (nil: no snapshot yet, so nothing is known and nothing is locked).
    public static func isLocked(_ page: WatchPage, tier: Tier?) -> Bool {
        guard let tier, let feature = feature(for: page) else { return false }
        return !FeatureTable.isIncluded(feature, in: tier)
    }

    public static func isLocked(_ kind: WatchComplicationKind, tier: Tier?) -> Bool {
        guard let tier else { return false }
        return !FeatureTable.isIncluded(feature(for: kind), in: tier)
    }
}

/// A locked page's words: its title (the page's own) and the one line. Built from the page alone, never from the snapshot, so there is no number in it.
public nonisolated struct WatchLockedContent: Equatable, Sendable {
    public let page: WatchPage

    public init(_ page: WatchPage) {
        self.page = page
    }

    public var title: String { page.title }
    public var line: String { WatchGate.lockedLine }
    public var accessibilityLabel: String { "\(title). \(line)" }
}
