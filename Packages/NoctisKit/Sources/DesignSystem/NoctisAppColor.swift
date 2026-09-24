import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// One mode's worth of main-app tokens (APP_RULES.md R5). `light` is the
/// NoctisPaper palette; `dark` is its dark counterpart. Kept as plain
/// values so contrast tests can check both modes without a trait
/// environment.
public nonisolated struct NoctisAppPalette: Sendable {
    public let bg: String
    public let surface: String
    public let hairline: String
    public let track: String
    public let ink: String
    public let ink2: String
    public let ink3: String
    public let orangeText: String
    public let sage: String
    public let orange: String
    public let butter: String
    public let lavender: String
    public let cocoa: String
    public let ctaFill: String
    public let ctaLabel: String
    /// Text and glyphs on sage, orange, butter and lavender fills.
    public let onFill: String
    /// Home's Last night panel: always the darkest element on screen.
    public let nightPanel: String
    /// Text on the night panel.
    public let nightInk: String
    /// The night panel's edge (Dark: an inset hairline; Light: none).
    public let nightBorder: String
    /// Home's color blocks (Tonight, Insight) and the ink on them.
    public let blockLavender: String
    public let blockButter: String
    public let blockInk: String
    /// The unfilled part of a recovery ring on the paper.
    public let ringTrack: String
    /// Last night's bar in This week.
    public let weekHighlight: String
    /// Lavender for display text (evening greeting), ≥ 3:1 on bg.
    public let lavenderText: String
    /// The morning reveal's first frame: a flat dusk that crossfades to
    /// the paper.
    public let dusk: String

    public static let light = NoctisAppPalette(
        bg: "F8F5EE", surface: "FFFFFF", hairline: "E9E3D8", track: "ECE6DA",
        ink: "2B1D14", ink2: "6B5B4E", ink3: "7A6B5E", orangeText: "C2571A",
        sage: "9DB073", orange: "E07B39", butter: "F2CE6B", lavender: "A08CEB", cocoa: "4A2F22",
        ctaFill: "4A2F22", ctaLabel: "F8F5EE", onFill: "2B1D14",
        nightPanel: "4A2F22", nightInk: "F8F5EE", nightBorder: "4A2F22",
        blockLavender: "A08CEB", blockButter: "F2CE6B", blockInk: "2B1D14",
        ringTrack: "ECE6DA", weekHighlight: "4A2F22", lavenderText: "7B63D6",
        dusk: "E6E0EE"
    )

    public static let dark = NoctisAppPalette(
        bg: "17110E", surface: "221A15", hairline: "33281F", track: "2E241D",
        ink: "F4EDE3", ink2: "C9BBAA", ink3: "9C8C7B", orangeText: "F08A4B",
        // Cocoa lifts to #9A6A50 in Dark: #4A2F22 is 1.5:1 on the dark
        // surface, too faint for the Deep stage and last night's bar.
        sage: "8FA366", orange: "E4854A", butter: "E9C25E", lavender: "9A87E6", cocoa: "9A6A50",
        ctaFill: "F4EDE3", ctaLabel: "2B1D14", onFill: "2B1D14",
        // Designed separately: an inset near-black panel with a hairline,
        // blocks deepened a step, a quieter ring track.
        nightPanel: "0E0A08", nightInk: "F4EDE3", nightBorder: "33281F",
        blockLavender: "8E7BDC", blockButter: "E0B955", blockInk: "2B1D14",
        ringTrack: "2A211B", weekHighlight: "9A87E6", lavenderText: "A897F0",
        dusk: "120E17"
    )
}

/// The main app's adaptive tokens (R5): each resolves to the light or dark
/// palette from the current trait collection. Onboarding keeps the fixed
/// `NoctisPaper` tokens and stays light.
public nonisolated enum NoctisAppColor {
    public static let bg = adaptive(\.bg)
    public static let surface = adaptive(\.surface)
    public static let hairline = adaptive(\.hairline)
    public static let track = adaptive(\.track)
    public static let ink = adaptive(\.ink)
    public static let ink2 = adaptive(\.ink2)
    public static let ink3 = adaptive(\.ink3)
    public static let orangeText = adaptive(\.orangeText)

    // MARK: Fills

    public static let sage = adaptive(\.sage)
    public static let orange = adaptive(\.orange)
    public static let butter = adaptive(\.butter)
    public static let lavender = adaptive(\.lavender)
    public static let cocoa = adaptive(\.cocoa)

    // MARK: CTA (R10)

    public static let ctaFill = adaptive(\.ctaFill)
    public static let ctaLabel = adaptive(\.ctaLabel)

    /// Glyphs and text on sage, orange, butter and lavender (R5: ink on
    /// fills), dark in both modes.
    public static let onFill = adaptive(\.onFill)

    // MARK: Home v2

    public static let nightPanel = adaptive(\.nightPanel)
    public static let nightInk = adaptive(\.nightInk)
    public static let nightBorder = adaptive(\.nightBorder)
    public static let blockLavender = adaptive(\.blockLavender)
    public static let blockButter = adaptive(\.blockButter)
    /// #2B1D14 in both modes: cocoa #4A2F22 is only 4.33:1 (Light) and
    /// 3.50:1 (Dark) on the lavender block.
    public static let blockInk = adaptive(\.blockInk)
    public static let ringTrack = adaptive(\.ringTrack)
    public static let weekHighlight = adaptive(\.weekHighlight)
    public static let lavenderText = adaptive(\.lavenderText)
    public static let dusk = adaptive(\.dusk)

    // MARK: Sleep stages

    public static let stageDeep = cocoa
    public static let stageCore = orange
    public static let stageREM = sage
    public static let stageAwake = butter

    /// `nonisolated`: UIKit resolves dynamic colors on whatever thread is
    /// rendering, including SwiftUI's background renderer (see NoctisColor).
    nonisolated private static func adaptive(_ token: KeyPath<NoctisAppPalette, String>) -> Color {
        #if canImport(UIKit)
        let light = noctisHexComponents(NoctisAppPalette.light[keyPath: token])
        let dark = noctisHexComponents(NoctisAppPalette.dark[keyPath: token])
        return Color(uiColor: UIColor { traits in
            let (r, g, b) = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
        #else
        return noctisHexColor(NoctisAppPalette.light[keyPath: token])
        #endif
    }
}
