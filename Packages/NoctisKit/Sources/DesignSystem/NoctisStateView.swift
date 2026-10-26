import SwiftUI

public struct NoctisLoadingState: View {
    private let message: String
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ message: String) {
        self.message = message
    }

    public var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            RoundedRectangle(cornerRadius: NoctisRadius.md, style: .continuous)
                .fill(NoctisColor.surfaceSunken)
                .frame(height: 120)
                .opacity(pulse ? 0.6 : 1.0)
            NoctisText(message, style: .caption, color: NoctisColor.textTertiary)
        }
        .padding(NoctisSpacing.lg)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}
