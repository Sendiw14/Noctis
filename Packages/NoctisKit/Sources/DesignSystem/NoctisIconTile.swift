import SwiftUI

/// A flat filled circle with a centered SF Symbol — the onboarding
/// system's basic icon unit (a goal, a signal, a summary item). Solid
/// color only, no glow or gradient (R2).
public struct NoctisIconTile: View {
    private let systemImage: String
    private let fill: Color
    private let foreground: Color
    private let baseSize: CGFloat
    /// R4: tiles sit beside text, so they grow with it (capped at
    /// `NoctisTypeScale.maxIconScale`); `size` is the default-text-size
    /// diameter.
    @NoctisScaleFactor private var scale: CGFloat

    public init(systemImage: String, fill: Color, foreground: Color = NoctisPaper.bg, size: CGFloat = 44) {
        self.systemImage = systemImage
        self.fill = fill
        self.foreground = foreground
        self.baseSize = size
    }

    private var size: CGFloat { baseSize * scale }

    public var body: some View {
        Circle()
            .fill(fill)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(foreground)
            )
            .accessibilityHidden(true)
    }
}
