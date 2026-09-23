import DesignSystem
import NoctisCore
import RecoveryKit
import SwiftUI

struct RecoveryOrbDetailSheet: View {
    let score: RecoveryScore
    let onSeeFull: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentRevealed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: NoctisSpacing.xxl) {
                    NoctisScoreOrb(
                        score: score.overall,
                        label: "Recovery",
                        tint: NoctisColor.recoveryTint(for: score.overall),
                        diameter: 240
                    )
                    .padding(.top, NoctisSpacing.lg)

                    VStack(spacing: 0) {
                        ForEach(score.factors) { factor in
                            factorRow(factor)
                            if factor.id != score.factors.last?.id {
                                Rectangle().fill(NoctisColor.divider).frame(height: 1)
                            }
                        }
                    }
                    .opacity(contentRevealed ? 1 : 0)
                    .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion).delay(0.15), value: contentRevealed)

                    Button("See Full Recovery", action: onSeeFull)
                        .buttonStyle(.noctisSecondary)
                        .opacity(contentRevealed ? 1 : 0)
                        .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion).delay(0.22), value: contentRevealed)
                }
                .padding(NoctisSpacing.xl)
            }
            .background(NoctisColor.canvas)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear { contentRevealed = true }
    }

    private func factorRow(_ factor: RecoveryFactor) -> some View {
        NoctisFactorRow(
            systemImage: factor.kind.systemImage,
            tint: factor.kind.tint,
            title: factor.kind.displayName,
            subtitle: factor.confidence.displayName + " confidence",
            valueText: "\(factor.score)",
            progress: Double(factor.score) / 100
        )
    }
}
