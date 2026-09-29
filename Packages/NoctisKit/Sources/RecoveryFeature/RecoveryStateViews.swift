import DesignSystem
import HomeFeature
import NoctisCore
import SwiftUI

/// Apple Health hasn't updated: what's shown is what was last read.
struct RecoveryBannerView: View {
    let banner: RecoveryBanner
    @Environment(\.openURL) private var openURL

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                Text(banner.title)
                    .noctisFont(15, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(NoctisAppColor.ink)
                Text(banner.detail)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                if let health = URL(string: "x-apple-health://") {
                    NoctisTextButton("Open Health", adaptive: true) { openURL(health) }
                        .accessibilityHint("Opens the Health app.")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recovery.banner")
    }
}

/// Nothing to show yet: what's going on, and its one action.
struct RecoveryStateView: View {
    let state: RecoveryStateContent
    let viewModel: RecoveryViewModel
    @Environment(\.openURL) private var openURL
    @State private var connecting = false

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            DormantRingView()
            switch state {
            case .connect(let title, let message, let showsButton):
                DormantTextView(title: title, detail: message, titleSize: 22)
                if showsButton {
                    NoctisCTA("Connect Apple Health", isLoading: connecting, adaptive: true) {
                        connecting = true
                        Task {
                            await viewModel.connectAppleHealth()
                            connecting = false
                        }
                    }
                }
            case .noSleepData(let title, let message):
                DormantTextView(title: title, detail: message, titleSize: 22)
                if let health = URL(string: "x-apple-health://") {
                    NoctisTextButton("Open Health", adaptive: true) { openURL(health) }
                        .accessibilityHint("Opens the Health app.")
                }
            case .failed(let message):
                DormantTextView(title: message, detail: nil)
                NoctisCTA("Try again", icon: "arrow.clockwise", adaptive: true) {
                    Task { await viewModel.refresh() }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, NoctisSpacing.xl)
        .accessibilityIdentifier("recovery.state")
    }
}

/// Learning your baseline: the dormant ring, one dot per night needed
/// (recorded nights filled), and how many so far.
struct RecoveryLearningView: View {
    let content: RecoveryLearningContent

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            DormantRingView()
            LearningDots(nights: content.nights, required: content.required)
            DormantTextView(title: "Learning your baseline", detail: content.text, alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, NoctisSpacing.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Learning your baseline, \(content.nights) of \(content.required) nights recorded.")
        .accessibilityIdentifier("recovery.learning")
    }
}

/// Data is current, but no sleep was recorded last night.
struct RecoveryNoSleepView: View {
    let content: RecoveryNoSleepContent

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            DormantRingView()
            DormantTextView(title: content.title, detail: content.detail)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, NoctisSpacing.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([content.title, content.detail].compactMap { $0 }.joined(separator: " "))
        .accessibilityIdentifier("recovery.noSleep")
    }
}

/// Track-colored blocks shaped like Today while the first snapshot
/// loads; a slow pulse, none under Reduce Motion or Low Power Mode.
struct RecoverySkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false
    var lowPower: Bool { HomeViewModel.systemLowPower() }

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            Circle().fill(NoctisAppColor.track).frame(width: 220, height: 220)
            Capsule().fill(NoctisAppColor.track).frame(width: 160, height: 18)
            block(height: 190)
            block(height: 150)
            block(height: 150)
        }
        .frame(maxWidth: .infinity)
        .opacity(dimmed ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion, !lowPower else { return }
            withAnimation(NoctisMotion.pulse) { dimmed = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your recovery")
    }

    private func block(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous)
            .fill(NoctisAppColor.track)
            .frame(height: height)
    }
}
