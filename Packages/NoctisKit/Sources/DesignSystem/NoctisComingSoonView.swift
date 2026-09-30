import SwiftUI

/// The placeholder for a screen that isn't built yet (APP_RULES.md R19),
/// pushed over a tab (Profile): the tab scaffold's field, the title and a
/// plain "Coming soon" card, nothing tappable. Tabs use `NoctisTabPlaceholder`
/// directly. Every screen using it is listed in ROADMAP.md.
public struct NoctisComingSoonView: View {
    private let title: String

    public init(title: String, systemImage: String = "") {
        self.title = title
    }

    public var body: some View {
        NoctisTabPlaceholder(.home, title: title, presentation: .pushed)
    }
}

#Preview("Light") {
    NoctisTabPlaceholder(.insights, title: "Insights", dateCaption: "WEDNESDAY, SEPTEMBER 30")
}

#Preview("Dark") {
    NoctisTabPlaceholder(.coach, title: "Coach", dateCaption: "WEDNESDAY, SEPTEMBER 30")
        .preferredColorScheme(.dark)
}
