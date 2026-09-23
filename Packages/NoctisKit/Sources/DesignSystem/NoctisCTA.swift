import SwiftUI

/// R10's primary action: a 58pt cocoa capsule with an ivory label and a
/// trailing arrow. Press scales to .97 and springs back; loading morphs
/// the label into a spinning ring; disabled (via the standard `.disabled`
/// modifier) swaps to a track fill with an ink3 label.
public struct NoctisCTA: View {
    private let title: String
    private let isLoading: Bool
    private let icon: String
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `icon` defaults to R10's standard trailing `arrow.right`; a screen
    /// may override it for a CTA whose action isn't "go forward" — e.g.
    /// Paywall's error-state "Try again", which reads as a retry
    /// (`arrow.clockwise`), not forward progress.
    public init(_ title: String, isLoading: Bool = false, icon: String = "arrow.right", action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Capsule(style: .continuous)
                    .fill(isEnabled ? NoctisPaper.cocoa : NoctisPaper.track)

                if isLoading {
                    NoctisCTASpinner(tint: NoctisPaper.bg, reduceMotion: reduceMotion)
                } else {
                    HStack(spacing: 6) {
                        Text(title)
                            .noctisFont(17, .semibold, relativeTo: .body)
                            .multilineTextAlignment(.center)
                        Image(systemName: icon)
                            .noctisIcon(15)
                    }
                    .foregroundStyle(isEnabled ? NoctisPaper.bg : NoctisPaper.ink3)
                    // R4: 58pt at the default size; taller when the label
                    // grows or wraps, never clipped.
                    .padding(.vertical, NoctisSpacing.sm)
                    .padding(.horizontal, NoctisSpacing.lg)
                }
            }
            .frame(minHeight: 58)
            .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(NoctisCTAButtonStyle(reduceMotion: reduceMotion))
        .disabled(isLoading)
        .accessibilityLabel(title)
    }
}

private struct NoctisCTAButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(NoctisMotion.adaptive(NoctisMotion.snap, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

private struct NoctisCTASpinner: View {
    let tint: Color
    let reduceMotion: Bool
    @State private var angle: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0.08, to: 0.92)
            .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 20, height: 20)
            .rotationEffect(.degrees(angle))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}

/// R10's secondary action: a 44pt plain text button in `ink2`.
public struct NoctisTextButton: View {
    private let title: String
    private let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .noctisFont(15, .medium, relativeTo: .subheadline)
                .foregroundStyle(NoctisPaper.ink2)
                .multilineTextAlignment(.center)
                .frame(minWidth: 44, minHeight: 44)
                // `.plain` hit-tests only drawn pixels without this — the
                // 44pt frame was layout only, leaving an 18pt-tall target.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
