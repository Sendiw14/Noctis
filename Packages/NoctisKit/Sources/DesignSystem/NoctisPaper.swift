import SwiftUI

/// The v2 "Ink & Ivory" onboarding palette (ONBOARDING_RULES.md R5) — warm
/// ivory paper with cocoa ink and flat solid fills. Fixed regardless of
/// system light/dark mode, distinct from `NoctisColor`'s adaptive palette:
/// every onboarding step after Welcome uses these tokens exclusively so no
/// view ever hardcodes a hex value.
public enum NoctisPaper {
    public static let bg = noctisHexColor("F8F5EE")
    public static let surface = noctisHexColor("FFFFFF")
    public static let hairline = noctisHexColor("E9E3D8")
    public static let track = noctisHexColor("ECE6DA")
    public static let ink = noctisHexColor("2B1D14")
    public static let ink2 = noctisHexColor("6B5B4E")
    public static let ink3 = noctisHexColor("7A6B5E")
    public static let orangeText = noctisHexColor("C2571A")

    // MARK: Fills

    public static let sage = noctisHexColor("9DB073")
    public static let orange = noctisHexColor("E07B39")
    public static let butter = noctisHexColor("F2CE6B")
    public static let lavender = noctisHexColor("A08CEB")
    public static let cocoa = noctisHexColor("4A2F22")

    // MARK: Sleep stages

    public static let stageDeep = cocoa
    public static let stageCore = orange
    public static let stageREM = sage
    public static let stageAwake = butter

    /// Ivory — the color that reads correctly on `cocoa`/`ink` fills.
    public static let ivory = bg
}
