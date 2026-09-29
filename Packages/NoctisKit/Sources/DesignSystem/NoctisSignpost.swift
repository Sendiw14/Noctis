import Foundation
import QuartzCore
import os

/// The intervals NOCTIS's performance budgets are measured over, as
/// `os_signpost` intervals in one subsystem and category, so Instruments
/// (the "Points of Interest"-style signpost track), `xctrace` and
/// `XCTOSSignpostMetric` all see them by name:
///
/// - `LaunchToFirstFrame`: the app starting to Home's first frame.
/// - `LaunchToPopulated`: the app starting to Home showing fresh data.
/// - `Reveal`: the morning reveal, start to end (or to a skip).
/// - `Morph`: the day ↔ evening morph.
/// - `Collapse`: a scroll, finger down to rest, over which the hero
///   collapses into the compact bar.
/// - `Scrub`: a finger scrubbing the night panel or the week.
/// - `TabSwitch`: a tab being chosen to its content appearing.
public nonisolated enum NoctisSignpost {
    public static let subsystem = "com.noctis.app"
    public static let category = "Performance"

    public enum Interval: String, CaseIterable, Sendable {
        case launchToFirstFrame = "LaunchToFirstFrame"
        case launchToPopulated = "LaunchToPopulated"
        case reveal = "Reveal"
        case morph = "Morph"
        case collapse = "Collapse"
        case scrub = "Scrub"
        case tabSwitch = "TabSwitch"
        /// The Sleep repository reading Health and deriving every night.
        case sleepLoad = "SleepLoad"
        /// Building the render model for one Sleep selection.
        case sleepModel = "SleepModel"
    }

    private static let signposter = OSSignposter(subsystem: subsystem, category: category)
    private static let running = Running()

    /// Starts `interval`. One of a kind can run at a time; starting it
    /// again while it runs does nothing (a finger down twice, a launch).
    public static func begin(_ interval: Interval) {
        running.begin(interval) {
            switch interval {
            case .launchToFirstFrame: signposter.beginInterval("LaunchToFirstFrame")
            case .launchToPopulated: signposter.beginInterval("LaunchToPopulated")
            case .reveal: signposter.beginInterval("Reveal")
            case .morph: signposter.beginInterval("Morph")
            case .collapse: signposter.beginInterval("Collapse")
            case .scrub: signposter.beginInterval("Scrub")
            case .tabSwitch: signposter.beginInterval("TabSwitch")
            case .sleepLoad: signposter.beginInterval("SleepLoad")
            case .sleepModel: signposter.beginInterval("SleepModel")
            }
        }
    }

    /// Ends `interval`; nothing happens if it isn't running.
    public static func end(_ interval: Interval) {
        running.end(interval) { state in
            switch interval {
            case .launchToFirstFrame: signposter.endInterval("LaunchToFirstFrame", state)
            case .launchToPopulated: signposter.endInterval("LaunchToPopulated", state)
            case .reveal: signposter.endInterval("Reveal", state)
            case .morph: signposter.endInterval("Morph", state)
            case .collapse: signposter.endInterval("Collapse", state)
            case .scrub: signposter.endInterval("Scrub", state)
            case .tabSwitch: signposter.endInterval("TabSwitch", state)
            case .sleepLoad: signposter.endInterval("SleepLoad", state)
            case .sleepModel: signposter.endInterval("SleepModel", state)
            }
        }
    }

    /// Ends `interval` on the first display frame after now: for an
    /// interval that runs until something has been drawn (a tab switch's
    /// content), not just until it was built.
    @MainActor
    public static func endAfterNextFrame(_ interval: Interval) {
        FrameTick.once { end(interval) }
    }

    /// The intervals running now (tests).
    public static var active: Set<Interval> { running.active }

    /// A one-shot display link.
    @MainActor
    private final class FrameTick: NSObject {
        private var link: CADisplayLink?
        private let work: () -> Void

        private init(_ work: @escaping () -> Void) {
            self.work = work
            super.init()
        }

        static func once(_ work: @escaping () -> Void) {
            let tick = FrameTick(work)
            let link = CADisplayLink(target: tick, selector: #selector(fire))
            tick.link = link
            link.add(to: .main, forMode: .common)
        }

        @objc private func fire() {
            link?.invalidate()
            link = nil
            work()
        }
    }

    /// Which intervals are open, and their signpost states.
    private final class Running: @unchecked Sendable {
        private let lock = NSLock()
        private var states: [Interval: OSSignpostIntervalState] = [:]

        var active: Set<Interval> { lock.withLock { Set(states.keys) } }

        func begin(_ interval: Interval, _ start: () -> OSSignpostIntervalState) {
            lock.withLock {
                guard states[interval] == nil else { return }
                states[interval] = start()
            }
        }

        func end(_ interval: Interval, _ finish: (OSSignpostIntervalState) -> Void) {
            lock.withLock {
                guard let state = states.removeValue(forKey: interval) else { return }
                finish(state)
            }
        }
    }
}
