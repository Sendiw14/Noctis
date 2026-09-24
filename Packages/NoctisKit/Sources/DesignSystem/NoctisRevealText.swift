import SwiftUI

/// A marker attribute so `NoctisRevealRenderer` can recover each word's
/// index from `Text.Layout`, independent of how SwiftUI happens to group
/// runs — required because adjacent identically-styled runs can otherwise
/// merge, defeating a per-word stagger.
nonisolated private struct NoctisWordIndexAttribute: TextAttribute {
    let index: Int
}

/// Words rising into place with a blur-to-sharp resolve, staggered left to
/// right — the onboarding title treatment. Two lines only: the first in
/// `ink`, the second in the step's accent, matching the night-becomes-
/// morning brief (ink text on the morning steps, accent carrying the
/// step's color).
public struct NoctisRevealText: View {
    private let line1: String
    private let line2: String?
    private let style: NoctisTextStyle
    private let line1Color: Color
    private let accentColor: Color
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        _ line1: String,
        line2: String? = nil,
        style: NoctisTextStyle = .display,
        color: Color = NoctisColor.textPrimary,
        accent: Color = NoctisColor.textPrimary
    ) {
        self.line1 = line1
        self.line2 = line2
        self.style = style
        self.line1Color = color
        self.accentColor = accent
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // KNOWN LIMITATION: a `Text` built by concatenating several
            // separately-styled per-word runs and given `.textRenderer`
            // does not reliably wrap — confirmed empirically (frame,
            // lineLimit(nil) and dropping .tracking() each failed to fix
            // it). Every caller works around this by pre-breaking into two
            // short line1/line2 fragments that individually fit on one
            // line; a line long enough to need a real wrap will still
            // truncate.
            wordText(line1, color: line1Color, wordOffset: 0)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let line2 {
                wordText(line2, color: accentColor, wordOffset: line1.split(separator: " ").count)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .textRenderer(NoctisRevealRenderer(progress: revealed ? 1 : 0, reduceMotion: reduceMotion))
        .accessibilityElement(children: .combine)
        .accessibilityLabel([line1, line2].compactMap { $0 }.joined(separator: " "))
        .onAppear {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.6, dampingFraction: 0.86)) {
                revealed = true
            }
        }
    }

    private func wordText(_ string: String, color: Color, wordOffset: Int) -> Text {
        let words = string.split(separator: " ")
        var result = Text("")
        for (index, word) in words.enumerated() {
            let styled = Text(String(word))
                .font(.system(size: scaledSize(style, dynamicTypeSize), weight: style.weight, design: style.design))
                .tracking(style.tracking)
                .foregroundStyle(color)
                .customAttribute(NoctisWordIndexAttribute(index: wordOffset + index))
            // Interpolation, not `+` (deprecated in iOS 26); each word keeps
            // its styling and reveal-index attribute.
            result = index == 0 ? styled : Text("\(result) \(styled)")
        }
        return result
    }
}

/// Draws each word with its own offset into the shared 0...1 `progress`
/// window (70ms-equivalent stagger) — rise 14pt, blur 10pt to 0, opacity
/// 0 to 1. Reduce Motion collapses this to a plain fade via the caller
/// passing `reduceMotion` straight through rather than staggering here.
private struct NoctisRevealRenderer: TextRenderer, Animatable {
    var progress: Double
    let reduceMotion: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    nonisolated func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let runs = Array(layout.flatMap { $0 })
        guard !runs.isEmpty else { return }
        let maxIndex = runs.compactMap { $0[NoctisWordIndexAttribute.self]?.index }.max() ?? (runs.count - 1)
        let staggerWindow = 0.5

        for run in runs {
            let index = run[NoctisWordIndexAttribute.self]?.index ?? 0
            let fraction = maxIndex > 0 ? Double(index) / Double(maxIndex) : 0
            let localProgress: Double
            if reduceMotion {
                localProgress = progress
            } else {
                let start = fraction * (1 - staggerWindow)
                localProgress = min(max((progress - start) / staggerWindow, 0), 1)
            }
            var runContext = context
            runContext.opacity = localProgress
            runContext.addFilter(.blur(radius: (1 - localProgress) * 10))
            runContext.translateBy(x: 0, y: (1 - localProgress) * 14)
            runContext.draw(run)
        }
    }
}
