import SwiftUI

public struct NoctisPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(NoctisMotion.adaptive(NoctisMotion.snap, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

public struct NoctisPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .noctisText(.bodyEmphasized, color: NoctisColor.textOnAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, NoctisSpacing.md)
            .background(
                Capsule(style: .continuous)
                    .fill(NoctisColor.textPrimary.opacity(isEnabled ? 1 : 0.35))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(NoctisMotion.adaptive(NoctisMotion.snap, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

public struct NoctisSecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .noctisText(.bodyEmphasized, color: NoctisColor.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, NoctisSpacing.md)
            .background(
                Capsule(style: .continuous)
                    .strokeBorder(NoctisColor.divider, lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(NoctisMotion.adaptive(NoctisMotion.snap, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == NoctisPrimaryButtonStyle {
    public static var noctisPrimary: NoctisPrimaryButtonStyle { NoctisPrimaryButtonStyle() }
}

extension ButtonStyle where Self == NoctisSecondaryButtonStyle {
    public static var noctisSecondary: NoctisSecondaryButtonStyle { NoctisSecondaryButtonStyle() }
}

extension ButtonStyle where Self == NoctisPressStyle {
    public static var noctisPress: NoctisPressStyle { NoctisPressStyle() }
}
