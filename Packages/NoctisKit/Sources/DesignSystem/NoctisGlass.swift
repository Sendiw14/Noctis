import SwiftUI

/// S5/R8: Liquid Glass on iOS 26 for small controls only (chips, page
/// dots, pills, the back button) — never on hero content — with a
/// material-and-stroke fallback below it.
extension View {
    @ViewBuilder
    public func noctisGlass(tint: Color, in shape: some Shape = Capsule(style: .continuous), interactive: Bool = true) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.tint(tint.opacity(0.18)).interactive(interactive), in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.25), lineWidth: 0.5))
        }
    }

    /// Marks a view as part of a morphing glass group (e.g. a page dot
    /// becoming the selected one) — a no-op before iOS 26.
    @ViewBuilder
    public func noctisGlassID<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}

/// Wraps `GlassEffectContainer` on iOS 26 (so glass elements inside can
/// morph into and out of each other) and is a plain pass-through below
/// it, where there's no such container to opt into.
public struct NoctisGlassGroup<Content: View>: View {
    private let spacing: CGFloat?
    private let content: Content

    public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
