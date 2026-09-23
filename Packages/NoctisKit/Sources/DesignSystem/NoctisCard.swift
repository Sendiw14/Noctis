import SwiftUI

private struct NoctisCardModifier: ViewModifier {
    var padding: CGFloat = NoctisSpacing.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous)
                    .fill(NoctisColor.surfaceRaised)
            )
            .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 6)
    }
}

extension View {
    public func noctisCard(padding: CGFloat = NoctisSpacing.lg) -> some View {
        modifier(NoctisCardModifier(padding: padding))
    }
}
