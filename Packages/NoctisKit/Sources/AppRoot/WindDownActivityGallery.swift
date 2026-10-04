#if DEBUG
import DesignSystem
import NoctisWidgetKit
import SwiftUI

// The DEBUG Live Activity gallery (APP_RULES.md R49): `-activityGallery [lock|island|all]`. The Lock Screen presentation and each Dynamic Island
// presentation (compact, minimal, expanded), running and paused, drawn from the very views the extension composes, so a screenshot can be taken
// of each. It is NOT the real thing: the system's own Lock Screen and island (their shape, the camera cutout, their blur and the way the
// expanded island opens) are seen on the simulator's real Lock Screen and Dynamic Island, and on an iPhone. The black shapes here are
// outlines of the island's sizes, and the End button is drawn without its intent.

public enum ActivityGalleryRequest {
    public enum Part: String { case lock, island, all }

    public static func requested(_ arguments: [String]) -> Part? {
        guard let flag = arguments.firstIndex(of: "-activityGallery") else { return nil }
        let value = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : "all"
        return Part(rawValue: value) ?? .all
    }
}

public struct WindDownActivityGalleryView: View {
    let part: ActivityGalleryRequest.Part

    public init(part: ActivityGalleryRequest.Part) {
        self.part = part
    }

    private let attributes = WindDownActivityAttributes(plannedMinutes: 20, startedAt: Date().addingTimeInterval(-450))

    /// 7 and a half minutes in: 12:30 left, running.
    private var running: WindDownActivityAttributes.ContentState {
        WindDownActivityState.make(phase: .running, startedAt: attributes.startedAt, pausedTotal: 0, plannedSeconds: 1200)
    }

    /// Paused at the same moment, with the countdown standing at 12:30.
    private var paused: WindDownActivityAttributes.ContentState {
        WindDownActivityState.make(phase: .paused, startedAt: attributes.startedAt, pausedTotal: 0, plannedSeconds: 1200, pausedAt: Date())
    }

    private var ending: WindDownActivityAttributes.ContentState {
        WindDownActivityState.make(phase: .ending, startedAt: attributes.startedAt, pausedTotal: 0, plannedSeconds: 1200)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if part != .island {
                    label("Lock Screen: running")
                    lockScreen(running)
                    label("Lock Screen: paused")
                    lockScreen(paused)
                    label("Lock Screen: the time ran out")
                    lockScreen(ending)
                }
                if part != .lock {
                    label("Dynamic Island: compact, running")
                    compact(running)
                    label("Dynamic Island: compact, paused")
                    compact(paused)
                    label("Dynamic Island: compact, over")
                    compact(ending)
                    label("Dynamic Island: minimal")
                    minimal
                    label("Dynamic Island: expanded, running")
                    expanded(running)
                    label("Dynamic Island: expanded, paused")
                    expanded(paused)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background(Color(white: 0.12).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .noctisFont(13, .semibold, relativeTo: .footnote)
            .foregroundStyle(Color.white.opacity(0.7))
    }

    private func lockScreen(_ state: WindDownActivityAttributes.ContentState) -> some View {
        WindDownLockScreenView(attributes: attributes, state: state) { WindDownEndLabel() }
            .background(WindDownActivityStyle.background)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// The island's compact form: a black pill with the camera between its two halves.
    private func compact(_ state: WindDownActivityAttributes.ContentState) -> some View {
        HStack(spacing: 0) {
            WindDownIslandCompactLeading().frame(width: 52, alignment: .leading)
            Spacer(minLength: 0)
            WindDownIslandCompactTrailing(state: state).frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(width: 250, height: 37)
        .background(Capsule(style: .continuous).fill(Color.black))
        .frame(maxWidth: .infinity)
    }

    private var minimal: some View {
        WindDownIslandMinimal()
            .frame(width: 37, height: 37)
            .background(Circle().fill(Color.black))
            .frame(maxWidth: .infinity)
    }

    private func expanded(_ state: WindDownActivityAttributes.ContentState) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                WindDownIslandExpandedLeading(attributes: attributes, state: state)
                Spacer(minLength: 8)
                WindDownIslandExpandedTrailing(state: state)
            }
            WindDownIslandExpandedBottom(state: state) { WindDownEndLabel() }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 44, style: .continuous).fill(Color.black))
    }
}
#endif
