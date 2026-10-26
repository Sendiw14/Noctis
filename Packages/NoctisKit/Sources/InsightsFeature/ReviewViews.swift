import DesignSystem
import NoctisCore
import Observation
import ReviewKit
import SwiftUI

// The Reviews row on the Insights tab (APP_RULES.md R63). Every sentence comes from `ReviewRoute`, `ReviewScreenBuilder` and `ReviewStoryBuilder`, never
// from a view.

/// The Reviews row, above Recent: opens the Reviews list.
struct InsightsReviewsRow: View {
    let open: () -> Void

    var body: some View {
        NoctisRowCard {
            NoctisLinkRow(
                systemImage: "calendar", fill: NoctisAppColor.blockLavender, title: "Reviews", detail: "Your weekly and monthly reviews",
                hint: "Opens your reviews.",
                identifier: "insights.reviews", action: open
            )
        }
    }
}

/// A calm card with a caption, a line and a sentence: the count, or the word that the screen is coming.
struct ReviewMessageCard: View {
    let caption: String
    let headline: String
    let detail: String
    let identifier: String
    /// The headline is a number ("4 of 5 nights"): set large.
    var prominent = false

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                NoctisCaption(caption, style: .noctisInk3)
                Text(headline)
                    .noctisFont(prominent ? 34 : 22, .bold, relativeTo: prominent ? .largeTitle : .title3)
                    .foregroundStyle(NoctisAppColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
