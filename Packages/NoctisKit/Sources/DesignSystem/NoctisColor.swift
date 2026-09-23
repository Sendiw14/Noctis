import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public enum NoctisColor {
    /// `nonisolated` is required: UIKit invokes `UIColor`'s dynamicProvider
    /// closure from whatever thread is resolving the color — including
    /// SwiftUI's background AsyncRenderer thread — never only the main
    /// actor. Letting it inherit this module's main-actor-by-default
    /// isolation caused a real crash (Swift concurrency's runtime isolation
    /// check trapping when UIKit called it off the main actor).
    nonisolated private static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            let (r, g, b) = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
        #else
        Color(red: light.0, green: light.1, blue: light.2)
        #endif
    }

    // MARK: Surfaces

    public static let canvas = dynamic(light: (0.976, 0.965, 0.949), dark: (0.055, 0.055, 0.071))
    public static let surface = dynamic(light: (0.992, 0.988, 0.980), dark: (0.098, 0.098, 0.122))
    public static let surfaceRaised = dynamic(light: (1.0, 1.0, 1.0), dark: (0.137, 0.137, 0.165))
    public static let surfaceSunken = dynamic(light: (0.949, 0.937, 0.918), dark: (0.043, 0.043, 0.055))

    // MARK: Text

    public static let textPrimary = dynamic(light: (0.114, 0.098, 0.086), dark: (0.965, 0.957, 0.941))
    public static let textSecondary = dynamic(light: (0.361, 0.337, 0.314), dark: (0.729, 0.714, 0.706))
    public static let textTertiary = dynamic(light: (0.588, 0.565, 0.541), dark: (0.500, 0.494, 0.494))
    /// The inverse of `textPrimary` — for text sitting on a surface filled
    /// with `textPrimary`, such as the primary button.
    public static let textOnAccent = dynamic(light: (0.976, 0.965, 0.949), dark: (0.114, 0.098, 0.086))

    // MARK: Accents

    public static let accentPrimary = dynamic(light: (0.831, 0.678, 0.596), dark: (0.851, 0.706, 0.667))
    public static let sage = dynamic(light: (0.541, 0.612, 0.514), dark: (0.616, 0.686, 0.588))
    public static let violet = dynamic(light: (0.616, 0.588, 0.741), dark: (0.678, 0.647, 0.816))
    public static let amber = dynamic(light: (0.831, 0.635, 0.365), dark: (0.878, 0.686, 0.420))
    public static let terracotta = dynamic(light: (0.769, 0.475, 0.400), dark: (0.816, 0.541, 0.463))

    // MARK: Onboarding atmosphere
    // An extended, more expressive palette reserved for onboarding's more
    // cinematic moments — the rest of NOCTIS stays on the restrained
    // palette above. `midnight` is deliberately near-identical in both
    // light and dark mode: it's a fixed cinematic backdrop, not an
    // adaptive surface.

    public static let midnight = dynamic(light: (0.055, 0.055, 0.086), dark: (0.024, 0.024, 0.043))
    /// A dark neutral between `midnight` and `indigo` — the third stop in
    /// the midnight mesh gradient, kept out of the violet family so that
    /// gradient reads as atmosphere rather than a flat color ramp.
    public static let graphite = dynamic(light: (0.129, 0.125, 0.145), dark: (0.098, 0.094, 0.114))
    public static let indigo = dynamic(light: (0.376, 0.353, 0.702), dark: (0.478, 0.451, 0.831))
    public static let auroraBlue = dynamic(light: (0.318, 0.588, 0.827), dark: (0.412, 0.671, 0.914))
    public static let cyanAccent = dynamic(light: (0.275, 0.667, 0.678), dark: (0.376, 0.780, 0.788))
    public static let coral = dynamic(light: (0.914, 0.478, 0.427), dark: (0.945, 0.573, 0.514))
    public static let peach = dynamic(light: (0.949, 0.706, 0.573), dark: (0.949, 0.745, 0.635))
    public static let lavenderSoft = dynamic(light: (0.784, 0.749, 0.902), dark: (0.706, 0.667, 0.859))
    /// The warm off-white a screen resolves to when night becomes morning
    /// (Welcome's "Begin" mask expansion) — fixed in both appearances like
    /// `midnight`, since it represents a specific light, not a surface.
    public static let ivory = dynamic(light: (0.976, 0.965, 0.949), dark: (0.976, 0.965, 0.949))
    /// The corona's middle accent (violet -> magenta -> amber) — fixed
    /// like `midnight`/`ivory`, a specific cinematic light rather than an
    /// adaptive surface.
    public static let magenta = dynamic(light: (0.769, 0.243, 0.545), dark: (0.769, 0.243, 0.545))

    // MARK: Structural

    public static let divider = dynamic(light: (0.859, 0.839, 0.816), dark: (0.192, 0.192, 0.224))
    public static let scrim = dynamic(light: (0.114, 0.098, 0.086), dark: (0.020, 0.020, 0.031))

    // MARK: Semantic — sleep stages

    public static let stageAwake = terracotta
    public static let stageREM = amber
    public static let stageCore = sage
    public static let stageDeep = dynamic(light: (0.310, 0.271, 0.239), dark: (0.322, 0.361, 0.435))

    // MARK: Semantic — recovery factors

    public static let factorSleep = sage
    public static let factorHRV = violet
    public static let factorRestingHR = terracotta
    public static let factorConsistency = amber
    public static let factorLoad = textSecondary

    public static func recoveryTint(for score: Int) -> Color {
        switch score {
        case 75...100: sage
        case 50..<75: amber
        default: terracotta
        }
    }
}
