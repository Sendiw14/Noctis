import DesignSystem
import HealthProviding
import NoctisCore
import SwiftUI

/// The three signals NOCTIS asks to read, in the order shown. Sourced from
/// `HealthDataKind` (shared with the rest of the app) rather than
/// hardcoded here, so the label/benefit/icon shown always matches what's
/// actually requested below. Activity/steps is deliberately excluded:
/// `RecoveryFactorKind` (RecoveryKit/RecoveryModels.swift) has no case that
/// reads activity data today, and Recovery itself is never listed here —
/// it's computed from these signals, not a permission of its own.
private let requestedKinds: [HealthDataKind] = [.sleepAnalysis, .heartRate, .hrv]

private enum ConnectOutcome {
    case idle
    case connecting
    /// `requestAuthorization` came back `.unavailable` — a genuine
    /// mid-flow failure, distinct from the user simply declining (which
    /// iOS never reports, so a plain decline is treated identically to
    /// authorized: proceed with the pulse and advance).
    case error
}

/// Step 4/6 — what NOCTIS reads from Apple Health, and why. Real HealthKit
/// authorization on "Connect" via the existing `AppModel`/`HealthDataProviding`
/// seam; the availability check and the three listed signals both come from
/// that same seam so this screen can never drift from what the rest of the
/// app actually requests.
struct HealthScreen: View {
    let onNext: () -> Void
    let onBack: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var outcome: ConnectOutcome = .idle
    @State private var circlesConverged = false
    @State private var moonVisible = false
    @State private var rowsPulsing = false
    @State private var heroHeight: CGFloat = 700

    private var isAvailable: Bool { model.isHealthDataAvailable }
    private var compact: Bool { heroHeight < 700 }

    var body: some View {
        OnboardingScaffold(
            step: 3,
            title: "Connect your",
            emphasis: "signals.",
            onBack: onBack
        ) {
            VStack(spacing: NoctisScrollEdges.blockGap(compact ? NoctisSpacing.sm : NoctisSpacing.lg, dynamicTypeSize)) {
                hero
                if !isAvailable {
                    unavailableBanner
                        .noctisTextBlock()
                        .noctisScrollRow()
                }
                signalCard
                    .noctisScrollRow()
                privacyLine
                    .noctisTextBlock()
            }
            .padding(.bottom, NoctisSpacing.xs)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { heroHeight = geometry.size.height }
                        .onChange(of: geometry.size.height) { _, newHeight in heroHeight = newHeight }
                }
            )
        } bottomStack: {
            bottomStack
        }
        .onAppear { runHeroEntranceIfNeeded() }
    }

    // MARK: - Hero

    private var hero: some View {
        // R16: 110pt so the whole screen fits iPhone 17 Pro unscrolled.
        let diameter: CGFloat = 110
        let spread: CGFloat = compact ? 100 : 150
        let clustered: CGFloat = compact ? 44 : 62
        // Sized to the circles (what the old 26%-of-content rule always
        // resolved to at standard sizes); large text no longer inflates it.
        let bandHeight = diameter + NoctisSpacing.lg

        return ZStack {
            circle(NoctisPaper.sage, diameter: diameter)
                .offset(x: circlesConverged ? -clustered : -spread, y: compact ? 6 : 8)
            circle(NoctisPaper.lavender, diameter: diameter)
                .offset(x: circlesConverged ? clustered : spread, y: compact ? 6 : 8)
            circle(NoctisPaper.orange, diameter: diameter)
                .offset(y: compact ? -6 : -8)

            // Ivory, not cocoa: the three circles multiply-blend to a dark
            // overlap right where this glyph sits, and cocoa-on-that-dark
            // read as invisible.
            Image(systemName: "moon.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(NoctisPaper.ivory)
                .opacity(moonVisible ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: bandHeight)
        .accessibilityHidden(true)
    }

    private func circle(_ fill: Color, diameter: CGFloat) -> some View {
        Circle()
            .fill(isAvailable ? fill : NoctisPaper.track)
            .blendMode(.multiply)
            .frame(width: diameter, height: diameter)
    }

    /// R9/screen spec: the three signal circles start apart and slide into
    /// an overlapping cluster over ~0.9s (`.settle`), with the moon fading
    /// in once they've converged. Reduce Motion skips straight to the
    /// static, already-overlapped result — no slide, no fade.
    private func runHeroEntranceIfNeeded() {
        guard !reduceMotion else {
            circlesConverged = true
            moonVisible = true
            return
        }
        guard !circlesConverged else { return }
        withAnimation(NoctisMotion.settle) {
            circlesConverged = true
        }
        withAnimation(.easeIn(duration: 0.4).delay(0.5)) {
            moonVisible = true
        }
    }

    // MARK: - Unavailable banner

    private var unavailableBanner: some View {
        HStack(spacing: NoctisSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .noctisIcon(15, relativeTo: .subheadline)
                .foregroundStyle(NoctisPaper.orangeText)
                .accessibilityHidden(true)
            Text("Health data isn't available on this device.")
                .noctisFont(14, relativeTo: .subheadline)
                .foregroundStyle(NoctisPaper.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(NoctisSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: NoctisRadius.md, style: .continuous)
                .fill(NoctisPaper.butter.opacity(0.35))
        )
    }

    // MARK: - Signal card

    /// R15's compact card, so the screen fits iPhone 17 Pro unscrolled (R16).
    private var signalCard: some View {
        NoctisPaperCard(density: .compact) {
            VStack(spacing: 0) {
                ForEach(Array(requestedKinds.enumerated()), id: \.element) { index, kind in
                    signalRow(kind)
                        .noctisTextBlock()
                        .opacity(isAvailable ? 1 : 0.4)
                        .scaleEffect(rowsPulsing ? 1.03 : 1.0)
                    if index < requestedKinds.count - 1 {
                        Rectangle()
                            .fill(NoctisPaper.hairline)
                            .frame(height: 1)
                            .padding(.vertical, NoctisScrollEdges.blockGap(compact ? NoctisSpacing.xs : NoctisSpacing.sm, dynamicTypeSize) / 2)
                    }
                }
            }
        }
        .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion), value: rowsPulsing)
    }

    private func signalRow(_ kind: HealthDataKind) -> some View {
        HStack(spacing: NoctisSpacing.md) {
            NoctisIconTile(systemImage: kind.systemImage, fill: signalFill(kind), size: compact ? 38 : 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.rowTitle)
                    .noctisFont(17, .semibold, relativeTo: .body)
                    .foregroundStyle(NoctisPaper.ink)
                Text(kind.benefit)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(NoctisPaper.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.rowTitle). \(kind.benefit)")
    }

    private func signalFill(_ kind: HealthDataKind) -> Color {
        switch kind {
        case .sleepAnalysis: NoctisPaper.sage
        case .heartRate: NoctisPaper.orange
        case .hrv: NoctisPaper.lavender
        default: NoctisPaper.cocoa
        }
    }

    // MARK: - Privacy line

    private var privacyLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .noctisIcon(12, relativeTo: .footnote)
                .accessibilityHidden(true)
            Text("Read-only. You control access in the Health app at any time.")
                .noctisFont(13, relativeTo: .footnote)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(NoctisPaper.ink3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Bottom stack

    @ViewBuilder
    private var bottomStack: some View {
        if !isAvailable {
            NoctisCTA("Continue without Health data", action: onNext)
        } else {
            switch outcome {
            case .error:
                VStack(spacing: NoctisSpacing.sm) {
                    Text("Couldn't reach Health right now.")
                        .noctisFont(14, relativeTo: .subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(NoctisPaper.ink2)
                    NoctisCTA("Try again", action: connect)
                    NoctisTextButton("Continue without Health data", action: onNext)
                }
            case .idle, .connecting:
                VStack(spacing: NoctisSpacing.sm) {
                    NoctisCTA("Connect Apple Health", isLoading: outcome == .connecting, action: connect)
                    NoctisTextButton("Continue without Health data", action: onNext)
                }
            }
        }
    }

    private func connect() {
        NoctisHaptics.softImpact()
        outcome = .connecting
        Task {
            await model.requestHealthAuthorization(for: requestedKinds)
            guard model.healthAuthorization != .unavailable else {
                outcome = .error
                return
            }
            outcome = .idle
            // R9: one synchronized settle pulse — never a per-row stagger,
            // and never a checkmark/"connected" state, since iOS never
            // actually reveals which of these were granted.
            withAnimation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion)) {
                rowsPulsing = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion)) {
                    rowsPulsing = false
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                onNext()
            }
        }
    }
}

private extension HealthDataKind {
    /// `displayName` (shared elsewhere as e.g. "Resting Heart Rate") is a
    /// touch more clinical than this row wants; these three specific
    /// labels match the screen's own copy without duplicating the
    /// benefit/icon/systemImage already owned by `HealthDataKind`.
    var rowTitle: String {
        switch self {
        case .sleepAnalysis: "Sleep"
        case .heartRate: "Heart rate"
        case .hrv: "HRV"
        default: displayName
        }
    }
}
