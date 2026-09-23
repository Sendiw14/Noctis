import SwiftUI

public struct NoctisPremiumBadge: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkle")
            Text("PREMIUM")
        }
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .tracking(0.6)
        .foregroundStyle(NoctisColor.textOnAccent)
        .padding(.horizontal, NoctisSpacing.sm)
        .padding(.vertical, 4)
        .background(Capsule().fill(NoctisColor.accentPrimary))
        .accessibilityLabel("Premium feature")
    }
}

/// Presentational only — callers map their own confidence/provenance concept
/// to a label and tint so this module stays free of domain dependencies.
public struct NoctisConfidenceBadge: View {
    private let label: String
    private let tint: Color

    public init(label: String, tint: Color = NoctisColor.textTertiary) {
        self.label = label
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 6, height: 6)
            NoctisText(label, style: .caption, color: NoctisColor.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }
}
