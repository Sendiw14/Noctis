import Charts
import DesignSystem
import NoctisCore
import SleepKit
import SwiftUI

public struct SleepView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoctisSpacing.xxl) {
                    switch model.dataState {
                    case .loading:
                        NoctisLoadingState("Reading your latest sleep data…")
                            .transition(.opacity)
                    case .ready, .partial:
                        if let today = model.today {
                            content(today)
                                .transition(.opacity)
                        } else {
                            NoctisLoadingState("Reading your latest sleep data…")
                                .transition(.opacity)
                        }
                    default:
                        NoctisStateView(
                            systemImage: "bed.double",
                            title: "No sleep data yet",
                            message: "Once NOCTIS reads a night of sleep from Health, it will appear here."
                        )
                        .transition(.opacity)
                    }
                }
                .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion), value: model.dataState)
                .padding(NoctisSpacing.xl)
            }
            .background(NoctisColor.canvas)
            .navigationTitle("Sleep")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func content(_ today: TodaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.xxl) {
            hero(today)

            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                NoctisSectionHeader("Last Night")
                SleepTimelineView(
                    session: today.session,
                    heartRateSamples: today.nightHeartRateSamples,
                    respiratoryRate: today.nightRespiratoryRate
                )
            }

            detailsGrid(today)

            if today.scoredSessions.count >= 5 {
                historyChart(today)
            }
        }
    }

    private func hero(_ today: TodaySnapshot) -> some View {
        VStack(spacing: NoctisSpacing.xs) {
            NoctisText(formatDuration(today.session.totalAsleep), style: .heroNumber)
            NoctisText("\(today.quality.overall)% Sleep Quality", style: .subheadline, color: NoctisColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func detailsGrid(_ today: TodaySnapshot) -> some View {
        let session = today.session
        let items: [(String, String)] = [
            ("Time in Bed", formatDuration(session.timeInBed)),
            ("Efficiency", "\(Int(session.sleepEfficiency * 100))%"),
            ("Awakenings", "\(session.awakeningsCount)"),
            ("REM", formatDuration(session.remDuration)),
            ("Core", formatDuration(session.coreDuration)),
            ("Deep", formatDuration(session.deepDuration)),
        ]
        return VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
            NoctisSectionHeader("Sleep Details")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: NoctisSpacing.lg) {
                ForEach(items, id: \.0) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        NoctisText(item.0, style: .caption, color: NoctisColor.textTertiary)
                        NoctisText(item.1, style: .bodyEmphasized)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func historyChart(_ today: TodaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
            NoctisSectionHeader("Recent Nights")
            Chart(today.scoredSessions.suffix(14), id: \.session.id) { scored in
                BarMark(
                    x: .value("Night", scored.session.bedtime, unit: .day),
                    y: .value("Hours", scored.session.totalAsleep / 3600)
                )
                .foregroundStyle(NoctisColor.factorSleep)
                .cornerRadius(3)
            }
            .chartXAxis(.hidden)
            .frame(height: 120)
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval / 60)
        return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
    }
}
