import SwiftUI

/// R15's two card densities.
public enum NoctisCardDensity: Sendable {
    /// 20pt inner padding on every side; stacked cards 12pt apart.
    case standard
    /// 14pt vertical / 20pt horizontal inner padding; stacked cards 8pt
    /// apart. Allowed only on Health and Notifications, whose content must
    /// fit iPhone 17 Pro unscrolled (R16).
    case compact

    public var insets: EdgeInsets {
        switch self {
        case .standard: EdgeInsets(top: NoctisSpacing.lg, leading: NoctisSpacing.lg, bottom: NoctisSpacing.lg, trailing: NoctisSpacing.lg)
        case .compact: EdgeInsets(top: 14, leading: NoctisSpacing.lg, bottom: 14, trailing: NoctisSpacing.lg)
        }
    }

}

/// A flat floating surface (R2's one allowed shadow: cocoa .06, blur 24,
/// y 8) — white fill, hairline stroke, 28pt radius. Named `NoctisPaperCard`
/// to avoid colliding with the existing `.noctisCard(padding:)` modifier
/// used elsewhere in the app.
public struct NoctisPaperCard<Content: View>: View {
    private let insets: EdgeInsets
    private let borderColor: Color
    private let borderWidth: CGFloat
    private let content: Content

    public init(
        padding: CGFloat = NoctisSpacing.lg,
        borderColor: Color = NoctisPaper.hairline,
        borderWidth: CGFloat = 1,
        @ViewBuilder content: () -> Content
    ) {
        self.insets = EdgeInsets(top: padding, leading: padding, bottom: padding, trailing: padding)
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.content = content()
    }

    /// A card at one of R15's densities (see `NoctisCardDensity`).
    public init(
        density: NoctisCardDensity,
        borderColor: Color = NoctisPaper.hairline,
        borderWidth: CGFloat = 1,
        @ViewBuilder content: () -> Content
    ) {
        self.insets = density.insets
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.content = content()
    }

    public var body: some View {
        content
            .padding(insets)
            .background(
                RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous)
                    .fill(NoctisPaper.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous)
                            .stroke(borderColor, lineWidth: borderWidth)
                    )
            )
            .shadow(color: NoctisPaper.cocoa.opacity(0.06), radius: 24, x: 0, y: 8)
    }
}
