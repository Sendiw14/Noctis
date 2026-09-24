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

    public static let light = NoctisAppPalette(
        bg: "F8F5EE", surface: "FFFFFF", hairline: "E9E3D8", track: "ECE6DA",
        ink: "2B1D14", ink2: "6B5B4E", ink3: "7A6B5E", orangeText: "C2571A",
        sage: "9DB073", orange: "E07B39", butter: "F2CE6B", lavender: "A08CEB", cocoa: "4A2F22",
        ctaFill: "4A2F22", ctaLabel: "F8F5EE", onFill: "2B1D14"
    )

    public static let dark = NoctisAppPalette(
        bg: "17110E", surface: "221A15", hairline: "33281F", track: "2E241D",
        ink: "F4EDE3", ink2: "C9BBAA", ink3: "9C8C7B", orangeText: "F08A4B",
        // Cocoa lifts to #9A6A50 in Dark: #4A2F22 is 1.5:1 on the dark
        // surface, too faint for the Deep stage and last night's bar.
        sage: "8FA366", orange: "E4854A", butter: "E9C25E", lavender: "9A87E6", cocoa: "9A6A50",
        ctaFill: "F4EDE3", ctaLabel: "2B1D14", onFill: "2B1D14"
    )
}

/// The main app's adaptive tokens (R5): each resolves to the light or dark
/// palette from the current trait collection. Onboarding keeps the fixed
/// `NoctisPaper` tokens and stays light.
public enum NoctisAppColor {
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
