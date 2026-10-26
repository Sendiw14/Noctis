import Foundation
import NightKit
import NoctisWidgetKit
import PremiumKit

/// What the publisher asks the app for each time it writes: the profile, the bedtime recommendation if one is known, and the
/// alarm. Set after the repositories that answer exist, so the publisher can be made first.
public nonisolated final class WidgetInputSource: @unchecked Sendable {
    private let lock = NSLock()
    private var profileProvider: @Sendable () async -> UserProfileSnapshot
    private var bedtimeProvider: @Sendable (UserProfileSnapshot) async -> BedtimeRecommendation? = { _ in nil }
    private var alarmProvider: @Sendable () async -> WidgetAlarm? = { nil }
    private var tierProvider: @Sendable () async -> Tier = { .free }

    public init(profile: @escaping @Sendable () async -> UserProfileSnapshot) {
        profileProvider = profile
    }

    public func setBedtime(_ provider: @escaping @Sendable (UserProfileSnapshot) async -> BedtimeRecommendation?) {
        lock.withLock { bedtimeProvider = provider }
    }

    public func setAlarm(_ provider: @escaping @Sendable () async -> WidgetAlarm?) {
        lock.withLock { alarmProvider = provider }
    }

    /// The person's plan, written into the snapshot so the extensions and the Watch need not (and never do) call StoreKit. Free until the app says otherwise.
    public func setTier(_ provider: @escaping @Sendable () async -> Tier) {
        lock.withLock { tierProvider = provider }
    }

    func current() async -> (profile: UserProfileSnapshot, bedtime: BedtimeRecommendation?, alarm: WidgetAlarm?, tier: Tier) {
        let (profileFor, bedtimeFor, alarmFor, tierFor) = lock.withLock { (profileProvider, bedtimeProvider, alarmProvider, tierProvider) }
        let profile = await profileFor()
        return await (profile, bedtimeFor(profile), alarmFor(), tierFor())
    }
}

/// Writes the widgets' snapshot and asks the system to redraw them (APP_RULES.md R44). Called by `HomeRepository` after every
/// refresh that read Health, and by the app when the alarm or the profile changes. Does nothing when nothing the widgets draw has
/// changed, so the system's reload budget is spent on real changes.
public actor WidgetPublisher {
    private let store: WidgetSnapshotStore?
    private let inputs: WidgetInputSource
    private let reload: @Sendable () -> Void
    private let clock: @Sendable () -> Date
    private let calendar: Calendar
    /// The data epoch every snapshot carries (the time of the last "Delete all NOCTIS data"; 0 if never), so the Apple Watch can tell.
    private let epoch: @Sendable () -> Int64
    /// Told after a snapshot was written (the Apple Watch is sent it), and after the summary was deleted (the Watch is told to drop its copy).
    private let afterWrite: @Sendable (WidgetSnapshot) async -> Void
    private let afterForget: @Sendable () async -> Void
    private var latest: HomeSnapshot?
    private var written: WidgetSnapshot?
    private var suspended = false

    /// `store` is nil where the App Group is not available; the publisher then does nothing.
    public init(
        store: WidgetSnapshotStore?, inputs: WidgetInputSource, reload: @escaping @Sendable () -> Void = {},
        clock: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .autoupdatingCurrent,
        epoch: @escaping @Sendable () -> Int64 = { 0 }, afterWrite: @escaping @Sendable (WidgetSnapshot) async -> Void = { _ in },
        afterForget: @escaping @Sendable () async -> Void = {}
    ) {
        self.store = store
        self.inputs = inputs
        self.reload = reload
        self.clock = clock
        self.calendar = calendar
        self.epoch = epoch
        self.afterWrite = afterWrite
        self.afterForget = afterForget
        written = store?.load()
    }

    /// The snapshot after a Health read. A failed read changes nothing.
    public func publish(_ home: HomeSnapshot) async {
        latest = home
        await write()
    }

    /// The same Home data with the plan or the alarm as they are now.
    public func republish() async {
        guard latest != nil else { return }
        await write()
    }

    /// Deletes the file and forgets what was held (Data management).
    public func forget() async {
        latest = nil
        written = nil
        store?.delete()
        reload()
        await afterForget()
    }

    /// Stops writing, for good: the app is deleting its data and will start over.
    public func suspend() {
        suspended = true
    }

    public var lastWritten: WidgetSnapshot? { written }

    private func write() async {
        guard !suspended, let store, let home = latest else { return }
        let now = clock()
        let current = await inputs.current()
        guard
            let snapshot = WidgetSnapshotMaker.make(
                home: home, profile: current.profile, bedtime: current.bedtime, alarm: current.alarm, now: now, calendar: calendar, dataEpoch: epoch(),
                tier: current.tier
            )
        else { return }
        // Nothing the widgets draw has changed: leave the file, and the system's budget, alone.
        if let written, Self.sameContent(written, snapshot) { return }
        guard !suspended, store.save(snapshot) else { return }
        written = snapshot
        reload()
        await afterWrite(snapshot)
    }

    /// Equal but for the time it was made.
    static func sameContent(_ lhs: WidgetSnapshot, _ rhs: WidgetSnapshot) -> Bool {
        var other = rhs
        other.generatedAt = lhs.generatedAt
        return lhs == other
    }
}
