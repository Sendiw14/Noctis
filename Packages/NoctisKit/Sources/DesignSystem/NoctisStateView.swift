import SwiftUI

public struct NoctisStateAction {
    public let title: String
    public let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
}

/// Backs every non-happy-path moment in NOCTIS — no data yet, partial data,
/// a stale read, a permission gap, or an outright error. One shape, one voice.
public struct NoctisStateView: View {
    public let systemImage: String
    public let title: String
    public let message: String
    public let primaryAction: NoctisStateAction?
    public let secondaryAction: NoctisStateAction?

    public init(
        systemImage: String,
        title: String,
        message: String,
        primaryAction: NoctisStateAction? = nil,
        secondaryAction: NoctisStateAction? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
    }

    public var body: some View {
        VStack(spacing: NoctisSpacing.lg) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(NoctisColor.textTertiary)
                .accessibilityHidden(true)

            VStack(spacing: NoctisSpacing.xs) {
                NoctisText(title, style: .headline)
                    .multilineTextAlignment(.center)
                NoctisText(message, style: .subheadline, color: NoctisColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let primaryAction {
                Button(primaryAction.title, action: primaryAction.action)
                    .buttonStyle(.noctisPrimary)
                    .frame(maxWidth: 260)
            }
            if let secondaryAction {
                Button(secondaryAction.title, action: secondaryAction.action)
                    .buttonStyle(.noctisPress)
                    .noctisText(.caption, color: NoctisColor.textSecondary)
            }
        }
        .padding(NoctisSpacing.xxl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

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

public struct NoctisStaleBanner: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(spacing: NoctisSpacing.xxs) {
            Image(systemName: "clock.arrow.circlepath")
            NoctisText(text, style: .caption, color: NoctisColor.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }
}
