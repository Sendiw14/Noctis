import SwiftUI

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
