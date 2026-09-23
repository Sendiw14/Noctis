import SwiftUI

/// R4: every onboarding text keeps its designed point size at the default
/// text size (Large) and scales with Dynamic Type along one system text
/// style's curve, via `@ScaledMetric`:
///
/// | Role                                   | Anchor          |
/// |----------------------------------------|-----------------|
/// | Titles, hero numerals (cap 1.6x)       | `.largeTitle`   |
/// | Body copy, row titles, CTA labels (17) | `.body`         |
/// | Labels, secondary lines (14–16)        | `.subheadline`  |
/// | Captions (13)                          | `.footnote`     |
/// | Small print, badges (≤12)              | `.caption`      |
///
/// Icons and tiles beside text scale with the text they sit next to,
/// capped at `maxIconScale` so a glyph never outgrows its row.
public enum NoctisTypeScale {
    /// Hero numerals stop growing here so they stay inside their card.
    public static let maxNumeralScale: CGFloat = 1.6
    /// Icons, tiles and marks beside text stop growing here.
    public static let maxIconScale: CGFloat = 1.6
}

private struct NoctisScaledFont: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat
    private let size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design
    private let maxScale: CGFloat?

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, style: Font.TextStyle, maxScale: CGFloat?) {
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.size = size
        self.weight = weight
        self.design = design
        self.maxScale = maxScale
    }

    func body(content: Content) -> some View {
        let pointSize = maxScale.map { min(scaledSize, size * $0) } ?? scaledSize
        content.font(.system(size: pointSize, weight: weight, design: design))
    }
}

extension View {
    /// SF Rounded at `size` points at the default text size, scaling with
    /// Dynamic Type along `style`'s curve (R4). `maxScale` optionally caps
    /// the growth as a multiple of `size`.
    public func noctisFont(
        _ size: CGFloat,
        _ weight: Font.Weight = .regular,
        relativeTo style: Font.TextStyle,
        design: Font.Design = .rounded,
        maxScale: CGFloat? = nil
    ) -> some View {
        modifier(NoctisScaledFont(size: size, weight: weight, design: design, style: style, maxScale: maxScale))
    }

    /// R4 hero numerals: `Font.system(size:weight:design:)` on the
    /// `.largeTitle` curve, capped at 1.6x, one line, and shrinking to fit
    /// if a narrow card still can't hold the capped size.
    public func noctisNumeral(_ size: CGFloat, _ weight: Font.Weight = .heavy, minimumScaleFactor: CGFloat = 0.5) -> some View {
        noctisFont(size, weight, relativeTo: .largeTitle, maxScale: NoctisTypeScale.maxNumeralScale)
            .lineLimit(1)
            .minimumScaleFactor(minimumScaleFactor)
    }

    /// An SF Symbol beside text: scales with that text's style, capped at
    /// `NoctisTypeScale.maxIconScale`.
    public func noctisIcon(_ size: CGFloat, _ weight: Font.Weight = .semibold, relativeTo style: Font.TextStyle = .body) -> some View {
        noctisFont(size, weight, relativeTo: style, design: .default, maxScale: NoctisTypeScale.maxIconScale)
    }
}

/// A length (a tile, a mark, a dot) that scales beside text: `base` at the
/// default text size, growing with `style` up to `maxIconScale`.
@propertyWrapper
public struct NoctisScaledLength: DynamicProperty {
    @ScaledMetric private var scaled: CGFloat
    private let base: CGFloat

    public init(wrappedValue: CGFloat, relativeTo style: Font.TextStyle = .body) {
        _scaled = ScaledMetric(wrappedValue: wrappedValue, relativeTo: style)
        base = wrappedValue
    }

    public var wrappedValue: CGFloat { min(scaled, base * NoctisTypeScale.maxIconScale) }
}

/// The scale factor (1 at the default text size) of `style`'s Dynamic Type
/// curve, capped like icons. For sizes computed from one base, e.g. a
/// tile whose glyph is a fraction of its diameter.
@propertyWrapper
public struct NoctisScaleFactor: DynamicProperty {
    @ScaledMetric private var scaled: CGFloat

    public init(relativeTo style: Font.TextStyle = .body) {
        _scaled = ScaledMetric(wrappedValue: 100, relativeTo: style)
    }

    public var wrappedValue: CGFloat { min(scaled / 100, NoctisTypeScale.maxIconScale) }
}
