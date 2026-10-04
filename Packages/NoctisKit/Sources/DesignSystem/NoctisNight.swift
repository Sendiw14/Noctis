import SwiftUI

/// The night (APP_RULES.md R32): the one place the app goes dark on purpose, in both Light and Dark.
/// Flat colors in the existing cocoa language: the night, the deep it moves toward, ivory ink, the
/// lavender accent, the moon, and two hills a little lighter than the sky. No gradients, no glow.
public nonisolated enum NoctisNight {
    public static let nightHex = "17110E"
    public static let deepHex = "0E0A08"
    /// Ivory ink, and the quieter ivory for secondary lines (4.5:1 on both).
    public static let ivoryHex = "F4EDE3"
    public static let ivory2Hex = "B9B0A6"
    public static let lavenderHex = "8E7BDC"
    /// The two hills, back and front: slightly lighter cocoa than the sky.
    public static let hillBackHex = "221810"
    public static let hillFrontHex = "2C1F16"

    public static var night: Color { noctisHexColor(nightHex) }
    public static var deep: Color { noctisHexColor(deepHex) }
    public static var ivory: Color { noctisHexColor(ivoryHex) }
    public static var ivory2: Color { noctisHexColor(ivory2Hex) }
    public static var lavender: Color { noctisHexColor(lavenderHex) }
    public static var moon: Color { ivory }
    public static var hillBack: Color { noctisHexColor(hillBackHex) }
    public static var hillFront: Color { noctisHexColor(hillFrontHex) }

    /// The sky `t` of the way from the night to the deep (0...1): one flat color at any moment.
    public static func sky(_ t: Double) -> Color {
        let u = min(max(t, 0), 1)
        let a = noctisHexComponents(nightHex), b = noctisHexComponents(deepHex)
        return Color(red: a.0 + (b.0 - a.0) * u, green: a.1 + (b.1 - a.1) * u, blue: a.2 + (b.2 - a.2) * u)
    }
}
