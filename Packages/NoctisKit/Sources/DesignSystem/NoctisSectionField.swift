import SwiftUI

/// A tab's own color: its field, its motif and its ink for the tab bar's
/// selected glyph. Every field carries cocoa ink.
public nonisolated enum NoctisSection: Sendable, CaseIterable {
    case home
    case sleep
    case recovery
    case insights
    case coach
    /// Not a tab: the Profile page pushed from Home's avatar.
    case profile

    /// The field's fill.
    public var fill: Color {
        switch self {
        case .home: NoctisAppColor.fieldApricot
        case .sleep: NoctisAppColor.blockSage
        case .recovery: NoctisAppColor.blockLavender
        case .insights: NoctisAppColor.blockButter
        case .coach: NoctisAppColor.fieldRose
        case .profile: NoctisAppColor.fieldSand
        }
    }

    /// The selected tab glyph's ink: 3:1 on the paper and the tab bar.
    public var ink: Color {
        switch self {
        case .home: NoctisAppColor.sectionApricot
        case .sleep: NoctisAppColor.sectionSage
        case .recovery: NoctisAppColor.sectionLavender
        case .insights: NoctisAppColor.sectionButter
        case .coach: NoctisAppColor.sectionRose
        case .profile: NoctisAppColor.sectionSand
        }
    }

    public func fillHex(_ palette: NoctisAppPalette) -> String {
        switch self {
        case .home: palette.fieldApricot
        case .sleep: palette.blockSage
        case .recovery: palette.blockLavender
        case .insights: palette.blockButter
        case .coach: palette.fieldRose
        case .profile: palette.fieldSand
        }
    }

    public func inkHex(_ palette: NoctisAppPalette) -> String {
        switch self {
        case .home: palette.sectionApricot
        case .sleep: palette.sectionSage
        case .recovery: palette.sectionLavender
        case .insights: palette.sectionButter
        case .coach: palette.sectionRose
        case .profile: palette.sectionSand
        }
    }

    /// The tab's glyph.
    public var systemImage: String {
        switch self {
        case .home: "house"
        case .sleep: "moon.zzz"
        case .recovery: "heart"
        case .insights: "lightbulb"
        case .coach: "sparkles"
        case .profile: "person"
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

    /// The opacity of cocoa ink for a quieter line on this field: `target`
    /// (the caption's .7, the summary's .8), raised in steps of .05 until
    /// the text reads at 4.5:1 on the field in that mode.
    public func quietOpacity(target: Double, dark: Bool) -> Double {
        let palette: NoctisAppPalette = dark ? .dark : .light
        let fill = fillHex(palette)
        var opacity = target
        while opacity < 1 {
            let mixed = noctisBlendHex(palette.blockInk, over: fill, alpha: opacity)
            if noctisContrastRatio(noctisHexColor(mixed), noctisHexColor(fill)) >= 4.5 { return opacity }
            opacity += 0.05
        }
        return 1
    }
}

/// `foreground` over `background` at `alpha`, as a hex string.
public nonisolated func noctisBlendHex(_ foreground: String, over background: String, alpha: Double) -> String {
    let f = noctisHexComponents(foreground), b = noctisHexComponents(background)
    func mix(_ x: Double, _ y: Double) -> Int { Int(((alpha * x + (1 - alpha) * y) * 255).rounded()) }
    return String(format: "%02X%02X%02X", mix(f.0, b.0), mix(f.1, b.1), mix(f.2, b.2))
}

private nonisolated struct NoctisFieldSectionKey: EnvironmentKey {
    static let defaultValue: NoctisSection? = nil
}

extension EnvironmentValues {
    /// Set on a section field's content: text styles inside it use the
    /// field's cocoa ink (`.noctisInk2` and `.noctisInk3` become the
    /// summary's .8 and the caption's .7, raised where a field needs it).
    public nonisolated var noctisFieldSection: NoctisSection? {
        get { self[NoctisFieldSectionKey.self] }
        set { self[NoctisFieldSectionKey.self] = newValue }
    }
}

/// Cocoa ink on a section's field: full for titles and numbers, the
/// summary's .8 and the caption's .7 for quieter lines (each raised, where
/// a field needs it, to 4.5:1); full ink with Increase Contrast.
public struct NoctisFieldInkStyle: ShapeStyle {
    public enum Level: Sendable {
        case primary
        /// The summary line: .8.
        case secondary
        /// The date caption: .7.
        case caption
    }

    public static let summaryOpacity = 0.8
    public static let captionOpacity = 0.7
    public let level: Level

    public init(_ level: Level) {
        self.level = level
    }

    public func resolve(in environment: EnvironmentValues) -> Color {
        let section = environment.noctisFieldSection ?? .recovery
        let dark = environment.colorScheme == .dark
        let raised = environment.colorSchemeContrast == .increased
        switch level {
        case .primary: return NoctisAppColor.blockInk
        case .secondary: return NoctisAppColor.blockInk.opacity(raised ? 1 : section.quietOpacity(target: Self.summaryOpacity, dark: dark))
        case .caption: return NoctisAppColor.blockInk.opacity(raised ? 1 : section.quietOpacity(target: Self.captionOpacity, dark: dark))
        }
    }
}

extension ShapeStyle where Self == NoctisFieldInkStyle {
    /// Block ink, for text on a section field.
    public static var noctisFieldInk: NoctisFieldInkStyle { NoctisFieldInkStyle(.primary) }
    /// The summary line's ink on a field (see `NoctisFieldInkStyle`).
    public static var noctisFieldInk2: NoctisFieldInkStyle { NoctisFieldInkStyle(.secondary) }
    /// The date caption's ink on a field.
    public static var noctisFieldCaption: NoctisFieldInkStyle { NoctisFieldInkStyle(.caption) }
}

/// How a section field arrives the first time its tab is shown in a launch.
public nonisolated enum NoctisFieldEntrance: Sendable, Equatable {
    /// Already there.
    case none
    /// The color fills outward from the segmented control with a spring:
    /// once per tab per day.
    case wash
    /// A plain fade (the wash was already spent today).
    case fade
}

/// Where the segmented control sits in a field, so the wash can start there.
private nonisolated struct NoctisWashOriginKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = value ?? nextValue()
    }
}

extension View {
    /// Marks the segmented control a section field's wash grows from.
    public func noctisWashOrigin() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: NoctisWashOriginKey.self, value: proxy.frame(in: .named(NoctisSectionFieldSpace.name)).midY)
            }
        }
    }
}

nonisolated enum NoctisSectionFieldSpace {
    static let name = "noctisSectionField"
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
    private let entrance: NoctisFieldEntrance
    private let onEntered: () -> Void
    private let maxWidth: CGFloat
    private let washes: [NoctisWash]
    @Binding private var height: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0...1: how much of the field has arrived.
    @State private var arrival: Double
    @State private var origin: CGFloat?
    @State private var measured: CGFloat = 0

    /// `bottomInset` is the room under the content, inside the field, and
    /// includes the overlap. `height` reports the field's own height.
    public init(
        _ section: NoctisSection,
        bottomInset: CGFloat = 16 + NoctisSectionField.overlap,
        height: Binding<CGFloat> = .constant(0),
        entrance: NoctisFieldEntrance = .none,
        onEntered: @escaping () -> Void = {},
        maxWidth: CGFloat = 680,
        washes: [NoctisWash] = [],
        @ViewBuilder content: () -> Content,
        @ViewBuilder motif: () -> Motif
    ) {
        self.section = section
        self.bottomInset = bottomInset
        self._height = height
        self.entrance = entrance
        self.onEntered = onEntered
        self.maxWidth = maxWidth
        self.washes = washes
        self._arrival = State(initialValue: entrance == .none ? 1 : 0)
        self.content = content()
        self.motif = motif()
    }

    private var extensionHeight: CGFloat {
        section.extendsUnderStatusBar(dark: colorScheme == .dark) ? Self.statusExtension : 0
    }

    /// In Dark some fields (the apricot, sage, butter and rose) start below
    /// the safe area, under the paper scrim's 16pt fade. Every field gets
    /// that room there, so the caption and title sit in the same place on
    /// all five tabs, whether or not a field runs under the status bar.
    private var topClearance: CGFloat {
        colorScheme == .dark ? 16 : 0
    }

    private var showsMotif: Bool {
        !typeSize.isAccessibilitySize && contrast != .increased
    }

    /// The wash grows from the control; without Reduce Motion only. Reduce
    /// Motion (and a wash already spent today) is a plain fade.
    private var growsFromControl: Bool { entrance == .wash && !reduceMotion }

    /// The wash's spring: half a second, no bounce, so a second change (a
    /// tab switch mid-wash) retargets from where it is.
    private var arrivalAnimation: Animation {
        growsFromControl ? NoctisMotion.draw(0.5) : NoctisMotion.adaptive(NoctisMotion.fade, reduceMotion: reduceMotion)
    }

    /// The mask's anchor: the control's height in the field, as a share of
    /// it (the middle until measured).
    private func anchor(inset: CGFloat) -> UnitPoint {
        guard let origin, measured > 0 else { return .center }
        return UnitPoint(x: 0.5, y: min(max((origin + inset) / (measured + inset), 0), 1))
    }

    public var body: some View {
        content
            .environment(\.noctisFieldSection, section)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .padding(.horizontal, NoctisSpacing.lg)
            .padding(.top, NoctisSpacing.xs + topClearance)
            .padding(.bottom, bottomInset)
            .frame(maxWidth: .infinity)
            // The text arrives with the color, not before it (ink on the
            // paper would vanish in Dark).
            .opacity(growsFromControl ? 0.2 + 0.8 * min(arrival * 1.6, 1) : 1)
            .coordinateSpace(name: NoctisSectionFieldSpace.name)
            .onPreferenceChange(NoctisWashOriginKey.self) { origin = $0 }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                height = $0
                measured = $0
            }
            .background(alignment: .top) {
                let inset = extensionHeight
                // The motif is an overlay, so it never sizes the field.
                section.fill
                    .overlay {
                        // The morning reveal's dusk lifts off the field too.
                        ForEach(Array(washes.enumerated()), id: \.offset) { _, wash in
                            wash.color.opacity(wash.opacity)
                        }
                    }
                    .overlay {
                        if showsMotif {
                            motif
                                .padding(.top, inset)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: NoctisRadius.lg, bottomTrailingRadius: NoctisRadius.lg, style: .continuous))
                    .modifier(FieldArrival(washes: growsFromControl, arrival: arrival, anchor: anchor(inset: inset)))
                    .padding(.top, -inset)
            }
            .onAppear {
                guard arrival < 1 else { return }
                withAnimation(arrivalAnimation) { arrival = 1 }
                onEntered()
            }
    }
}

/// The field's arrival: a mask that grows from the control (the wash), or an
/// opacity fade.
private struct FieldArrival: ViewModifier {
    let washes: Bool
    let arrival: Double
    let anchor: UnitPoint

    func body(content: Content) -> some View {
        if washes {
            content.mask {
                Rectangle().scaleEffect(x: 1, y: max(arrival, 0.001), anchor: anchor)
            }
        } else {
            content.opacity(arrival)
        }
    }
}

extension NoctisSectionField where Motif == EmptyView {
    public init(
        _ section: NoctisSection,
        bottomInset: CGFloat = 16 + NoctisSectionField.overlap,
        height: Binding<CGFloat> = .constant(0),
        entrance: NoctisFieldEntrance = .none,
        onEntered: @escaping () -> Void = {},
        maxWidth: CGFloat = 680,
        washes: [NoctisWash] = [],
        @ViewBuilder content: () -> Content
    ) {
        self.init(section, bottomInset: bottomInset, height: height, entrance: entrance, onEntered: onEntered, maxWidth: maxWidth, washes: washes, content: content, motif: { EmptyView() })
    }
}

// MARK: - Motifs

/// Which flat, static motif a section's field carries (low contrast, never
/// behind text; the field hides it at accessibility sizes and with Increase
/// Contrast).
public struct NoctisSectionMotif: View {
    private let section: NoctisSection

    public init(_ section: NoctisSection) {
        self.section = section
    }

    /// The strip a motif needs along the field's bottom edge, above the
    /// overlap; the others sit in a corner and need none.
    public static func bottomStrip(_ section: NoctisSection) -> CGFloat {
        switch section {
        case .sleep: NoctisHillsMotif.height
        case .home: NoctisHorizonMotif.height
        case .recovery, .insights, .coach, .profile: 0
        }
    }

    public var body: some View {
        switch section {
        case .home: NoctisHorizonMotif()
        case .sleep: NoctisHillsMotif()
        case .recovery: NoctisArcsMotif()
        case .insights: NoctisDotsMotif()
        case .coach: NoctisCirclesMotif()
        // A page with a gear in the corner and no motif: the sand is quiet on its own.
        case .profile: EmptyView()
        }
    }
}

/// Sleep's: flat hills along the bottom of the field in a second, deeper
/// sage tone, and a small paper crescent in the sky over them.
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
            // The crescent sits in the sky over the dip between the hills,
            // inside the strip (clear of the text above it).
            NoctisCrescentShape()
                .fill(NoctisAppColor.nightInk.opacity(0.85))
                .frame(width: 18, height: 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 132)
                .padding(.bottom, 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

/// A crescent: a disc with a second, offset disc taken out of it.
public nonisolated struct NoctisCrescentShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let disc = Path(ellipseIn: rect)
        let bite = Path(ellipseIn: rect.offsetBy(dx: rect.width * 0.32, dy: -rect.height * 0.10).insetBy(dx: rect.width * 0.02, dy: rect.height * 0.02))
        return disc.subtracting(bite)
    }
}

/// Home's: a low horizon line along the bottom of the field, and a sun
/// disc half risen over it at .35.
public struct NoctisHorizonMotif: View {
    /// The strip the horizon needs under the content, above the overlap.
    public static let height: CGFloat = 32

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            // The sun, its lower half under the line.
            Circle()
                .fill(NoctisAppColor.nightInk.opacity(0.35))
                .frame(width: 44, height: 44)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 52)
                .padding(.bottom, -22)
                .frame(height: Self.height, alignment: .bottom)
                .clipped()
            Rectangle()
                .fill(NoctisAppColor.blockInk.opacity(0.15))
                .frame(height: 1.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

/// Insights': three small dots, stacked, at the top right.
public struct NoctisDotsMotif: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(NoctisAppColor.blockInk.opacity(0.10 + 0.05 * Double(index)))
                    .frame(width: 10, height: 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.trailing, 32)
        .padding(.top, 28)
    }
}

/// Coach's: two small overlapping circles, at the top right.
public struct NoctisCirclesMotif: View {
    public init() {}

    public var body: some View {
        HStack(spacing: -14) {
            Circle().strokeBorder(NoctisAppColor.blockInk.opacity(0.14), lineWidth: 3).frame(width: 30, height: 30)
            Circle().strokeBorder(NoctisAppColor.blockInk.opacity(0.10), lineWidth: 3).frame(width: 30, height: 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.trailing, 28)
        .padding(.top, 28)
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
struct NoctisSectionScrim: View {
    let section: NoctisSection
    let phase: NoctisScrollPhase
    /// Flat colors over the paper (Home's evening paper and dusk), and over
    /// the field (the dusk).
    var paperWashes: [NoctisWash] = []
    var fieldWashes: [NoctisWash] = []
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let extends = section.extendsUnderStatusBar(dark: colorScheme == .dark)
        ZStack(alignment: .top) {
            if extends {
                // Under the paper scrim, which fades in on top of it:
                // together they stay opaque, so nothing shows through.
                // Once the paper is fully in, this goes, so its fade
                // leaves no tinted line below the status bar.
                NoctisStatusBarScrim(washes: fieldWashes, fill: section.fill)
                    .opacity(phase.paper >= 1 ? 0 : phase.lift)
            }
            NoctisStatusBarScrim(washes: paperWashes)
                .opacity(extends ? phase.paper : 1)
        }
    }
}

/// How far a tab's page has scrolled, in steps, so a scroll writes state
/// only when a value changes.
struct NoctisScrollPhase: Equatable {
    /// 0...1 over the first points of scroll: the field's scrim.
    var lift: Double = 0
    /// 0...1 as the field's bottom edge nears the safe area: the paper's.
    var paper: Double = 0

    /// The field's scrim is fully in after this much scroll.
    static let liftDistance: Double = 24
    /// The paper scrim fades in over this much scroll, ending when the
    /// field's bottom edge reaches the safe area.
    static let fadeDistance: Double = 80

    init(lift: Double = 0, paper: Double = 0) {
        self.lift = lift
        self.paper = paper
    }

    init(offset: Double, fieldHeight: Double) {
        func step(_ value: Double) -> Double { (min(max(value, 0), 1) * 20).rounded() / 20 }
        lift = step(offset / Self.liftDistance)
        paper = step((offset - (fieldHeight - Self.fadeDistance)) / Self.fadeDistance)
    }

    /// The field has left: the compact title bar takes its place.
    var fieldGone: Bool { paper >= 1 }
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

// MARK: - The usual band

/// The shaded band for "your usual" on a chart: butter at 25% in Light and
/// 18% in Dark (the track color it replaces was nearly invisible).
public struct NoctisUsualBandStyle: ShapeStyle {
    public static func opacity(dark: Bool) -> Double { dark ? 0.18 : 0.25 }

    public init() {}

    public func resolve(in environment: EnvironmentValues) -> Color {
        NoctisAppColor.butter.opacity(Self.opacity(dark: environment.colorScheme == .dark))
    }
}

extension ShapeStyle where Self == NoctisUsualBandStyle {
    public static var noctisUsualBand: NoctisUsualBandStyle { NoctisUsualBandStyle() }
}

// MARK: - Highlights

/// A small butter capsule for something true about a night, a week or a
/// day: a personal high. Block ink on the butter block; calm words.
public struct NoctisHighlightCapsule: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle")
                .font(.system(size: 12, weight: .bold))
                .accessibilityHidden(true)
            Text(text)
                .noctisFont(13, .semibold, relativeTo: .footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(NoctisAppColor.blockInk)
        .padding(.horizontal, NoctisSpacing.sm)
        .padding(.vertical, 6)
        .frame(minHeight: 28)
        .background(NoctisAppColor.blockButter, in: Capsule(style: .continuous))
        .noctisContrastBorder(cornerRadius: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityIdentifier("highlight")
    }
}
