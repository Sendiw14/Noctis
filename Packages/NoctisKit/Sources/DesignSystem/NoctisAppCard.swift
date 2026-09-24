import SwiftUI

/// The main app's card (R15, R2): 20pt inner padding, surface fill,
/// hairline stroke, 28pt radius and the one soft shadow. Follows
/// Light/Dark through `NoctisAppColor`.
public struct NoctisAppCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(NoctisSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous)
                    .fill(NoctisAppColor.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous)
                            .strokeBorder(NoctisAppColor.hairline, lineWidth: 1)
                    )
            )
            .shadow(color: NoctisPaper.cocoa.opacity(0.06), radius: 24, x: 0, y: 8)
    }
}

/// A whole card as a button: presses to .98 and springs back (R10's press
/// feel, scaled down for a large surface).
public struct NoctisCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(NoctisMotion.adaptive(NoctisMotion.snap, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
