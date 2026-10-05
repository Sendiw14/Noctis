import Foundation
import NoctisWatchKit
import NoctisWidgetKit
import Observation
import WidgetKit

/// What the Watch app's screens read (APP_RULES.md R50, R51): the held snapshot and when it arrived. It runs no engine and reads no Health: it holds
/// what the iPhone sent, and `WatchState` says what that allows the screens to say.
@MainActor
@Observable
final class WatchModel {
    private(set) var snapshot: WidgetSnapshot?
    private(set) var receivedAt: Date?
    private(set) var isPhoneReachable = false

    @ObservationIgnored private(set) var receiver: WatchSnapshotReceiver?
    #if DEBUG
    /// `-watchRedacted`: draw every Health number as the system draws it while the Watch is locked.
    @ObservationIgnored private(set) var debugRedacted = false
    /// With a mock, the time the pages are drawn at is the mock's, running on from when the app started.
    @ObservationIgnored private var debugClock: (pretend: Date, started: Date)?
    /// `-watchPage recovery|sleep|heart|tonight|settings`: the page to open on, so a screenshot needs no scrolling.
    @ObservationIgnored private(set) var debugPage: WatchPage?
    #endif

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        debugRedacted = arguments.contains("-watchRedacted")
        if let index = arguments.firstIndex(of: "-watchPage"), arguments.indices.contains(index + 1) { debugPage = WatchPage(rawValue: arguments[index + 1]) }
        if let mock = WatchMock(arguments: arguments) {
            // `-watchMockSnapshot full|learning|...`: the Watch app without the iPhone, for screenshots and tests. Nothing is stored or received.
            snapshot = mock.snapshot
            receivedAt = mock.receivedAt
            isPhoneReachable = true
            debugClock = (mock.now, Date())
            return
        }
        #endif
        let inbox = WatchInbox()
        let held = inbox?.load()
        snapshot = held?.snapshot
        receivedAt = held?.receivedAt
        receiver = WatchSnapshotReceiver(
            inbox: inbox,
            didChange: { [weak self] held in Task { @MainActor in self?.apply(held) } },
            didChangeReachability: { [weak self] reachable in Task { @MainActor in self?.isPhoneReachable = reachable } },
            // What the Watch holds changed: the complications are asked to draw it.
            reloadComplications: { WidgetCenter.shared.reloadAllTimelines() }
        )
        receiver?.activate()
    }

    private func apply(_ held: (snapshot: WidgetSnapshot, receivedAt: Date?)?) {
        snapshot = held?.snapshot
        receivedAt = held?.receivedAt
    }

    /// Everything a page needs, at `now`.
    func input(now: Date) -> WatchPageInput {
        #if DEBUG
        if let debugClock { return WatchPageInput(snapshot: snapshot, now: debugClock.pretend.addingTimeInterval(now.timeIntervalSince(debugClock.started)), receivedAt: receivedAt) }
        #endif
        return WatchPageInput(snapshot: snapshot, now: now, receivedAt: receivedAt)
    }

    /// The page the Watch opens on: always Recovery, except for the DEBUG flag.
    var initialPage: WatchPage {
        #if DEBUG
        if let debugPage { return debugPage }
        #endif
        return .recovery
    }

    /// A date on the page's clock as a date on the system clock, which is what a timer-style `Text` runs on. They are the same thing, except in the
    /// DEBUG mock, which pretends it is another time of day.
    func systemDate(for date: Date) -> Date {
        #if DEBUG
        if let debugClock { return debugClock.started.addingTimeInterval(date.timeIntervalSince(debugClock.pretend)) }
        #endif
        return date
    }

    var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "NOCTIS \(version) (\(build))"
    }

    /// "Ask iPhone to update": only while the iPhone can be reached.
    func askPhone() async -> String {
        guard let receiver else { return WatchCopy.asked }
        switch await receiver.requestUpdate() {
        case .accepted: return WatchCopy.asked
        case .unreachable: return WatchCopy.unreachable
        case .failed: return WatchCopy.askFailed
        }
    }
}
