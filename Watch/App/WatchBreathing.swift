import BreathingKit
import DesignSystem
import NoctisWatchKit
import Observation
import SwiftUI
import WatchKit

// Breathing on the Watch (APP_RULES.md R55): the pattern, the schedule, the haptic plan and the session's rules are `BreathingKit`'s and
// `NoctisWatchKit`'s (pure, tested); this file plays them with the system's own session and haptics and draws them. It reads no Health and writes none.

// MARK: - The system's session and haptics

/// A mindfulness `WKExtendedRuntimeSession` (the `mindfulness` background mode in this app's Info.plist): it keeps the app running with the wrist down
/// and the screen asleep so the haptics go on. It must be started while the app is active. It lasts at most about ten minutes; when it ends, or cannot
/// start, the exercise goes on while the screen is on and waits ("Raise your wrist to continue") while it is not.
final class WKRuntimeClient: NSObject, ExtendedRuntimeClient, WKExtendedRuntimeSessionDelegate, @unchecked Sendable {
    var onEvent: (@Sendable (ExtendedRuntimeEvent) -> Void)?
    private var session: WKExtendedRuntimeSession?

    func start() {
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        self.session = session
        session.start()
    }

    func invalidate() {
        guard let session, session.state == .running || session.state == .scheduled else { return }
        session.invalidate()
    }

    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        onEvent?(.started)
    }

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        onEvent?(.willExpire)
    }

    func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: (any Error)?
    ) {
        let mapped: ExtendedRuntimeInvalidation
        switch reason {
        case .none: mapped = .none
        case .sessionInProgress: mapped = .sessionInProgress
        case .expired: mapped = .expired
        case .resignedFrontmost: mapped = .resignedFrontmost
        case .suppressedBySystem: mapped = .suppressedBySystem
        default: mapped = .error
        }
        onEvent?(.invalidated(mapped))
    }
}

/// The wrist: one of the system's haptic types for each change of breath. `directionUp` rises like an inhale, `directionDown` falls like an exhale, `click` is a
/// single light tap for a hold, and `success` ends the exercise.
final class WKHaptics: BreathHapticPlaying {
    func play(_ haptic: BreathHaptic) {
        let type: WKHapticType
        switch haptic {
        case .inhale: type = .directionUp
        case .hold: type = .click
        case .exhale: type = .directionDown
        case .done: type = .success
        }
        WKInterfaceDevice.current().play(type)
    }
}

// MARK: - The model

@MainActor
@Observable
final class WatchBreathModel {
    enum Stage { case picking, running, done }

    var stage: Stage = .picking
    var choice = WatchBreathChoice()
    private(set) var driver: BreathSessionDriver?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored let preferences: WatchPreferences

    init(preferences: WatchPreferences) {
        self.preferences = preferences
    }

    var hapticsOn: Bool {
        get { access(keyPath: \.hapticsOn); return preferences.breathHaptics }
        set { withMutation(keyPath: \.hapticsOn) { preferences.breathHaptics = newValue } }
    }

    /// Starts the exercise: the runtime session is asked for, and a timer calls the driver while it runs.
    func start(isActive: Bool = true) {
        let now = Date()
        let driver = BreathSessionDriver(
            schedule: choice.schedule, now: now, isActive: isActive, hapticsEnabled: preferences.breathHaptics, runtime: WKRuntimeClient(), haptics: WKHaptics()
        )
        self.driver = driver
        stage = .running
        driver.begin(at: now)
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                driver.tick(at: Date())
                if driver.model.isFinished {
                    self?.stage = .done
                    break
                }
            }
        }
    }

    /// The person ended it, or left: no success haptic, and the session is ended.
    func end() {
        ticker?.cancel()
        driver?.cancel(at: Date())
        driver = nil
        stage = .picking
    }

    /// "Delete all NOCTIS data" on the iPhone reached the Watch: the preference goes back to its default.
    func resetPreferences() {
        withMutation(keyPath: \.hapticsOn) { preferences.reset() }
    }

    func again() {
        driver = nil
        stage = .picking
    }

    func sceneChanged(active: Bool) {
        guard let driver else { return }
        active ? driver.sceneBecameActive(at: Date()) : driver.sceneBecameInactive(at: Date())
    }

    /// What the screen shows at `date`; nil with no exercise.
    func frame(at date: Date) -> WatchBreathFrame? {
        guard let driver else { return nil }
        #if DEBUG
        if let debugFrozenElapsed { return WatchBreathFrame(moment: driver.model.schedule.moment(at: debugFrozenElapsed)) }
        #endif
        return WatchBreathFrame(moment: driver.model.schedule.moment(at: driver.model.elapsed(at: date)))
    }

    #if DEBUG
    /// `-watchBreathing picker | running:<calm|box|relax>:<minutes>:<seconds in>[:reduce][:paused] | done`: a screen in the state named, for a screenshot. A running
    /// one is the real exercise with the picture held at that moment.
    @ObservationIgnored var debugFrozenElapsed: Double?
    var debugReduceMotion = false

    func debugApply(_ script: String) {
        let parts = script.split(separator: ":").map(String.init)
        switch parts.first {
        case "running" where parts.count >= 4:
            choice.pattern = BreathingPattern.ID(rawValue: parts[1]) ?? .calm
            choice.minutes = Int(parts[2]) ?? 5
            debugFrozenElapsed = Double(parts[3])
            debugReduceMotion = parts.contains("reduce")
            start()
            if parts.contains("paused"), let driver {
                driver.runtimeEvent(.invalidated(.error), at: Date())
                driver.sceneBecameInactive(at: Date())
            }
        case "done":
            stage = .done
        default:
            stage = .picking
        }
    }
    #endif

    var pauseMessage: String? { driver?.model.pauseMessage }
}

// MARK: - The screens

struct BreathFlowView: View {
    @Bindable var model: WatchBreathModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch model.stage {
            case .picking: BreathPickerView(model: model)
            case .running: BreathSessionView(model: model)
            case .done: BreathDoneView(model: model)
            }
        }
        .background(Color.black)
        .onChange(of: scenePhase) { _, phase in model.sceneChanged(active: phase == .active) }
        // Closing the sheet during the exercise ends it.
        .onDisappear { if model.stage == .running { model.end() } }
    }
}

private struct BreathChip: View {
    let title: String
    var detail: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(title).noctisFont(14, .semibold, relativeTo: .footnote)
                if let detail { Text(detail).noctisFont(12, relativeTo: .caption2) }
            }
            .foregroundStyle(selected ? NoctisAppColor.blockInk : WatchTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Capsule(style: .continuous).fill(selected ? WatchTheme.ink : Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct BreathPickerView: View {
    @Bindable var model: WatchBreathModel

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text(WatchBreathCopy.tagline)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(WatchTheme.quiet)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 4) {
                    ForEach(BreathingPattern.all) { pattern in
                        BreathChip(title: pattern.title, detail: pattern.rhythm, selected: model.choice.pattern == pattern.id) { model.choice.pattern = pattern.id }
                            .accessibilityLabel("\(pattern.title), \(pattern.rhythm)")
                    }
                }
                HStack(spacing: 4) {
                    ForEach(BreathingSchedule.durations, id: \.self) { minutes in
                        BreathChip(title: WatchBreathCopy.minutes(minutes), selected: model.choice.minutes == minutes) { model.choice.minutes = minutes }
                    }
                }
                Button(action: { model.start() }) {
                    Text(WatchBreathCopy.start)
                        .noctisFont(15, .semibold, relativeTo: .body)
                        .foregroundStyle(NoctisAppColor.blockInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule(style: .continuous).fill(WatchTheme.accent(.tonight)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
        }
    }
}

struct BreathSessionView: View {
    @Bindable var model: WatchBreathModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var reduceMotion: Bool {
        #if DEBUG
        return systemReduceMotion || model.debugReduceMotion
        #else
        return systemReduceMotion
        #endif
    }

    var body: some View {
        VStack(spacing: 6) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: model.pauseMessage != nil)) { context in
                if let frame = model.frame(at: context.date) {
                    if reduceMotion { levelBar(frame) } else { circle(frame) }
                }
            }
            if let message = model.pauseMessage {
                Text(message).noctisFont(13, .semibold, relativeTo: .footnote).foregroundStyle(WatchTheme.ink).multilineTextAlignment(.center)
            }
            Button(action: { model.end() }) {
                Text(WatchBreathCopy.end)
                    .noctisFont(13, .semibold, relativeTo: .footnote)
                    .foregroundStyle(WatchTheme.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule(style: .continuous).fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
    }

    /// A flat ivory circle that grows on the inhale and shrinks on the exhale, with the seconds in it and the phase's name above it (a small circle has no
    /// room for the name).
    private func circle(_ frame: WatchBreathFrame) -> some View {
        VStack(spacing: 4) {
            Text(frame.phase).noctisFont(14, .semibold, relativeTo: .footnote).foregroundStyle(WatchTheme.ink)
            GeometryReader { proxy in
                let room = min(proxy.size.width, proxy.size.height)
                ZStack {
                    Circle().fill(WatchTheme.ink).frame(width: room * frame.circleScale, height: room * frame.circleScale)
                    Text("\(frame.seconds)").noctisFont(34, .bold, relativeTo: .title).monospacedDigit().foregroundStyle(NoctisAppColor.blockInk)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(frame.accessibilityLabel)
    }

    /// With Reduce Motion: no growing. The same words over a flat level bar that fills and empties.
    private func levelBar(_ frame: WatchBreathFrame) -> some View {
        VStack(spacing: 10) {
            words(frame).foregroundStyle(WatchTheme.ink)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous).fill(Color.white.opacity(0.18))
                    Capsule(style: .continuous).fill(WatchTheme.ink).frame(width: max(proxy.size.width * frame.level, 12))
                }
            }
            .frame(height: 14)
        }
        .frame(maxHeight: .infinity)
    }

    private func words(_ frame: WatchBreathFrame) -> some View {
        VStack(spacing: 0) {
            Text(frame.phase).noctisFont(14, .semibold, relativeTo: .footnote)
            Text("\(frame.seconds)").noctisFont(34, .bold, relativeTo: .title).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(frame.accessibilityLabel)
    }
}

struct BreathDoneView: View {
    @Bindable var model: WatchBreathModel

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").noctisIcon(34, .semibold, relativeTo: .title).foregroundStyle(NoctisAppColor.sage)
                Text(WatchBreathCopy.done).noctisFont(24, .heavy, relativeTo: .title2).foregroundStyle(WatchTheme.ink)
                Button(action: { model.again() }) {
                    Text(WatchBreathCopy.again)
                        .noctisFont(15, .semibold, relativeTo: .body)
                        .foregroundStyle(NoctisAppColor.blockInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule(style: .continuous).fill(WatchTheme.accent(.tonight)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
        }
    }
}
