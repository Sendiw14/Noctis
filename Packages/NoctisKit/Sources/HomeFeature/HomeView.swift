import DesignSystem
import InsightsKit
import NoctisCore
import RecoveryKit
import SettingsFeature
import SleepKit
import SwiftUI

public struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSettings = false
    @State private var showRecoveryDetail = false
    /// Flips once, the first time real content appears, and then stays
    /// `true` for the rest of the session — the staggered hero entrance is
    /// a first-load moment, not something that should replay on every
    /// pull-to-refresh.
    @State private var heroSettled = false
    @Namespace private var orbNamespace

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoctisSpacing.xl) {
                    greeting
                    stateContent
                        .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion), value: model.dataState)
                }
                .padding(.horizontal, NoctisSpacing.xl)
                .padding(.vertical, NoctisSpacing.lg)
            }
            .background(NoctisColor.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Profile and Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .task { await model.refresh() }
            .refreshable { await model.refresh() }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 2) {
            NoctisText(greetingWord, style: .subheadline, color: NoctisColor.textSecondary)
            NoctisText(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()), style: .caption, color: NoctisColor.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private var greetingWord: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let name = model.profile.name.isEmpty ? "" : ", \(model.profile.name)"
        switch hour {
        case 0..<12: return "Good morning\(name)"
        case 12..<17: return "Good afternoon\(name)"
        default: return "Good evening\(name)"
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch model.dataState {
        case .loading:
            NoctisLoadingState("Reading your latest sleep data…")
                .transition(.opacity)
        case .noData:
            NoctisStateView(
                systemImage: "moon.zzz.fill",
                title: "Your first night starts here.",
                message: "Connect Apple Health so NOCTIS can read your sleep and heart data each morning.",
                primaryAction: .init("Connect Apple Health") { Task { await model.requestHealthAuthorization(); await model.refresh() } }
            )
            .transition(.opacity)
        case .permissionRequired:
            NoctisStateView(
                systemImage: "hand.raised.fill",
                title: "Health access needed",
                message: "NOCTIS needs permission to read sleep and heart data to show your recovery.",
                primaryAction: .init("Grant Access") { Task { await model.requestHealthAuthorization(); await model.refresh() } }
            )
            .transition(.opacity)
        case .healthKitUnavailable:
            NoctisStateView(
                systemImage: "exclamationmark.triangle.fill",
                title: "Health data isn't available right now.",
                message: "You can still explore NOCTIS. Reconnect anytime from Settings.",
                secondaryAction: .init("Open Settings") { showSettings = true }
            )
            .transition(.opacity)
        case .error(let message):
            NoctisStateView(
                systemImage: "wifi.exclamationmark",
                title: "Something went wrong",
                message: message,
                primaryAction: .init("Try Again") { Task { await model.refresh() } }
            )
            .transition(.opacity)
        case .partial(let message):
            VStack(alignment: .leading, spacing: NoctisSpacing.lg) {
                NoctisStaleBanner(message)
                if let today = model.today { readyContent(today) }
            }
            .transition(.opacity)
        case .ready:
            if let today = model.today {
                readyContent(today)
                    .transition(.opacity)
            } else {
                NoctisLoadingState("Reading your latest sleep data…")
                    .transition(.opacity)
            }
        }
    }

    private func readyContent(_ today: TodaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            recoverySection(today)
                .padding(.bottom, NoctisSpacing.massive)
            heroSequenced(order: 0) { metricsSection(today) }
                .padding(.bottom, NoctisSpacing.xxl)
            if let insight = model.insights.first {
                heroSequenced(order: 1) { insightSection(insight: insight) }
                    .padding(.bottom, NoctisSpacing.xxl)
            }
            heroSequenced(order: 2) { tonightSection(today) }
                .padding(.bottom, NoctisSpacing.xl)
            heroSequenced(order: 3) { quickActions }
        }
        .onAppear { heroSettled = true }
    }

    /// Beat 4-7 of the hero entrance (environment → orb → score/ring already
    /// happen inside `NoctisScoreOrb` itself, untouched): the sections below
    /// the orb settle in with a short, restrained stagger rather than
    /// appearing all at once. Section-level only — never per-row.
    @ViewBuilder
    private func heroSequenced(order: Int, @ViewBuilder content: () -> some View) -> some View {
        content()
            .opacity(heroSettled ? 1 : 0)
            .animation(
                NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion).delay(0.15 + Double(order) * 0.07),
                value: heroSettled
            )
    }

    private func recoverySection(_ today: TodaySnapshot) -> some View {
        VStack(spacing: NoctisSpacing.sm) {
            Button {
                NoctisHaptics.medium()
                showRecoveryDetail = true
            } label: {
                NoctisScoreOrb(
                    score: today.recovery.overall,
                    label: "Recovery",
                    tint: NoctisColor.recoveryTint(for: today.recovery.overall),
                    diameter: 268
                )
            }
            .buttonStyle(.noctisPress)
            .matchedTransitionSource(id: "recoveryOrb", in: orbNamespace)

            if let delta = today.recovery.deltaVsRecentBaseline, delta != 0 {
                NoctisText(deltaDescription(delta), style: .caption, color: NoctisColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, NoctisSpacing.lg)
        .sheet(isPresented: $showRecoveryDetail) {
            RecoveryOrbDetailSheet(score: today.recovery) { showRecoveryDetail = false; model.selectedTab = .recovery }
                .navigationTransition(.zoom(sourceID: "recoveryOrb", in: orbNamespace))
        }
    }

    private func deltaDescription(_ delta: Int) -> String {
        delta > 0 ? "+\(delta) vs your recent baseline" : "\(delta) vs your recent baseline"
    }

    private func metricsSection(_ today: TodaySnapshot) -> some View {
        NoctisMetricRow([
            NoctisMetricRowItem(systemImage: "bed.double.fill", value: formatDuration(today.session.totalAsleep), label: "Sleep", tint: NoctisColor.factorSleep),
            NoctisMetricRowItem(systemImage: "waveform.path.ecg", value: "\(today.quality.overall)%", label: "Quality", tint: NoctisColor.amber),
            NoctisMetricRowItem(systemImage: "moon.fill", value: bedtimeString(today), label: "Bedtime", tint: NoctisColor.violet),
        ])
    }

    private func insightSection(insight: Insight) -> some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
            NoctisSectionHeader("Today's Insight")
            HStack(alignment: .top, spacing: NoctisSpacing.md) {
                Capsule()
                    .fill(NoctisColor.violet)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
                VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                    NoctisText(insight.title, style: .title)
                    NoctisText(insight.interpretation, style: .subheadline, color: NoctisColor.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func tonightSection(_ today: TodaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
            NoctisSectionHeader("Tonight")
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
                    NoctisText("Suggested wind-down", style: .caption, color: NoctisColor.canvas.opacity(0.55))
                    NoctisText(suggestedBedtime(today), style: .title, color: NoctisColor.canvas)
                }
                Spacer()
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(NoctisColor.amber)
            }
            .padding(NoctisSpacing.lg)
            .background(RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous).fill(NoctisColor.textPrimary))
            .accessibilityElement(children: .combine)
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
            NoctisSectionHeader("Quick Actions")
            HStack(spacing: NoctisSpacing.xl) {
                quickActionButton(title: "Sleep", systemImage: "moon.stars.fill", tint: NoctisColor.violet) { model.selectedTab = .sleep }
                quickActionButton(title: "Recovery", systemImage: "heart.fill", tint: NoctisColor.sage) { model.selectedTab = .recovery }
                quickActionButton(title: "Insights", systemImage: "lightbulb.fill", tint: NoctisColor.amber) { model.selectedTab = .insights }
            }
        }
    }

    private func quickActionButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: NoctisSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(tint.opacity(0.12)))
                NoctisText(title, style: .caption, color: NoctisColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.noctisPress)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval / 60)
        return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
    }

    private func bedtimeString(_ today: TodaySnapshot) -> String {
        today.session.bedtime.formatted(date: .omitted, time: .shortened)
    }

    private func suggestedBedtime(_ today: TodaySnapshot) -> String {
        let target = Calendar.current.date(byAdding: .minute, value: -Int(today.balance.needHours * 60), to: nextWakeDate(today)) ?? .now
        return target.formatted(date: .omitted, time: .shortened)
    }

    private func nextWakeDate(_ today: TodaySnapshot) -> Date {
        Calendar.current.date(bySettingHour: model.profile.typicalWakeMinutes / 60, minute: model.profile.typicalWakeMinutes % 60, second: 0, of: .now.addingTimeInterval(86400)) ?? .now
    }
}
