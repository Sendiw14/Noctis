import SwiftUI

/// Places each subview along the width at a fraction (0 = leading edge,
/// 1 = trailing edge), kept inside the bounds: labels under a strip or
/// chart (R8: a system `Layout`, not absolute positioning).
public struct NoctisFractionLayout: Layout {
    public init() {}

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let fraction = subview[NoctisFraction.self]
            let centerX = bounds.minX + bounds.width * fraction
            let x = min(max(centerX - size.width / 2, bounds.minX), bounds.maxX - size.width)
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(size))
        }
    }
}

private nonisolated struct NoctisFraction: LayoutValueKey {
    static let defaultValue: Double = 0
}

extension View {
    /// Where this view sits in a `NoctisFractionLayout` (0...1).
    public func noctisFraction(_ fraction: Double) -> some View {
        layoutValue(key: NoctisFraction.self, value: fraction)
    }
}
