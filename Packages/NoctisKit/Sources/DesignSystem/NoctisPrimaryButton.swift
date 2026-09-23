import SwiftUI

/// The onboarding flow's primary action. Distinct from the app's existing
/// `NoctisPrimaryButtonStyle` (left untouched, still used throughout the
/// rest of the product) — this is a full `View`, not a `ButtonStyle`,
/// because the sheen sweep and loading morph need their own state, which a
/// `ButtonStyle` can't hold across reuses cleanly. Solid fill only: glass
/// belongs on small controls (`NoctisGlassCircleButton`), never on hero
/// content like this.
public struct NoctisPrimaryButton: View {
    private let title: String
    private let isLoading: Bool
    private let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var pressed = false
    @State private var sheenOffset: CGFloat = -0.5
    @State private var hasSweptSheen = false
    @State private var spinAngle: Double = 0

    public init(_ title: String, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Capsule(style: .continuous).fill(NoctisColor.textPrimary)
                sheen
                content
            }
            .frame(height: 56)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isLoading || !isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .scaleEffect(pressed ? 0.97 : 1)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .animation(NoctisMotion.adaptive(NoctisMotion.snap, reduceMotion: reduceMotion), value: pressed)
        .animation(NoctisMotion.adaptive(.easeInOut(duration: 0.25), reduceMotion: reduceMotion), value: isLoading)
        .onAppear { sweepSheenOnce() }
        .onChange(of: isLoading) { _, newValue in
            guard newValue, !reduceMotion else { return }
            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                spinAngle = 360
            }
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isLoading ? [] : [.isButton])
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(NoctisColor.textOnAccent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 20, height: 20)
                .rotationEffect(.degrees(spinAngle))
                .transition(.opacity.combined(with: .scale(scale: 0.7)))
        } else {
            NoctisText(title, style: .bodyEmphasized, color: NoctisColor.textOnAccent)
                .transition(.opacity)
        }
    }

    /// A single diagonal highlight sweeping through once on first
    /// appearance — not a repeating shimmer.
    private var sheen: some View {
        GeometryReader { geometry in
            LinearGradient(colors: [.clear, NoctisColor.textOnAccent.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
                .frame(width: geometry.size.width * 0.4)
                .rotationEffect(.degrees(20))
                .offset(x: geometry.size.width * sheenOffset)
        }
        .clipShape(Capsule(style: .continuous))
        .allowsHitTesting(false)
    }

    private func sweepSheenOnce() {
        guard !hasSweptSheen else { return }
        hasSweptSheen = true
        guard !reduceMotion else { return }
        withAnimation(NoctisMotion.drawIn.delay(0.15)) {
            sheenOffset = 1.5
        }
    }
}

/// A small circular control using Liquid Glass on iOS 26 and a material
/// fallback below it — for chrome (back button) only, never for primary
/// actions or hero content.
public struct NoctisGlassCircleButton: View {
    private let systemImage: String
    private let accessibilityLabel: String
    private let action: () -> Void

    public init(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NoctisColor.textSecondary)
                .frame(width: 44, height: 44)
                .background(background)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var background: some View {
        if #available(iOS 26, *) {
            Color.clear.glassEffect(.regular.interactive(), in: .circle)
        } else {
            Circle().fill(.ultraThinMaterial)
        }
    }
}
