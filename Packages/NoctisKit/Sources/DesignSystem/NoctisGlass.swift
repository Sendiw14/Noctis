import SwiftUI

/// S5/R8: Liquid Glass for small controls only (chips, page dots, pills,
/// the back button) — never on hero content.
extension View {
    public func noctisGlass(tint: Color, in shape: some Shape = Capsule(style: .continuous), interactive: Bool = true) -> some View {
        glassEffect(.regular.tint(tint.opacity(0.18)).interactive(interactive), in: shape)
    }

    /// Marks a view as part of a morphing glass group (e.g. a page dot
    /// becoming the selected one).
    public func noctisGlassID<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        glassEffectID(id, in: namespace)
    }
}

/// Wraps `GlassEffectContainer`, so glass elements inside can morph into
/// and out of each other.
public struct NoctisGlassGroup<Content: View>: View {
    private let spacing: CGFloat?
    private let content: Content

    public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        GlassEffectContainer(spacing: spacing) { content }
    }
}
