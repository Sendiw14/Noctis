import SwiftUI

/// WCAG 2.x contrast ratio between two colors: `(L1 + 0.05) / (L2 + 0.05)`
/// with `L1` the lighter relative luminance, so the result is always >= 1.
/// R5's palette contrast floors (`NoctisPaperContrastTests`) are checked
/// against this.
public nonisolated func noctisContrastRatio(_ a: Color, _ b: Color) -> Double {
    let luminanceA = relativeLuminance(of: a)
    let luminanceB = relativeLuminance(of: b)
    let lighter = max(luminanceA, luminanceB)
    let darker = min(luminanceA, luminanceB)
    return (lighter + 0.05) / (darker + 0.05)
}

private nonisolated func relativeLuminance(of color: Color) -> Double {
    let resolved = color.resolve(in: EnvironmentValues())
    let red = linearize(Double(resolved.red))
    let green = linearize(Double(resolved.green))
    let blue = linearize(Double(resolved.blue))
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue
}

private nonisolated func linearize(_ channel: Double) -> Double {
    channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
}
