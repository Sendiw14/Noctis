import Foundation
import InsightsKit
import RecoveryKit
import SleepKit

/// The last `HomeSnapshot`, kept on this device so the next launch draws
/// Home in its first frame instead of waiting for Health.
///
/// What it holds is derived values only: the scores and factor values the
/// engines produced, last night's summary and the geometry of its chart,
/// the week's durations, the insight's numbers and the downsampled heart
/// curve. It never holds a raw HealthKit record (no sample, no per-sample
/// timestamp, no source or device name: `PersistedSleep` leaves out the
/// stage timeline and the source name on purpose). The file has complete
/// file protection (unreadable while the device is locked, so a launch
/// before first unlock simply finds nothing), is excluded from backups, and
/// is registered with `NoctisDataRegistry` so Data Management erases it.
public nonisolated final class HomeSnapshotStore: NoctisErasable, @unchecked Sendable {
    /// Bumped whenever the persisted shape changes: an older file is
    /// dropped, never half-read.
    public static let schemaVersion = 1
    /// A file older than this is dropped: the baselines behind it reach
    /// back 30 days, so it says nothing current.
    public static let maximumAge: TimeInterval = 30 * 24 * 3600
    /// The data is stale after this long without a new Health sample.
    static let staleAfter = HomeSnapshotBuilder.staleAfter

    public let fileURL: URL
    private let clock: @Sendable () -> Date
    private let lock = NSLock()

    public var erasableName: String { "Home snapshot" }

    /// `directory` defaults to a "Noctis" folder in Application Support.
    public init(directory: URL? = nil, clock: @escaping @Sendable () -> Date = { Date() }) {
        let folder = directory ?? URL.applicationSupportDirectory.appending(path: "Noctis", directoryHint: .isDirectory)
        fileURL = folder.appending(path: "home-snapshot.json", directoryHint: .notDirectory)
        self.clock = clock
    }

    /// Whether a snapshot in this state is worth keeping: it has data to
    /// show. `.failed` is a hiccup (the previous file stays); the other
    /// empty states mean there's nothing left to show, and erase it.
    public static func isPersistable(_ state: HomeDataState) -> Bool {
        switch state {
        case .ready, .noSleepLastNight, .stale: true
        case .learning(let nights): nights > 0
        case .failed, .empty, .permissionRequired, .healthDataUnavailable: false
        }
    }

    // MARK: Write

    public func save(_ snapshot: HomeSnapshot) {
        lock.withLock {
            if Self.isPersistable(snapshot.dataState) {
                write(snapshot)
            } else if snapshot.dataState != .failed {
                remove()
            }
        }
    }

    private func write(_ snapshot: HomeSnapshot) {
        let file = PersistedHomeFile(
            schema: Self.schemaVersion,
            recoveryModel: RecoveryModel.current.version,
            savedAt: clock(),
            home: PersistedHome(snapshot)
        )
        do {
            // Dates keep the default encoding (seconds since the reference
            // date, exactly as a `Date` holds them): a round trip changes
            // nothing, not even the last bit.
            let data = try JSONEncoder().encode(file)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var url = fileURL
            try? url.setResourceValues(values)
        } catch {
            // A cache that can't be written is a cache that isn't there.
        }
    }

    // MARK: Read

    /// The saved snapshot, or nil when there's none, it can't be read, it
    /// is from another schema or recovery model, or it is too old (the
    /// file is deleted in each of those cases). Data whose newest sample is
    /// over a day old comes back `.stale`, as a fresh snapshot would say.
    public func load() -> HomeSnapshot? {
        lock.withLock {
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            guard let file = try? JSONDecoder().decode(PersistedHomeFile.self, from: data) else {
                remove()
                return nil
            }
            let now = clock()
            let age = now.timeIntervalSince(file.savedAt)
            guard file.schema == Self.schemaVersion,
                  file.recoveryModel == RecoveryModel.current.version,
                  age <= Self.maximumAge,
                  file.savedAt <= now.addingTimeInterval(3600)
            else {
                remove()
                return nil
            }
            return file.home.snapshot(now: now)
        }
    }

    // MARK: Erase

    public func erase() {
        lock.withLock { remove() }
    }

    private func remove() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - The file

nonisolated struct PersistedHomeFile: Codable {
    var schema: Int
    var recoveryModel: String
    var savedAt: Date
    var home: PersistedHome
}

/// `HomeSnapshot`, as it is written: every field is a derived value.
nonisolated struct PersistedHome: Codable {
    var dataState: HomeDataState
    var recovery: RecoveryState?
    var lastNight: PersistedSleep?
    var latestSleep: PersistedSleep?
    var recentNights: [NightDuration]
    var weekAverageMinutes: Double?
    var tonight: TonightPlan
    var topInsight: Insight?
    var lastNightHeart: NightHeartSeries?
    var newestSample: Date?
    var lastUpdated: Date
    var render: HomeRenderModel

    init(_ snapshot: HomeSnapshot) {
        dataState = snapshot.dataState
        recovery = snapshot.recovery
        lastNight = snapshot.lastNight.map(PersistedSleep.init)
        latestSleep = snapshot.latestSleep.map(PersistedSleep.init)
        recentNights = snapshot.recentNights
        weekAverageMinutes = snapshot.weekAverageMinutes
        tonight = snapshot.tonight
        topInsight = snapshot.topInsight
        lastNightHeart = snapshot.lastNightHeart
        newestSample = snapshot.newestSample
        lastUpdated = snapshot.lastUpdated
        render = snapshot.render
    }

    func snapshot(now: Date) -> HomeSnapshot {
        // The staleness rule a fresh snapshot applies, as of now.
        var state = dataState
        if let newestSample, now.timeIntervalSince(newestSample) > HomeSnapshotStore.staleAfter {
            switch dataState {
            case .ready, .learning, .noSleepLastNight: state = .stale(newestSample: newestSample)
            default: break
            }
        }
        return HomeSnapshot(
            dataState: state,
            recovery: recovery,
            lastNight: lastNight?.session,
            latestSleep: latestSleep?.session,
            recentNights: recentNights,
            weekAverageMinutes: weekAverageMinutes,
            tonight: tonight,
            topInsight: topInsight,
            lastNightHeart: lastNightHeart,
            newestSample: newestSample,
            lastUpdated: lastUpdated,
            render: render
        )
    }
}

/// A night's summary: when it began and ended, its totals and how
/// complete the data was. Not its stage-by-stage timeline (the chart's
/// geometry is in the render model) and not the name of the app or device
/// that recorded it.
nonisolated struct PersistedSleep: Codable {
    var isNap: Bool
    var night: SleepNightKey
    var bedtime: Date
    var wakeTime: Date
    var timeZone: String
    var totals: SleepTotals
    var awakenings: Int
    var efficiency: Double?
    var completeness: SleepDataCompleteness

    init(_ session: SleepSession) {
        isNap = session.kind == .nap
        night = session.night
        bedtime = session.bedtime
        wakeTime = session.wakeTime
        timeZone = session.timeZone.identifier
        totals = session.totals
        awakenings = session.awakenings
        efficiency = session.efficiency
        completeness = session.completeness
    }

    var session: SleepSession {
        SleepSession(
            kind: isNap ? .nap : .main,
            night: night,
            bedtime: bedtime,
            wakeTime: wakeTime,
            timeZone: TimeZone(identifier: timeZone) ?? .current,
            timeline: [],
            totals: totals,
            awakenings: awakenings,
            efficiency: efficiency,
            completeness: completeness,
            sourceName: ""
        )
    }
}
