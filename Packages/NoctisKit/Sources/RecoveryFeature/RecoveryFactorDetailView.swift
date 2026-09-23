import DesignSystem
import RecoveryKit
import SwiftUI

struct RecoveryFactorDetailView: View {
    let factor: RecoveryFactor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoctisSpacing.xxl) {
                VStack(spacing: NoctisSpacing.xs) {
                    Image(systemName: factor.kind.systemImage)
                        .font(.system(size: 28))
                        .foregroundStyle(factor.kind.tint)
                    NoctisText("\(factor.score)", style: .heroNumber)
                    NoctisText(factor.kind.displayName, style: .eyebrow, color: NoctisColor.textTertiary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: NoctisSpacing.sm) {
                    if let current = factor.currentValue {
                        detailRow("Current", value: format(current))
                    }
                    if let baseline = factor.baselineValue {
                        detailRow("Your Baseline", value: format(baseline))
                    }
                    detailRow("Confidence", value: factor.confidence.displayName)
                }

                VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                    NoctisText("Explanation", style: .eyebrow, color: NoctisColor.textTertiary)
                    NoctisText(explanation, style: .body, color: NoctisColor.textSecondary)
                }
            }
            .padding(NoctisSpacing.xl)
        }
        .background(NoctisColor.canvas)
        .navigationTitle(factor.kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            NoctisText(label, style: .body, color: NoctisColor.textSecondary)
            Spacer()
            NoctisText(value, style: .bodyEmphasized)
        }
    }

    private func format(_ value: Double) -> String {
        let unit = factor.unit
        if unit == "score" { return "\(Int(value.rounded()))" }
        return "\(String(format: "%.0f", value)) \(unit)"
    }

    private var explanation: String {
        switch factor.kind {
        case .sleep:
            "Based on your available sleep duration, timing, continuity and stage balance from last night."
        case .hrv:
            "Your heart rate variability compared with your own recent baseline — higher relative to baseline generally reflects better recovery."
        case .restingHeartRate:
            "Your resting heart rate compared with your own recent baseline — lower relative to baseline generally reflects better recovery."
        case .consistency:
            "How steady your bedtime has been over your recent history."
        case .load:
            "Recent activity load factored against your recovery capacity."
        }
    }
}
