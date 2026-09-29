import SwiftUI

/// A tab's own color (Sleep sage, Recovery lavender, Insights butter): its
/// field, and its ink for the tab bar's selected glyph.
public nonisolated enum NoctisSection: Sendable, CaseIterable {
    case sleep
    case recovery
    case insights

    /// The field's fill.
    public var fill: Color {
        switch self {
        case .sleep: NoctisAppColor.blockSage
        case .recovery: NoctisAppColor.blockLavender
        case .insights: NoctisAppColor.blockButter
        }
    }

    /// The selected tab glyph's ink: 3:1 on the paper and the tab bar.
    public var ink: Color {
        switch self {
        case .sleep: NoctisAppColor.sectionSage
        case .recovery: NoctisAppColor.sectionLavender
        case .insights: NoctisAppColor.sectionButter
        }
    }

    public func fillHex(_ palette: NoctisAppPalette) -> String {
        switch self {
        case .sleep: palette.blockSage
        case .recovery: palette.blockLavender
        case .insights: palette.blockButter
        }
    }

    /// Whether the field may run under the status bar: the system's
    /// status-bar text (black in Light, white in Dark) has to clear 3:1
    /// over it. Otherwise the field starts below the safe area.
    public func extendsUnderStatusBar(dark: Bool) -> Bool {
        let palette: NoctisAppPalette = dark ? .dark : .light
        let text = dark ? "FFFFFF" : "000000"
        return noctisContrastRatio(noctisHexColor(fillHex(palette)), noctisHexColor(text)) >= 3
    }
}

/// Ink on a section's field: block ink, and block ink at 90% in Light for
/// the quieter lines. In Dark the lavender field leaves no room to dim
/// (block ink is only 4.67:1 on it), so the quieter lines are full ink there,
/// and read quieter by their size and weight. Full ink with Increase Contrast.
public struct NoctisFieldInkStyle: ShapeStyle {
    public enum Level: Sendable {
        case primary
        case secondary
    }

    /// The quieter lines' opacity: 4.5:1 on every field in that mode.
    public static func secondaryOpacity(dark: Bool) -> Double { dark ? 1 : 0.9 }
    public let level: Level

    public init(_ level: Level) {
        self.level = level
    }

    public func resolve(in environment: EnvironmentValues) -> Color {
        switch level {
        case .primary: NoctisAppColor.blockInk
        case .secondary:
            NoctisAppColor.blockInk.opacity(environment.colorSchemeContrast == .increased ? 1 : Self.secondaryOpacity(dark: environment.colorScheme == .dark))
        }
    }
}

extension ShapeStyle where Self == NoctisFieldInkStyle {
    /// Block ink, for text on a section field.
    public static var noctisFieldInk: NoctisFieldInkStyle { NoctisFieldInkStyle(.primary) }
    /// The quieter ink on a field (see `NoctisFieldInkStyle`).
    public static var noctisFieldInk2: NoctisFieldInkStyle { NoctisFieldInkStyle(.secondary) }
}

/// A full-width solid color field behind a tab's date, title, segmented
/// control and hero numbers. It runs under the status bar (where the
/// status-bar text stays legible), has 28pt bottom corners and scrolls
/// away with the content. Motifs are flat and static, and hide at
/// accessibility sizes and with Increase Contrast. The first card under it
/// overlaps its bottom edge by `overlap` (the caller pulls it up).
public struct NoctisSectionField<Content: View, Motif: View>: View {
    /// How far the first card under the field rides up over it.
    public static var overlap: CGFloat { 24 }
    /// Drawn above the safe area, so pulling the page down keeps the color.
    static var statusExtension: CGFloat { 200 }

    private let section: NoctisSection
    private let bottomInset: CGFloat
    private let content: Content
    private let motif: Motif
    @Binding private var height: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast

    /// `bottomInset` is the room under the content, inside the field, and
    /// includes the overlap. `height` reports the field's own height.
    public init(
        _ section: NoctisSection,
        bottomInset: CGFloat = 16 + NoctisSectionField.overlap,
        height: Binding<CGFloat> = .constant(0),
        @ViewBuilder content: () -> Content,
        @ViewBuilder motif: () -> Motif
    ) {
        self.section = section
        self.bottomInset = bottomInset
        self._height = height
        self.content = content()
        self.motif = motif()
    }

    private var extensionHeight: CGFloat {
        section.extendsUnderStatusBar(dark: colorScheme == .dark) ? Self.statusExtension : 0
    }

    private var showsMotif: Bool {
        !typeSize.isAccessibilitySize && contrast != .increased
    }

    public var body: some View {
        content
            .frame(maxWidth: 680)
            .padding(.horizontal, NoctisSpacing.lg)
            .padding(.top, NoctisSpacing.xs)
            .padding(.bottom, bottomInset)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .background(alignment: .top) {
                let inset = extensionHeight
                // The motif is an overlay, so it never sizes the field.
                section.fill
                    .overlay {
                        if showsMotif {
                            motif
                                .padding(.top, inset)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: NoctisRadius.lg, bottomTrailingRadius: NoctisRadius.lg, style: .continuous))
                    .padding(.top, -inset)
            }
    }
}

extension NoctisSectionField where Motif == EmptyView {
    public init(
        _ section: NoctisSection,
        bottomInset: CGFloat = 16 + NoctisSectionField.overlap,
        height: Binding<CGFloat> = .constant(0),
        @ViewBuilder content: () -> Content
    ) {
        self.init(section, bottomInset: bottomInset, height: height, content: content, motif: { EmptyView() })
    }
}

// MARK: - Motifs

/// Sleep's: flat hills along the bottom of the field in a second, deeper
/// sage tone, and one small paper moon. Static, and kept clear of text
/// (the field reserves the strip).
public struct NoctisHillsMotif: View {
    /// The strip the hills need under the content, above the overlap.
    public static let height: CGFloat = 52
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    private var hillTone: Color {
        colorScheme == .dark ? NoctisAppColor.blockInk.opacity(0.16) : NoctisAppColor.sectionSage.opacity(0.55)
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            NoctisHillsShape()
                .fill(hillTone)
                .frame(height: Self.height)
            // The moon sits in the sky over the dip between the hills, inside
            // the strip (clear of the text above it).
            Circle()
                .fill(NoctisAppColor.nightInk.opacity(0.85))
                .frame(width: 14, height: 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 132)
                .padding(.bottom, 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

/// Two soft hills in one silhouette.
public nonisolated struct NoctisHillsShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.55))
        path.addCurve(
            to: CGPoint(x: rect.minX + w * 0.34, y: rect.minY + h * 0.30),
            control1: CGPoint(x: rect.minX + w * 0.10, y: rect.minY + h * 0.30),
            control2: CGPoint(x: rect.minX + w * 0.22, y: rect.minY + h * 0.18)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + w * 0.62, y: rect.minY + h * 0.62),
            control1: CGPoint(x: rect.minX + w * 0.46, y: rect.minY + h * 0.42),
            control2: CGPoint(x: rect.minX + w * 0.52, y: rect.minY + h * 0.62)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.38),
            control1: CGPoint(x: rect.minX + w * 0.74, y: rect.minY + h * 0.62),
            control2: CGPoint(x: rect.minX + w * 0.86, y: rect.minY + h * 0.14)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Recovery's: two concentric arcs cropped by the field's top-right corner.
public struct NoctisArcsMotif: View {
    public init() {}

    public var body: some View {
        ZStack {
            Circle()
                .strokeBorder(NoctisAppColor.blockInk.opacity(0.12), lineWidth: 8)
                .frame(width: 200, height: 200)
            Circle()
                .strokeBorder(NoctisAppColor.blockInk.opacity(0.08), lineWidth: 8)
                .frame(width: 292, height: 292)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .offset(x: 120, y: -110)
    }
}

// MARK: - The status bar over a field

/// The status-bar scrim for a screen with a section field. At rest there is
/// none: the field runs under the status bar. Once the page scrolls, the
/// field's own color covers content passing under it (so a control never
/// slides beneath the clock), and as the field leaves the paper scrim comes
/// in, so nothing renders behind the status bar (R14). A field that starts
/// below the safe area (Dark, where white status-bar text over it fails
/// 3:1) keeps the paper scrim throughout.
struct NoctisSectionStatusBar: ViewModifier {
    let section: NoctisSection
    let fieldHeight: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase = Phase(lift: 0, paper: 0)

    struct Phase: Equatable {
        /// 0...1 over the first points of scroll: the field's scrim.
        var lift: Double
        /// 0...1 as the field's bottom edge nears the safe area: the paper's.
        var paper: Double
    }

    /// The field's scrim is fully in after this much scroll.
    static let liftDistance: CGFloat = 24
    /// The paper scrim fades in over this much scroll, ending when the
    /// field's bottom edge reaches the safe area.
    static let fadeDistance: CGFloat = 80

    func body(content: Content) -> some View {
        let extends = section.extendsUnderStatusBar(dark: colorScheme == .dark)
        let fieldEnd = Double(fieldHeight)
        content
            .onScrollGeometryChange(for: Phase.self) { geometry in
                let offset = Double(geometry.contentOffset.y + geometry.contentInsets.top)
                func step(_ value: Double) -> Double { (min(max(value, 0), 1) * 20).rounded() / 20 }
                // Quantized: a scroll writes state only when a value changes.
                return Phase(
                    lift: step(offset / Double(Self.liftDistance)),
                    paper: step((offset - (fieldEnd - Double(Self.fadeDistance))) / Double(Self.fadeDistance))
                )
            } action: { _, new in
                phase = new
            }
            .scrollEdgeEffectHidden(true, for: .top)
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    if extends {
                        // Under the paper scrim, which fades in on top of it:
                        // together they stay opaque, so nothing shows through.
                        // Once the paper is fully in, this goes, so its fade
                        // leaves no tinted line below the status bar.
                        NoctisStatusBarScrim(fill: section.fill)
                            .opacity(phase.paper >= 1 ? 0 : phase.lift)
                    }
                    NoctisStatusBarScrim()
                        .opacity(extends ? phase.paper : 1)
                }
            }
    }
}

extension View {
    /// Nothing renders behind the status bar (R14), on a screen whose first
    /// element is a section field of `fieldHeight`.
    public func noctisSectionStatusBar(_ section: NoctisSection, fieldHeight: CGFloat) -> some View {
        modifier(NoctisSectionStatusBar(section: section, fieldHeight: fieldHeight))
    }
}

// MARK: - The ring on a field

private nonisolated struct NoctisRingTrackKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    /// A ring's unfilled track, where the paper's track color won't do (a
    /// ring on a section field).
    public nonisolated var noctisRingTrack: Color? {
        get { self[NoctisRingTrackKey.self] }
        set { self[NoctisRingTrackKey.self] = newValue }
    }
}
