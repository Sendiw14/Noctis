import DesignSystem
import NoctisCore
import SwiftUI

/// "Compare free and Premium" (APP_RULES.md R58, R59): every feature, in plain words, with a mark and the words "Included" or "Not included" for each tier
/// (never color alone). It is made from `FeatureTable` and nothing else, so it cannot disagree with what the app does; the paywall and Settings share it.
/// Light paper, like the paywall it belongs to, with a visible "Done".
public struct PremiumComparisonSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Everything in NOCTIS keeps working on the free plan. Premium adds depth.")
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(NoctisPaper.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, NoctisSpacing.md)
                    if !dynamicTypeSize.isAccessibilitySize { headerRow }
                    ForEach(FeatureTable.comparison(), id: \.area) { group in
                        areaHeader(group.area)
                        ForEach(group.rows) { row in
                            comparisonRow(row)
                            Rectangle().fill(NoctisPaper.hairline).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, NoctisSpacing.xl)
                .padding(.top, NoctisSpacing.md)
                .padding(.bottom, NoctisSpacing.xl)
            }
            .background(NoctisPaper.bg)
            .navigationTitle("What Premium includes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("premium.compare.done")
                }
            }
        }
        .preferredColorScheme(.light)
        .accessibilityIdentifier("premium.compare")
    }

    private var headerRow: some View {
        HStack {
            Text("").frame(maxWidth: .infinity, alignment: .leading)
            Text("Free").noctisFont(13, .semibold, relativeTo: .footnote).frame(width: 84)
            Text("Premium").noctisFont(13, .semibold, relativeTo: .footnote).frame(width: 84)
        }
        .foregroundStyle(NoctisPaper.ink2)
        .padding(.vertical, NoctisSpacing.xs)
        .accessibilityHidden(true)
    }

    private func areaHeader(_ area: FeatureArea) -> some View {
        Text(area.title.uppercased())
            .noctisFont(13, .semibold, relativeTo: .footnote)
            .tracking(0.8)
            .foregroundStyle(NoctisPaper.ink3)
            .padding(.top, NoctisSpacing.lg)
            .padding(.bottom, NoctisSpacing.xs)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func comparisonRow(_ row: FeatureTable.Row) -> some View {
        let title = Text(row.title)
            .noctisFont(14, relativeTo: .subheadline)
            .foregroundStyle(NoctisPaper.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
        if dynamicTypeSize.isAccessibilitySize {
            // Stacked: the feature, then one labeled line per tier.
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                title
                stacked("Free", included: row.free)
                stacked("Premium", included: true)
            }
            .padding(.vertical, NoctisSpacing.sm)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.spoken)
        } else {
            HStack(alignment: .top) {
                title
                cell(included: row.free).frame(width: 84)
                cell(included: true).frame(width: 84)
            }
            .padding(.vertical, NoctisSpacing.sm)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.spoken)
        }
    }

    private func cell(included: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: included ? "checkmark.circle.fill" : "minus.circle")
                .noctisIcon(15, relativeTo: .caption)
                .foregroundStyle(included ? NoctisPaper.sage : NoctisPaper.ink3)
            Text(included ? "Included" : "Not included")
                .noctisFont(12, relativeTo: .caption)
                .foregroundStyle(NoctisPaper.ink2)
        }
    }

    private func stacked(_ tier: String, included: Bool) -> some View {
        HStack(spacing: NoctisSpacing.xs) {
            Image(systemName: included ? "checkmark.circle.fill" : "minus.circle")
                .noctisIcon(15, relativeTo: .footnote)
                .foregroundStyle(included ? NoctisPaper.sage : NoctisPaper.ink3)
            Text("\(tier): \(included ? "Included" : "Not included")")
                .noctisFont(13, relativeTo: .footnote)
                .foregroundStyle(NoctisPaper.ink2)
        }
    }
}
