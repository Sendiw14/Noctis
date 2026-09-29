import SwiftUI

/// Places each subview along the width at a fraction (0 = leading edge,
/// 1 = trailing edge), kept inside the bounds: labels under a strip or
/// chart (R8: a system `Layout`, not absolute positioning).
public struct NoctisFractionLayout: Layout {
    /// Offer each subview the layout's width, so text wider than the
    /// chart wraps instead of running out of it (a pill at accessibility
    /// sizes). Off: subviews take their ideal size.
    public var wraps: Bool

    public init(wraps: Bool = false) {
        self.wraps = wraps
    }

    private func offer(_ width: CGFloat?) -> ProposedViewSize {
        wraps ? ProposedViewSize(width: width, height: nil) : .unspecified
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(offer(proposal.width)).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let size = subview.sizeThatFits(offer(bounds.width))
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

/// Stretches its one subview across part of the width, from one fraction
/// to another (0 = leading edge, 1 = trailing edge), at least `minimumWidth`
/// wide and always inside the bounds: a bar that is a share of its track, a
/// span on a time strip (R8: a system `Layout`, not absolute positioning).
public struct NoctisSpanLayout: Layout {
    public var from: Double
    public var to: Double
    public var minimumWidth: CGFloat

    public init(from: Double = 0, to: Double, minimumWidth: CGFloat = 0) {
        self.from = from
        self.to = to
        self.minimumWidth = minimumWidth
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.first.map { $0.sizeThatFits(ProposedViewSize(width: nil, height: proposal.height)).height } ?? 0
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let start = min(max(from, 0), 1)
        let end = min(max(to, start), 1)
        let width = min(max((end - start) * bounds.width, minimumWidth), bounds.width)
        let x = min(bounds.minX + start * bounds.width, bounds.maxX - width)
        subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: width, height: bounds.height))
    }
}

/// Places each subview down the height at a fraction (0 = top, 1 = bottom),
/// leading-aligned and centered on its fraction, kept inside the bounds:
/// the hour labels beside a clock axis, the values beside a chart (R8: a
/// system `Layout`).
public struct NoctisVerticalFractionLayout: Layout {
    public init() {}

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        return CGSize(width: width, height: proposal.height ?? 0)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let centerY = bounds.minY + bounds.height * subview[NoctisVerticalFraction.self]
            let y = min(max(centerY - size.height / 2, bounds.minY), bounds.maxY - size.height)
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
        }
    }
}

private nonisolated struct NoctisVerticalFraction: LayoutValueKey {
    static let defaultValue: Double = 0
}

extension View {
    /// Where this view sits in a `NoctisVerticalFractionLayout` (0 = top, 1 = bottom).
    public func noctisVerticalFraction(_ fraction: Double) -> some View {
        layoutValue(key: NoctisVerticalFraction.self, value: fraction)
    }
}

/// Stretches its one subview across the full width and part of the height,
/// from one fraction to another (0 = top, 1 = bottom), at least
/// `minimumLength` tall and always inside the bounds: a usual band, a grid
/// line on an axis. Its two ends animate, so a band follows a chart that
/// rescales.
public struct NoctisVerticalSpanLayout: Layout {
    public var from: Double
    public var to: Double
    public var minimumLength: CGFloat

    public init(from: Double, to: Double, minimumLength: CGFloat = 0) {
        self.from = from
        self.to = to
        self.minimumLength = minimumLength
    }

    public var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(from, to) }
        set {
            from = newValue.first
            to = newValue.second
        }
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let start = min(max(from, 0), 1)
        let end = min(max(to, start), 1)
        let length = min(max((end - start) * bounds.height, minimumLength), bounds.height)
        let y = min(bounds.minY + start * bounds.height, bounds.maxY - length)
        subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: length))
    }
}
