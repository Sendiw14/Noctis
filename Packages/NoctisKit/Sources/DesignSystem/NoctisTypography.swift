import SwiftUI

public enum NoctisTextStyle {
    case display
    case heroNumber
    case title
    case headline
    case body
    case bodyEmphasized
    case subheadline
    case caption
    case eyebrow
    /// R4: the paper-onboarding title — 38pt bold, rounded, tracking -0.6.
    case paperTitle
    /// R4: paper-onboarding body copy — 17pt regular, rounded.
    case paperBody
    /// R4: paper-onboarding caption — 13pt, rounded.
    case paperCaption

    var baseSize: CGFloat {
        switch self {
        case .display: 44
        case .heroNumber: 76
        case .title: 26
        case .headline: 19
        case .body, .bodyEmphasized: 17
        case .subheadline: 15
        case .caption, .eyebrow: 13
        case .paperTitle: 38
        case .paperBody: 17
        case .paperCaption: 13
        }
    }

    var weight: Font.Weight {
        switch self {
        case .display, .heroNumber, .eyebrow: .bold
        case .title, .headline, .bodyEmphasized: .semibold
        case .body, .subheadline: .regular
        case .caption: .medium
        case .paperTitle: .bold
        case .paperBody: .regular
        case .paperCaption: .medium
        }
    }

    var design: Font.Design {
        switch self {
        case .display, .heroNumber, .title, .eyebrow: .rounded
        case .paperTitle, .paperBody, .paperCaption: .rounded
        default: .default
        }
    }

    /// How much this style grows under larger Dynamic Type settings — hero
    /// numbers and display text grow the least, body text the most.
    var growthFactor: CGFloat {
        switch self {
        case .display, .heroNumber: 0.5
        case .title: 0.7
        case .headline, .body, .bodyEmphasized: 1.0
        case .subheadline, .caption, .eyebrow: 1.0
        case .paperTitle: 0.6
        case .paperBody, .paperCaption: 1.0
        }
    }

    var tracking: CGFloat {
        switch self {
        case .display: -1.0
        case .heroNumber: -2.2
        case .title: -0.4
        case .headline: -0.2
        case .body, .bodyEmphasized: 0
        case .subheadline: 0
        case .caption: 0.1
        case .eyebrow: 1.4
        case .paperTitle: -0.6
        case .paperBody: 0
        case .paperCaption: 0
        }
    }

    var lineSpacing: CGFloat {
        switch self {
        case .display, .heroNumber: -2
        case .title: -1
        case .headline, .body, .bodyEmphasized: 2
        case .subheadline, .caption, .eyebrow: 1
        case .paperTitle: -1
        case .paperBody: 2
        case .paperCaption: 1
        }
    }

    var uppercase: Bool { self == .eyebrow }
}

/// A flat per-category multiplier driven directly off `DynamicTypeSize`,
/// deliberately not `@ScaledMetric` — several simultaneous `@ScaledMetric`
/// instances appearing together during an animated transition (e.g. title +
/// body sliding in on an onboarding step) can trip an internal SwiftUI
/// text-layout race (`_dispatch_assert_queue_fail` on the AsyncRenderer
/// thread). This is plain arithmetic against an environment value instead.
func dynamicTypeMultiplier(_ size: DynamicTypeSize) -> CGFloat {
    switch size {
    case .xSmall: 0.88
    case .small: 0.92
    case .medium: 0.96
    case .large: 1.0
    case .xLarge: 1.08
    case .xxLarge: 1.16
    case .xxxLarge: 1.24
    case .accessibility1: 1.4
    case .accessibility2: 1.6
    case .accessibility3: 1.8
    case .accessibility4: 2.0
    case .accessibility5: 2.2
    @unknown default: 1.0
    }
}

func scaledSize(_ style: NoctisTextStyle, _ dynamicTypeSize: DynamicTypeSize) -> CGFloat {
    let multiplier = dynamicTypeMultiplier(dynamicTypeSize)
    let eased = 1.0 + (multiplier - 1.0) * style.growthFactor
    return style.baseSize * eased
}

/// The same Dynamic-Type-scaled point size `NoctisText` uses internally,
/// exposed for callers outside this module that need to hand-build a
/// `Text` (e.g. to drive `.tracking`/`.blur` from an external animation
/// timeline) rather than use `NoctisText` itself.
public func noctisScaledSize(_ style: NoctisTextStyle, _ dynamicTypeSize: DynamicTypeSize) -> CGFloat {
    scaledSize(style, dynamicTypeSize)
}

public struct NoctisText: View {
    private let content: String
    private let style: NoctisTextStyle
    private let color: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(_ content: String, style: NoctisTextStyle, color: Color = NoctisColor.textPrimary) {
        self.content = content
        self.style = style
        self.color = color
    }

    public var body: some View {
        Text(content)
            .font(.system(size: scaledSize(style, dynamicTypeSize), weight: style.weight, design: style.design))
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
            .textCase(style.uppercase ? .uppercase : nil)
            .foregroundStyle(color)
    }
}

private struct NoctisTextStyleModifier: ViewModifier {
    let style: NoctisTextStyle
    let color: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content
            .font(.system(size: scaledSize(style, dynamicTypeSize), weight: style.weight, design: style.design))
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
            .textCase(style.uppercase ? .uppercase : nil)
            .foregroundStyle(color)
    }
}

extension View {
    /// Applies a NOCTIS text style to an arbitrary view (e.g. a Button's
    /// label) rather than constructing a new `Text` — use `NoctisText` when
    /// you're producing the string yourself.
    public func noctisText(_ style: NoctisTextStyle, color: Color = NoctisColor.textPrimary) -> some View {
        modifier(NoctisTextStyleModifier(style: style, color: color))
    }
}
