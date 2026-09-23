import SwiftUI

/// R7's top-bar progress: 6 segments, 4pt tall with 4pt gaps, track-colored
/// with a cocoa fill wiping in over 0.4s as `step` advances.
public struct NoctisSegmentedProgress: View {
    private let step: Int
    private let totalSteps: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(step: Int, totalSteps: Int = 6) {
        self.step = step
        self.totalSteps = totalSteps
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(NoctisPaper.track)
                    .overlay(alignment: .leading) {
                        GeometryReader { geometry in
                            Capsule(style: .continuous)
                                .fill(NoctisPaper.cocoa)
                                .frame(width: geometry.size.width * fillFraction(for: index))
                        }
                    }
                    .frame(height: 4)
                    .clipShape(Capsule(style: .continuous))
            }
        }
        .animation(NoctisMotion.adaptive(.easeOut(duration: 0.4), reduceMotion: reduceMotion), value: step)
        // A 44pt-tall element (the bar stays 4pt, centered) so VoiceOver
        // touch exploration can land on it.
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(min(step + 1, totalSteps)) of \(totalSteps)")
    }

    private func fillFraction(for index: Int) -> CGFloat {
        if index < step { return 1 }
        if index == step { return 1 }
        return 0
    }
}
