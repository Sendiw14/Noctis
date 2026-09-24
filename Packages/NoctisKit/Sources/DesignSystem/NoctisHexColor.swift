import SwiftUI

/// Parses a plain 6-digit hex string (no `#`, no alpha) into a `Color` —
/// the one place a literal hex value is allowed; every other view reads a
/// `NoctisPaper` or `NoctisAppColor` token instead (R5).
public nonisolated func noctisHexColor(_ hex: String) -> Color {
    let (red, green, blue) = noctisHexComponents(hex)
    return Color(red: red, green: green, blue: blue)
}

/// The 0–1 red, green and blue channels of a 6-digit hex string.
public nonisolated func noctisHexComponents(_ hex: String) -> (Double, Double, Double) {
    var value: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&value)
    let red = Double((value & 0xFF0000) >> 16) / 255
    let green = Double((value & 0x00FF00) >> 8) / 255
    let blue = Double(value & 0x0000FF) / 255
    return (red, green, blue)
}
