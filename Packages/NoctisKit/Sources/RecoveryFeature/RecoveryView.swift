import Charts
import DesignSystem
import InsightsKit
import NoctisCore
import RecoveryKit
import SwiftUI

public struct RecoveryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoctisSpacing.xxl) {
                    switch model.dataState {
                    case .loading:
                        NoctisLoadingState("Reading your recovery data…")
                            .transition(.opacity)
                    case .ready, .partial:
                        if let today = model.today {
                            content(today)
                                .transition(.opacity)
                        } else {
                            NoctisLoadingState("Reading your recovery data…")
                                .transition(.opacity)
                        }
                    default:
                        NoctisStateView(
                            systemImage: "heart.slash",
                            title: "No recovery yet",
                            message: "Once NOCTIS reads a full night of sleep, your recovery will appear here."
                        )
                        .transition(.opacity)
                    }
                }
                .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion), value: model.dataState)
                .padding(NoctisSpacing.xl)
            }
            .background(NoctisColor.canvas)
            .navigationTitle("Recovery")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func content(_ today: TodaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.xxl) {
            VStack(spacing: NoctisSpacing.sm) {
                NoctisScoreOrb(
                    score: today.recovery.overall,
                    label: "Recovery",
                    tint: NoctisColor.recoveryTint(for: today.recovery.overall),
                    diameter: 240
                )
                if let delta = today.recovery.deltaVsRecentBaseline, delta != 0 {
                    NoctisText(deltaDescription(delta), style: .caption, color: NoctisColor.textSecondary)
                }
                NoctisConfidenceBadge(label: "\(today.recovery.confidence.displayName) confidence", tint: NoctisColor.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, NoctisSpacing.lg)

            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                NoctisSectionHeader("Contributors")
                VStack(spacing: 0) {
                    ForEach(today.recovery.factors) { factor in
                        NavigationLink {
                            RecoveryFactorDetailView(factor: factor)
                        } label: {
                            NoctisFactorRow(
                                systemImage: factor.kind.systemImage,
                                tint: factor.kind.tint,
                                title: factor.kind.displayName,
                                subtitle: factor.confidence.displayName + " confidence",
                                valueText: "\(factor.score)",
                                progress: Double(factor.score) / 100
                            )
                        }
                        .buttonStyle(.noctisPress)
                        if factor.id != today.recovery.factors.last?.id {
                            Rectangle().fill(NoctisColor.divider).frame(height: 1)
                        }
                    }
                }
            }

            if today.recoveryHistory.count >= 3 {
                VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                    NoctisSectionHeader("Last 30 Days")
                    Chart(today.recoveryHistory, id: \.date) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Recovery", point.score))
                            .foregroundStyle(NoctisColor.sage)
                            .interpolationMethod(.catmullRom)
                        AreaMark(x: .value("Date", point.date), y: .value("Recovery", point.score))
                            .foregroundStyle(NoctisColor.sage.opacity(0.12))
                            .interpolationMethod(.catmullRom)
                    }
                    .chartYScale(domain: 0...100)
                    .chartXAxis(.hidden)
                    .frame(height: 140)
                    .accessibilityLabel(
                        "Recovery trend over the last \(today.recoveryHistory.count) days, currently \(today.recovery.overall)"
                    )
                }
            }
        }
    }

    private func deltaDescription(_ delta: Int) -> String {
        delta > 0 ? "+\(delta) vs your recent baseline" : "\(delta) vs your recent baseline"
    }
}
