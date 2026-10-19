import SwiftUI

// The tab scaffold: the one screen every tab is built on, so the five tabs
// read as the same app. A section field (a flat color, under the status
// bar, 28pt bottom corners) holds the date caption, the large title, an
// optional summary, a segmented control, a hero and a trailing button; the
// first card or hero below it overlaps its bottom edge by 24pt; and the
// page's own compact title bar takes over once the field has scrolled away.

/// How a scaffold is presented.
public enum TabScreenPresentation: Sendable {
    /// A tab's root: no navigation bar, the status bar handled, a compact
    /// title bar once the field scrolls away.
    case tab
    /// Pushed in a navigation stack: the navigation bar sits over the field.
    case pushed
}

/// What goes in a tab's field.
public struct TabScreenHeader {
    /// "WEDNESDAY, SEPTEMBER 30".
    public var dateCaption: String
    /// The large title (34 bold); a `Text` so a word can be emphasized.
    public var title: Text
    /// The plain title: the compact bar's, the navigation title's.
    public var plainTitle: String
    /// A pushed screen's navigation bar carries the title.
    public var showsTitle = true
    /// One sentence (17), under the title.
    public var summary: AnyView?
    /// The segmented control; the tab-entry wash grows from it.
    public var control: AnyView?
    /// Numbers and strips that live on the field (Sleep's night and hero).
    public var hero: AnyView?
    /// A button at the title's trailing edge (Home's 36pt avatar).
    public var trailing: AnyView?

    public init(
        dateCaption: String,
        title: String,
        showsTitle: Bool = true,
        summary: AnyView? = nil,
        control: AnyView? = nil,
        hero: AnyView? = nil,
        trailing: AnyView? = nil
    ) {
        self.init(dateCaption: dateCaption, title: Text(title), plainTitle: title, showsTitle: showsTitle, summary: summary, control: control, hero: hero, trailing: trailing)
    }

    public init(
        dateCaption: String,
        title: Text,
        plainTitle: String,
        showsTitle: Bool = true,
        summary: AnyView? = nil,
        control: AnyView? = nil,
        hero: AnyView? = nil,
        trailing: AnyView? = nil
    ) {
        self.dateCaption = dateCaption
        self.title = title
        self.plainTitle = plainTitle
        self.showsTitle = showsTitle
        self.summary = summary
        self.control = control
        self.hero = hero
        self.trailing = trailing
    }
}

/// Where the content under the field starts.
public enum TabContentTop: Sendable, Equatable {
    /// A card: it rides up 24pt over the field's edge.
    case overlapsField
    /// A ring on a paper disc (`discMargin` wide): the disc rides up 24pt
    /// over the field's edge, so the ring stands on paper.
    case overlapsDisc
    /// Text or a state on the paper: this far below the field.
    case below(CGFloat)
}

/// The compact title bar's behavior.
public enum TabCompactBarMode: Sendable {
    /// The section glyph and the title, once the field has scrolled away.
    case title
    /// The screen supplies its own (through `topOverlay`).
    case custom
    case none
}

public struct TabScreenScaffold<Content: View>: View {
    /// How far the first card under the field rides up over it.
    public static var overlap: CGFloat { NoctisSectionField<EmptyView, EmptyView>.overlap }

    private let section: NoctisSection
    private let presentation: TabScreenPresentation
    private let header: TabScreenHeader
    private let entrance: NoctisFieldEntrance
    private let onEntered: () -> Void
    private let fieldMaxWidth: CGFloat
    private let contentMaxWidth: CGFloat
    private let contentTop: TabContentTop
    private let compactMode: TabCompactBarMode
    private let contentSpace: String?
    private let paperOverlay: AnyView?
    private let paperWashes: [NoctisWash]
    private let fieldWashes: [NoctisWash]
    private let topOverlay: AnyView?
    private let refresh: (() async -> Void)?
    private let onScroll: ((Double) -> Void)?
    private let onScrollPhase: ((ScrollPhase, ScrollPhase) -> Void)?
    private let configureScroll: ((AnyView) -> AnyView)?
    private let content: Content
    @Binding private var scrollPosition: ScrollPosition

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var fieldHeight: CGFloat = 0
    @State private var phase = NoctisScrollPhase()

    public init(
        _ section: NoctisSection,
        presentation: TabScreenPresentation = .tab,
        header: TabScreenHeader,
        entrance: NoctisFieldEntrance = .none,
        onEntered: @escaping () -> Void = {},
        fieldMaxWidth: CGFloat = 680,
        contentMaxWidth: CGFloat = 680,
        contentTop: TabContentTop = .overlapsField,
        compactBar: TabCompactBarMode? = nil,
        contentSpace: String? = nil,
        paperOverlay: AnyView? = nil,
        paperWashes: [NoctisWash] = [],
        fieldWashes: [NoctisWash] = [],
        topOverlay: AnyView? = nil,
        scrollPosition: Binding<ScrollPosition>,
        refresh: (() async -> Void)? = nil,
        onScroll: ((Double) -> Void)? = nil,
        onScrollPhase: ((ScrollPhase, ScrollPhase) -> Void)? = nil,
        configureScroll: ((AnyView) -> AnyView)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.section = section
        self.presentation = presentation
        self.header = header
        self.entrance = presentation == .tab ? entrance : .none
        self.onEntered = onEntered
        self.fieldMaxWidth = fieldMaxWidth
        self.contentMaxWidth = contentMaxWidth
        self.contentTop = contentTop
        self.compactMode = compactBar ?? (presentation == .tab ? .title : .none)
        self.contentSpace = contentSpace
        self.paperOverlay = paperOverlay
        self.paperWashes = paperWashes
        self.fieldWashes = fieldWashes
        self.topOverlay = topOverlay
        self._scrollPosition = scrollPosition
        self.refresh = refresh
        self.onScroll = onScroll
        self.onScrollPhase = onScrollPhase
        self.configureScroll = configureScroll
        self.content = content()
    }

    private var strip: CGFloat { NoctisSectionMotif.bottomStrip(section) }

    /// The room under the field's content: the motif's strip, and the
    /// overlap the card above takes.
    private var bottomInset: CGFloat {
        switch contentTop {
        case .overlapsField, .overlapsDisc: max(strip + NoctisSpacing.lg, NoctisSpacing.md + Self.overlap)
        case .below: strip + NoctisSpacing.lg
        }
    }

    /// The paper disc a ring sits on reaches this far past the ring.
    public static var discMargin: CGFloat { 8 }

    private var contentTopPadding: CGFloat {
        switch contentTop {
        case .overlapsField: -Self.overlap
        case .overlapsDisc: -(Self.overlap - Self.discMargin)
        case .below(let gap): gap
        }
    }

    public var body: some View {
        scaffold
            .background {
                PaperBackground(adaptive: true)
                    .overlay { paperOverlay }
                    .ignoresSafeArea()
            }
            .modifier(TabScreenNavigation(presentation: presentation, title: header.plainTitle))
    }

    private var scaffold: some View {
        let scroll = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                field
                content
                    .frame(maxWidth: contentMaxWidth)
                    .padding(.horizontal, NoctisSpacing.lg)
                    .padding(.top, contentTopPadding)
                    .padding(.bottom, NoctisSpacing.xl)
                    .frame(maxWidth: .infinity)
            }
            .modifier(TabContentSpace(name: contentSpace))
        }
        return chrome(scroll)
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    if compactMode == .title, phase.fieldGone {
                        TabCompactBar(label: header.plainTitle, identifier: "tab.compactBar", action: scrollToTop) {
                            Image(systemName: section.systemImage)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(section.ink)
                                .accessibilityHidden(true)
                            Text(header.plainTitle)
                                .noctisFont(17, .semibold, relativeTo: .body)
                                .foregroundStyle(NoctisAppColor.ink)
                        }
                        .transition(.opacity)
                    }
                    topOverlay
                }
                .animation(NoctisMotion.adaptive(NoctisMotion.fade, reduceMotion: reduceMotion), value: phase.fieldGone)
            }
    }

    @ViewBuilder
    private func chrome(_ scroll: some View) -> some View {
        let configured: AnyView = configureScroll?(AnyView(scroll)) ?? AnyView(scroll)
        let base = configured
            .scrollPosition($scrollPosition)
            // R14: cards keep their shadows at the scroll view's edges.
            .scrollClipDisabled()
            .modifier(TabScrollObserver(fieldHeight: fieldHeight, phase: $phase, onScroll: onScroll, onScrollPhase: onScrollPhase))
        switch presentation {
        case .tab:
            refreshable(base.scrollEdgeEffectHidden(true, for: .top))
                .overlay(alignment: .top) {
                    NoctisSectionScrim(section: section, phase: phase, paperWashes: paperWashes, fieldWashes: fieldWashes)
                }
        case .pushed:
            refreshable(base)
        }
    }

    @ViewBuilder
    private func refreshable(_ view: some View) -> some View {
        if let refresh {
            view.refreshable { await refresh() }
        } else {
            view
        }
    }

    private var field: some View {
        NoctisSectionField(
            section,
            bottomInset: bottomInset,
            height: $fieldHeight,
            entrance: entrance,
            onEntered: onEntered,
            maxWidth: fieldMaxWidth,
            washes: fieldWashes
        ) {
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                // At accessibility sizes the trailing buttons sit on a row of their own above the text: beside it they took 88pt of an SE's
                // 335pt and the summary broke inside its word ("Understan / d your patterns.").
                if dynamicTypeSize.isAccessibilitySize, let trailing = header.trailing {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        trailing
                    }
                }
                HStack(alignment: .top, spacing: NoctisSpacing.sm) {
                    VStack(alignment: .leading, spacing: 6) {
                        NoctisCaption(header.dateCaption, style: .noctisFieldCaption)
                            .opacity(header.dateCaption.isEmpty ? 0 : 1)
                        if header.showsTitle {
                            header.title
                                .noctisFont(34, .bold, relativeTo: .largeTitle)
                                .tracking(-0.6)
                                .foregroundStyle(.noctisFieldInk)
                                .lineLimit(3)
                                .minimumScaleFactor(0.8)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("tab.title")
                        }
                        if let summary = header.summary {
                            summary
                                .noctisFont(17, relativeTo: .body)
                                .foregroundStyle(.noctisFieldInk2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !dynamicTypeSize.isAccessibilitySize, let trailing = header.trailing {
                        trailing
                    }
                }
                if let control = header.control {
                    control.noctisWashOrigin()
                }
                if let hero = header.hero {
                    hero
                }
            }
        } motif: {
            // A motif in the corner reads as a menu, with or without a button under it (QA part 5): left out whenever it would sit there.
            if NoctisSectionMotif.sitsInTheCorner(section) {
                EmptyView()
            } else {
                NoctisSectionMotif(section)
            }
        }
    }

    private func scrollToTop() {
        withAnimation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion)) {
            scrollPosition.scrollTo(edge: .top)
        }
    }
}

// MARK: - Pieces

private struct TabContentSpace: ViewModifier {
    let name: String?

    func body(content: Content) -> some View {
        if let name {
            content.coordinateSpace(.named(name))
        } else {
            content
        }
    }
}

private struct TabScreenNavigation: ViewModifier {
    let presentation: TabScreenPresentation
    let title: String

    func body(content: Content) -> some View {
        switch presentation {
        case .tab:
            content
                .navigationTitle(title)
                .toolbar(.hidden, for: .navigationBar)
        case .pushed:
            content
        }
    }
}

/// Watches the scroll: the steps the status bar and the compact bar follow,
/// and, when asked, the raw offset and phase.
private struct TabScrollObserver: ViewModifier {
    let fieldHeight: CGFloat
    @Binding var phase: NoctisScrollPhase
    let onScroll: ((Double) -> Void)?
    let onScrollPhase: ((ScrollPhase, ScrollPhase) -> Void)?

    func body(content: Content) -> some View {
        let height = Double(fieldHeight)
        content
            .onScrollGeometryChange(for: NoctisScrollPhase.self) { geometry in
                NoctisScrollPhase(offset: Double(geometry.contentOffset.y + geometry.contentInsets.top), fieldHeight: height)
            } action: { _, new in
                phase = new
            }
            .onScrollGeometryChange(for: Double.self) { geometry in
                onScroll == nil ? 0 : Double(geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, offset in
                onScroll?(offset)
            }
            .onScrollPhaseChange { old, new in
                onScrollPhase?(old, new)
            }
    }
}

/// The compact title bar every tab shares, pinned under the status bar: a
/// paper strip with a leading glyph or ring and a title, then a 16pt fade
/// so content slides out from under it. Tapping it springs back to the top.
public struct TabCompactBar<Content: View>: View {
    private let paper: Color
    private let label: String
    private let identifier: String
    private let maxWidth: CGFloat
    private let action: () -> Void
    private let content: Content

    /// Matches `NoctisStatusBarScrim`'s fade.
    public static var fadeHeight: CGFloat { 16 }

    public init(
        paper: Color = NoctisAppColor.bg,
        label: String,
        identifier: String,
        maxWidth: CGFloat = 680,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.paper = paper
        self.label = label
        self.identifier = identifier
        self.maxWidth = maxWidth
        self.action = action
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 10) {
                    content
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .frame(maxWidth: maxWidth)
                .padding(.horizontal, NoctisSpacing.lg)
                .padding(.vertical, NoctisSpacing.xxs)
                .frame(maxWidth: .infinity)
                .background(paper)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The button's frame is exactly what it answers to.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label). Scroll to top")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(identifier)
            // The same paper fade as the status bar scrim, under the bar;
            // touches pass through it to the content.
            LinearGradient(colors: [paper, paper.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.fadeHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
