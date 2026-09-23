import SwiftUI

/// A compact, presentational contributor/factor row: an icon inside a
/// small progress ring — a list-scale echo of `NoctisScoreOrb`'s ring — a
/// title/subtitle pair, and a trailing value. Callers map their own domain
/// concept (a recovery factor, say) onto these primitives so this module
/// stays free of domain dependencies.
public struct NoctisFactorRow: View {
    private let systemImage: String
    private let tint: Color
    private let title: String
    private let subtitle: String
    private let valueText: String
    private let progress: Double

    public init(systemImage: String, tint: Color, title: String, subtitle: String, valueText: String, progress: Double) {
        self.systemImage = systemImage
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.valueText = valueText
        self.progress = progress
    }

    public var body: some View {
        HStack(spacing: NoctisSpacing.md) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.2), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0, min(progress, 1)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                NoctisText(title, style: .bodyEmphasized, color: NoctisColor.textPrimary)
                NoctisText(subtitle, style: .caption, color: NoctisColor.textTertiary)
            }

            Spacer()

            NoctisText(valueText, style: .bodyEmphasized)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NoctisColor.textTertiary)
        }
        .padding(.vertical, NoctisSpacing.sm)
        .accessibilityElement(children: .combine)
    }
}
