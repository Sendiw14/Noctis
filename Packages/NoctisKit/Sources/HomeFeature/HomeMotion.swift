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
    var holdsStart: Bool { self == .pending }

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
struct HorizontalScrubGesture: UIGestureRecognizerRepresentable {
    var isEnabled = true
    let onChange: (CGFloat?) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChange(context.converter.localLocation.x)
        default:
            onChange(nil)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}

/// The scrub and selection pill: ink-on-ivory on the night panel,
/// ivory-on-ink on the paper.
struct HomePill: View {
    let text: String
    var onNightPanel = false

    var body: some View {
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
