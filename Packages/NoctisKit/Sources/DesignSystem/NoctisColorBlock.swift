import SwiftUI

/// A solid, flat color block (R15): 28pt corners, 20pt padding, no border
/// and no shadow (Increase Contrast adds a border). Text on it uses
/// `.noctisFieldInk` / `.noctisFieldInk2` (block ink), or `NoctisMetric`
/// with its `.block` tone.
public struct NoctisColorBlock<Content: View>: View {
    private let fill: Color
    private let content: Content

    public init(fill: Color, @ViewBuilder content: () -> Content) {
        self.fill = fill
        self.content = content()
    }

    public var body: some View {
        content
            .padding(NoctisSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous))
            .noctisContrastBorder()
    }
}

/// The hairline between tiles inside a color block: block ink at 12%.
public struct NoctisBlockRule: View {
    public enum Axis: Sendable {
        case horizontal
        case vertical
    }

    private let axis: Axis

    public init(_ axis: Axis) {
        self.axis = axis
    }

    public var body: some View {
        Rectangle()
            .fill(NoctisAppColor.blockInk.opacity(0.12))
            .frame(width: axis == .vertical ? 1 : nil, height: axis == .horizontal ? 1 : nil)
    }
}
