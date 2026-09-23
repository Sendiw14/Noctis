import SwiftUI

/// A single gradient-filled capsule track, not a segmented line or a
/// repeated ring motif — progress grows continuously, and the fill color
/// can carry meaning (a caller's own accent) rather than staying neutral.
public struct NoctisJourneyProgress: View {
    public let phaseIndex: Int
    public let phaseCount: Int
    public let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(phaseIndex: Int, phaseCount: Int, tint: Color = NoctisColor.textPrimary) {
        self.phaseIndex = phaseIndex
        self.phaseCount = phaseCount
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(NoctisColor.divider.opacity(0.5))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.6), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(geometry.size.width * progress, 4))
            }
        }
        .frame(height: 4)
        .animation(NoctisMotion.adaptive(.easeInOut(duration: 0.3), reduceMotion: reduceMotion), value: phaseIndex)
        .animation(NoctisMotion.adaptive(.easeInOut(duration: 0.3), reduceMotion: reduceMotion), value: tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(phaseIndex + 1) of \(phaseCount)")
    }

    private var progress: CGFloat {
        phaseCount <= 1 ? 1 : CGFloat(phaseIndex + 1) / CGFloat(phaseCount)
    }
}
