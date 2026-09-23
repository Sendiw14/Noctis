import DesignSystem
import InsightsKit
import NoctisCore
import SwiftUI

public struct InsightsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if model.insights.isEmpty {
                        InsightsLearningState(nightsLogged: model.today?.scoredSessions.count ?? 0)
                            .transition(.opacity)
                    } else {
                        ForEach(model.insights) { insight in
                            NavigationLink {
                                InsightDetailView(insight: insight)
                            } label: {
                                InsightRow(insight: insight)
                            }
                            .buttonStyle(.noctisPress)
                            .transition(.opacity)
                            if insight.id != model.insights.last?.id {
                                Rectangle().fill(NoctisColor.divider).frame(height: 1)
                            }
                        }
                    }
                }
                .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion), value: model.insights.isEmpty)
                .padding(NoctisSpacing.xl)
            }
            .background(NoctisColor.canvas)
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

/// "What NOCTIS knows / is learning" — built entirely from real numbers
/// (nights actually logged, the richest detector's real threshold). Never
/// a fabricated progress value.
///
/// An empty insight list has two genuinely different causes that must not
/// be conflated: not enough history yet, or enough history but nothing
/// that crossed a detector's real threshold recently. Each gets its own,
/// honest copy.
private struct InsightsLearningState: View {
    let nightsLogged: Int
    private let fullPictureThreshold = InsightEngine.richestSignalWindow

    private var hasFullHistory: Bool { nightsLogged >= fullPictureThreshold }

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.xl) {
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                NoctisText("LEARNING", style: .eyebrow, color: NoctisColor.textTertiary)
                if hasFullHistory {
                    NoctisText("No new patterns right now.", style: .title)
                    NoctisText(
                        "NOCTIS has enough history — it just hasn't found a change big enough to be worth mentioning. Insights appear when something real shifts, not on a schedule.",
                        style: .body,
                        color: NoctisColor.textSecondary
                    )
                } else {
                    NoctisText("Still learning your patterns.", style: .title)
                    NoctisText(
                        "NOCTIS looks for real, repeated patterns — this week compared with last, earlier bedtimes compared with later ones. It never guesses ahead of the data.",
                        style: .body,
                        color: NoctisColor.textSecondary
                    )
                }
            }

            if !hasFullHistory {
                VStack(spacing: NoctisSpacing.sm) {
                    row(label: "Nights logged so far", value: "\(nightsLogged)")
                    Rectangle().fill(NoctisColor.divider).frame(height: 1)
                    row(label: "Needed for the fullest picture", value: "\(fullPictureThreshold)")
                }

                ProgressView(value: min(Double(nightsLogged), Double(fullPictureThreshold)), total: Double(fullPictureThreshold))
                    .tint(NoctisColor.sage)
                    .accessibilityLabel("\(nightsLogged) of \(fullPictureThreshold) nights needed for the fullest picture")
            }
        }
        .padding(.top, NoctisSpacing.xxxl)
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            NoctisText(label, style: .subheadline, color: NoctisColor.textSecondary)
            Spacer()
            NoctisText(value, style: .bodyEmphasized)
        }
    }
}

private struct InsightRow: View {
    let insight: Insight

    var body: some View {
        HStack(alignment: .top, spacing: NoctisSpacing.md) {
            Capsule()
                .fill(insight.category.tint)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                NoctisText(insight.category.displayName, style: .eyebrow, color: NoctisColor.textTertiary)
                NoctisText(insight.title, style: .bodyEmphasized, color: NoctisColor.textPrimary)
                NoctisText(insight.interpretation, style: .subheadline, color: NoctisColor.textSecondary)
            }
        }
        .padding(.vertical, NoctisSpacing.sm)
        .accessibilityElement(children: .combine)
    }
}

struct InsightDetailView: View {
    let insight: Insight

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoctisSpacing.xl) {
                HStack(alignment: .top, spacing: NoctisSpacing.md) {
                    Capsule()
                        .fill(insight.category.tint)
                        .frame(width: 3)
                        .frame(maxHeight: .infinity)
                    VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                        NoctisText(insight.category.displayName, style: .eyebrow, color: NoctisColor.textTertiary)
                        NoctisText(insight.title, style: .title)
                    }
                }

                HStack(spacing: NoctisSpacing.lg) {
                    ForEach(insight.evidence) { point in
                        VStack(alignment: .leading, spacing: 2) {
                            NoctisText(point.label, style: .caption, color: NoctisColor.textTertiary)
                            NoctisText(point.value, style: .bodyEmphasized)
                        }
                    }
                }

                section("Context", insight.context)
                section("What This Means", insight.interpretation)
                section("What To Notice", insight.whatToNotice)
                if let suggestion = insight.suggestion {
                    section("What You Can Try", suggestion)
                }

                NoctisConfidenceBadge(label: "\(insight.confidence.displayName) confidence", tint: NoctisColor.textTertiary)
            }
            .padding(NoctisSpacing.xl)
        }
        .background(NoctisColor.canvas)
        .navigationTitle("Insight")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
            NoctisText(title, style: .eyebrow, color: NoctisColor.textTertiary)
            NoctisText(body, style: .body, color: NoctisColor.textSecondary)
        }
    }
}
