import SwiftUI

/// What "Settings > Accessibility > Display & Text Size > Button Shapes" asks of a button that is only text (S1B-A01, UX-02): the system underlines text buttons,
/// but not a `.plain` button with a custom label, so a link like "Restore" looked like a caption. With the setting on, the words are underlined, the way the
/// system does it; with it off nothing changes. The underline is the text's own, so it takes the text's colour and weight, follows every wrapped line and never
/// draws outside the label (an earlier version drew a separate rule, which took the wrong colour and the full width of a wrapped label). Rows, cards and tiles
/// already have a shape of their own and do not use it.
public struct NoctisButtonShape: ViewModifier {
    private let forced: Bool?
    @Environment(\.accessibilityShowButtonShapes) private var systemSetting

    /// `showsShapes` fixes the answer (tests, previews); nil follows the setting.
    public init(showsShapes: Bool? = nil) {
        forced = showsShapes
    }

    public func body(content: Content) -> some View {
        content.underline(forced ?? systemSetting)
    }
}

extension View {
    /// Underlines the text of a text-only button when Button Shapes is on (see `NoctisButtonShape`).
    public func noctisButtonShape() -> some View { modifier(NoctisButtonShape()) }
}
