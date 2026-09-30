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
