import SwiftUI

public struct NoctisScoreOrb: View {
    private let score: Int
    private let label: String
    private let tint: Color
    private let diameter: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedProgress: Double = 0

    public init(score: Int, label: String, tint: Color = NoctisColor.sage, diameter: CGFloat = 220) {
        self.score = score
        self.label = label
        self.tint = tint
        self.diameter = diameter
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(NoctisColor.surfaceSunken, lineWidth: 14)
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                NoctisText("\(score)", style: .heroNumber)
                NoctisText(label, style: .eyebrow, color: NoctisColor.textTertiary)
            }
        }
        .frame(width: diameter, height: diameter)
        .onAppear { animateIn() }
        .onChange(of: score) { animateIn() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(score) out of 100")
    }

    private func animateIn() {
        let target = Double(score) / 100
        // Reduce Motion still gets a brief fade to the resolved value — the
        // ring is conveying a real number, not decoration, so a hard jump
        // would cost comprehension for no reason. `.adaptive` drops the
        // spring's `.delay` along with the spring itself, so there's no
        // artificial wait added on top.
        withAnimation(NoctisMotion.adaptive(NoctisMotion.reveal.delay(0.1), reduceMotion: reduceMotion)) {
            animatedProgress = target
        }
    }
}
