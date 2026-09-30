import SwiftUI

private nonisolated struct NoctisEveningPaperKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Set where text sits on Home's evening paper, so tertiary ink uses
    /// `eveningInk3` and keeps 4.5:1. Nonisolated: shape styles resolve
    /// off the main actor.
    public nonisolated var noctisEveningPaper: Bool {
        get { self[NoctisEveningPaperKey.self] }
        set { self[NoctisEveningPaperKey.self] = newValue }
    }
}

/// Ink that follows Increase Contrast: secondary and tertiary text move
/// up one level (ink3 → ink2, ink2 → ink) when it's on. On the evening
/// paper, tertiary ink is `eveningInk3`.
public struct NoctisInkStyle: ShapeStyle {
    public enum Level: Sendable {
        case primary
        case secondary
        case tertiary
    }

    public let level: Level

    public init(_ level: Level) {
        self.level = level
    }

    public func resolve(in environment: EnvironmentValues) -> Color {
        // Text inside a section field wears the field's cocoa inks.
        if environment.noctisFieldSection != nil {
            return switch level {
            case .primary: NoctisFieldInkStyle(.primary).resolve(in: environment)
            case .secondary: NoctisFieldInkStyle(.secondary).resolve(in: environment)
            case .tertiary: NoctisFieldInkStyle(.caption).resolve(in: environment)
            }
        }
        let raised = environment.colorSchemeContrast == .increased
        return switch (level, raised) {
        case (.primary, _), (.secondary, true): NoctisAppColor.ink
        case (.secondary, false), (.tertiary, true): NoctisAppColor.ink2
        case (.tertiary, false): environment.noctisEveningPaper ? NoctisAppColor.eveningInk3 : NoctisAppColor.ink3
        }
    }
}

extension ShapeStyle where Self == NoctisInkStyle {
    /// ink2, or ink with Increase Contrast.
    public static var noctisInk2: NoctisInkStyle { NoctisInkStyle(.secondary) }
    /// ink3, or ink2 with Increase Contrast.
    public static var noctisInk3: NoctisInkStyle { NoctisInkStyle(.tertiary) }
}

/// Secondary text on the night panel: night ink at 70%, 90% with
/// Increase Contrast.
public struct NoctisNightInkStyle: ShapeStyle {
    public init() {}

    public func resolve(in environment: EnvironmentValues) -> Color {
        NoctisAppColor.nightInk.opacity(environment.colorSchemeContrast == .increased ? 0.9 : 0.7)
    }
}

extension ShapeStyle where Self == NoctisNightInkStyle {
    public static var noctisNightInk2: NoctisNightInkStyle { NoctisNightInkStyle() }
}

/// Increase Contrast gives cards and blocks a 1.5pt ink border.
struct NoctisContrastBorder: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(NoctisAppColor.ink, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    /// A 1.5pt ink border with Increase Contrast (cards, blocks, panels).
    public func noctisContrastBorder(cornerRadius: CGFloat = NoctisRadius.lg) -> some View {
        modifier(NoctisContrastBorder(cornerRadius: cornerRadius))
    }
}

/// A list of numbers SwiftUI can interpolate: the ring's per-segment
/// fills, so a live update moves only the segments that changed. Lists of
/// different lengths pad with zeros.
public struct NoctisAnimatableVector: VectorArithmetic, Sendable {
    public var values: [Double]

    public init(_ values: [Double]) {
        self.values = values
    }

    public static var zero: NoctisAnimatableVector { NoctisAnimatableVector([]) }

    public static func + (lhs: NoctisAnimatableVector, rhs: NoctisAnimatableVector) -> NoctisAnimatableVector {
        combine(lhs, rhs, +)
    }

    public static func - (lhs: NoctisAnimatableVector, rhs: NoctisAnimatableVector) -> NoctisAnimatableVector {
        combine(lhs, rhs, -)
    }

    public mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    public var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }

    private static func combine(_ lhs: NoctisAnimatableVector, _ rhs: NoctisAnimatableVector, _ operation: (Double, Double) -> Double) -> NoctisAnimatableVector {
        let count = max(lhs.values.count, rhs.values.count)
        return NoctisAnimatableVector((0..<count).map { index in
            operation(index < lhs.values.count ? lhs.values[index] : 0, index < rhs.values.count ? rhs.values[index] : 0)
        })
    }
}
