import Foundation
// The Watch kit builds on this one and asks the same table; re-exporting keeps its dependencies as they are (a leaf with no dependencies of its own).
@_exported import PremiumKit

// What the widgets do with the person's plan (APP_RULES.md R62). Pure: a family and a tier in, a decision and the words of a locked widget out. The tier is the one
// word in the shared snapshot (the extension never calls StoreKit); what a tier includes is the one feature table's (R59). A missing snapshot is free.

/// A family of the two widgets, named without WidgetKit so every decision is a unit test.
public nonisolated enum WidgetSurface: String, Sendable, CaseIterable, Equatable {
    case small, medium, large
    case lockCircular, lockRectangular, lockInline

    /// The feature that includes this family (R57): the small Home Screen widget and the circular Lock Screen widget are free; every other family is Premium.
    public var feature: Feature {
        switch self {
        case .small: .widgetSmall
        case .lockCircular: .widgetLockCircular
        case .medium, .large, .lockRectangular, .lockInline: .widgetMediumLargeAndOtherLock
        }
    }

    public func isLocked(in tier: Tier) -> Bool {
        !FeatureTable.isIncluded(feature, in: tier)
    }
}

/// What a locked widget says: a lock glyph, "NOCTIS Premium" and one line naming what the widget shows. It is built from the family alone, never from a snapshot, so
/// there is nowhere for a health number to come from.
public nonisolated struct WidgetLockedContent: Equatable, Sendable {
    public static let title = "NOCTIS Premium"

    public let surface: WidgetSurface
    /// What the widget shows, in one line; nil for the inline family (one line of text has room for the title alone).
    public let line: String?

    public init(_ surface: WidgetSurface) {
        self.surface = surface
        switch surface {
        case .small, .medium, .large: line = "Your recovery and tonight's bedtime."
        case .lockRectangular: line = "Recovery and bedtime on your Lock Screen."
        case .lockCircular, .lockInline: line = nil
        }
    }

    /// Read aloud as one thing, saying it opens the app.
    public var accessibilityLabel: String {
        [Self.title, line, "Opens NOCTIS."].compactMap { $0 }.joined(separator: " ")
    }

    /// A tap opens the app on the paywall sheet, saying what Premium adds to widgets.
    public var link: URL { PremiumLink(context: .widgets).url }
}

public nonisolated enum WidgetGate {
    /// Whether `entry` is drawn locked in `surface`: the person's plan (free with no snapshot) does not include the family. The widget gallery's preview (`isPreview`: sample
    /// numbers tagged "Sample", R45) always keeps the unlocked design, so what a widget can show is visible before it is added.
    public static func isLocked(_ entry: WidgetEntryModel, in surface: WidgetSurface) -> Bool {
        guard !entry.isPreview else { return false }
        // At the entry's own date: a plan that runs out while the app is closed locks the entry the timeline placed at that moment (S1B-C01).
        return surface.isLocked(in: entry.snapshot?.effectiveTier(at: entry.date) ?? .free)
    }

    /// The locked content for `entry` in `surface`, or nil when it is drawn as it always was.
    public static func lockedContent(_ entry: WidgetEntryModel, in surface: WidgetSurface) -> WidgetLockedContent? {
        isLocked(entry, in: surface) ? WidgetLockedContent(surface) : nil
    }

    /// The timeline's entries for a family: a locked family has nothing for the Smart Stack to promote (idle relevance), so a widget the person cannot use never pushes
    /// itself forward.
    public static func entries(_ entries: [WidgetEntryModel], in surface: WidgetSurface) -> [WidgetEntryModel] {
        entries.map { entry in
            guard isLocked(entry, in: surface) else { return entry }
            var quiet = entry
            quiet.relevance = .idle
            return quiet
        }
    }
}
