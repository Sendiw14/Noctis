import SwiftUI

/// 13pt uppercase caption with 0.08em tracking ("LAST NIGHT").
public struct NoctisCaption<Style: ShapeStyle>: View {
    let text: String
    let style: Style

    public init(_ text: String, style: Style) {
        self.text = text
        self.style = style
    }

    public var body: some View {
        Text(text)
            .noctisFont(13, .semibold, relativeTo: .footnote)
            .tracking(13 * 0.08)
            .foregroundStyle(style)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A card's caption with something at its trailing end ("SLEEP QUALITY" and "Last 30 nights"). Side by side when they fit; the trailing part under
/// the caption when they do not. In an HStack at accessibility sizes the caption wrapped into a second line that the row did not make room for, so it
/// overprinted the title below it ("SLEEP QUALITY" under "30-night average 93" at AX3) and lost its last letter at AX5.
public struct NoctisCaptionRow<Trailing: View>: View {
    let text: String
    let trailing: Trailing

    public init(_ text: String, @ViewBuilder trailing: () -> Trailing) {
        self.text = text
        self.trailing = trailing()
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                NoctisCaption(text, style: .noctisInk3)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: NoctisSpacing.xs)
                trailing
            }
            VStack(alignment: .leading, spacing: 2) {
                NoctisCaption(text, style: .noctisInk3)
                trailing
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
