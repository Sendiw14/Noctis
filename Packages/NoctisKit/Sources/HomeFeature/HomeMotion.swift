import DesignSystem
import SwiftUI
import UIKit

extension EnvironmentValues {
    /// The morning reveal's phase, for every view that takes part in it.
    @Entry var homeReveal: HomeRevealPhase = .none
    /// Matched geometry for the mode morph; nil under Reduce Motion.
    @Entry var homeMorph: Namespace.ID? = nil
    /// Low Power Mode: no count-up, no secondary staggers, no ambient
    /// animation.
    @Entry var homeLowPower: Bool = false
}

extension HomeRevealPhase {
    /// Whether a view shows its start state (empty ring, bars not drawn).
    public var holdsStart: Bool { self == .pending }

    /// When the ring, capsules and bars start: after the dusk crossfade.
    static let contentDelay = HomeReveal.backgroundDuration
}

/// The mode morph's shared element: the day ring and the evening card's
/// ring are one ring changing size.
enum HomeMorphID: Hashable {
    case recoveryRing
}

extension View {
    /// Joins the mode morph as `id` when motion is on.
    @ViewBuilder
    func homeMorph(_ id: HomeMorphID, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}

/// The hero shrinking (1.0 → 0.85) and fading as it scrolls away. Only
/// this view reads the collapse, so scrolling redraws nothing else.
struct HomeCollapseEffect<Content: View>: View {
    let viewModel: HomeViewModel
    var anchor: UnitPoint = .center
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let progress = viewModel.collapseProgress
        content
            .scaleEffect(reduceMotion ? 1 : HomeCollapse.scale(at: progress), anchor: anchor)
            .opacity(HomeCollapse.opacity(at: progress))
    }
}

/// A horizontal pan that only begins when the finger moves more sideways
/// than up or down, so vertical drags still scroll Home. Reports the
/// finger's x in the view, then nil when it lifts.
public struct HorizontalScrubGesture: UIGestureRecognizerRepresentable {
    var isEnabled = true
    let onChange: (CGFloat?) -> Void

    public init(isEnabled: Bool = true, onChange: @escaping (CGFloat?) -> Void) {
        self.isEnabled = isEnabled
        self.onChange = onChange
    }

    public func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    public func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        return pan
    }

    public func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    public func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChange(context.converter.localLocation.x)
        default:
            onChange(nil)
        }
    }

    public final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        public func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}

/// The scrub and selection pill: ink-on-ivory on the night panel,
/// ivory-on-ink on the paper.
public struct HomePill: View {
    let text: String
    var onNightPanel = false

    public init(text: String, onNightPanel: Bool = false) {
        self.text = text
        self.onNightPanel = onNightPanel
    }

    public var body: some View {
        Text(text)
            .noctisFont(13, .semibold, relativeTo: .footnote)
            .monospacedDigit()
            // One line at normal sizes; wraps inside its chart at
            // accessibility sizes (the layout offers it the chart's width).
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(onNightPanel ? NoctisAppColor.nightPanel : NoctisAppColor.bg)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(onNightPanel ? NoctisAppColor.nightInk : NoctisAppColor.ink, in: Capsule(style: .continuous))
    }
}

// MARK: - Column scrub

extension View {
    /// Picks a column of a chart: a horizontal drag follows the finger with
    /// a snap haptic at each column, and a tap picks the column under it (a
    /// tap on the column already picked clears it). A drag that starts more
    /// up and down than sideways is the page scrolling, so it does.
    ///
    /// The touch area runs `outset` out past the chart on each side (the
    /// card's padding and the screen margin) for the two outer columns; the
    /// chart itself (`chartWidth` wide) is what the columns split.
    public func columnScrub(count: Int, chartWidth: CGFloat, outset: CGFloat, selected: Binding<Int?>) -> some View {
        modifier(ColumnScrub(count: count, chartWidth: chartWidth, outset: outset, selected: selected))
    }
}

struct ColumnScrub: ViewModifier {
    let count: Int
    let chartWidth: CGFloat
    let outset: CGFloat
    @Binding var selected: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrubbing = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, outset)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                let column = column(at: location.x)
                if column == selected {
                    withAnimation(animation) { selected = nil }
                } else {
                    pick(column)
                }
            }
            .gesture(HorizontalScrubGesture { x in
                guard let x else {
                    if scrubbing { NoctisSignpost.end(.scrub) }
                    scrubbing = false
                    return
                }
                if !scrubbing {
                    scrubbing = true
                    NoctisSignpost.begin(.scrub)
                }
                pick(column(at: x))
            })
            .padding(.horizontal, -outset)
    }

    private var animation: Animation { NoctisMotion.adaptive(NoctisMotion.select, reduceMotion: reduceMotion) }

    private func pick(_ column: Int) {
        guard column != selected else { return }
        NoctisHaptics.snapLight()
        withAnimation(animation) { selected = column }
    }

    private func column(at x: CGFloat) -> Int {
        WeekColumns.index(x: x, barsWidth: chartWidth, outset: outset, count: count)
    }
}
