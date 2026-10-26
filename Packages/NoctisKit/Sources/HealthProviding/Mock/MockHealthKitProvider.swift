// DEBUG only: MockHealthKitProvider must never compile into a Release build.
#if DEBUG
import Foundation

/// The data situations the mock can simulate (`-mockScenario <name>`).
public enum MockScenario: String, Sendable, CaseIterable {
    /// 120 nights of sleep with HRV, resting and overnight heart rate.
    case full
    /// The same nights, but no HRV or heart rate of any kind.
    case sleepOnly
    /// Only the last 3 nights.
    case learning
    /// No Health data at all.
    case empty
    /// Nothing newer than 30 hours ago.
    case stale
    /// No data last night; today's daytime heart rate still arrives.
    case gap
    /// Like `full`, but last night was only later (a bedtime-shift insight).
    case lateBedtime
    /// Like `full`, but a steady sleeper on their usual (a streak insight).
    case steady
    /// Like `full`, but last night was restless: 11 awakenings, uneven
    /// runs and one 40-minute REM (the sleep landscape's stress test).
    case messyNight
    /// Like `full`, but a four-night dip a week ago (later, shorter,
    /// lower HRV, higher resting heart rate) and then back to usual: the
    /// Recovery charts' story.
    case recoveryDip
    /// Like `full`, but last night is the month's best: the longest night,
    /// the most deep sleep and the highest recovery (the highlights).
    case highs
    /// 90 nights whose bedtime swings an hour either way, and the earlier
    /// ones are the better ones: fewer awakenings and a higher HRV (the
    /// earlier-bedtime pattern insight).
    case earlyBird
    /// Like `full`, but Friday and Saturday nights run an hour later than
    /// the rest of the week (the weekend-shift insight).
    case weekendShift
    /// Like `full`, but HRV and resting heart rate are off their usual for
    /// the last three nights (the heart-signal insights).
    case hrvDip
    /// Only the last 6 nights: the Insights tab is still learning.
    case sparse
    /// 120 nights where nothing moves: every week alike, to the minute. The weekly review says it was a steady week (the reviews' `steadyWeek`).
    case steadyWeek
    /// Like `steadyWeek`, but the bedtimes before the latest review week were scattered an hour either way and that week's are tight (consistency tightens; the
    /// recovery model counts consistency, so recovery rises with it).
    case improvedWeek
    /// Like `steadyWeek`, but the latest review week's bedtimes (and so its wake times) are an hour later than every week before it.
    case laterWeek
    /// Like `full`, but the latest review week has only 4 nights: "4 of 5 nights".
    case sparseWeek
    /// Like `steadyWeek`, but each week of the previous calendar month differs from the others: the monthly review's story.
    case variedMonth
}

/// Development-only stand-in for a real HealthKit-backed provider. Clearly
/// separate type from anything that will ship reading real device data —
/// never wire this into a Release configuration.
///
/// Two sources, like a real iPhone + Apple Watch: the watch writes stages,
/// heart rate, HRV (several per night) and resting heart rate; the iPhone
/// writes an overlapping in-bed sample.
public final class MockHealthKitProvider: HealthDataProviding {
    public let isHealthDataAvailable: Bool
    public let sourceName = "Apple Watch (Simulated)"
    public let scenario: MockScenario

    private var status: HealthAuthorizationStatus
    private let sleep: [RawSleepSample]
    private let heartRate: [HeartRateSample]
    private let resting: [HeartRateSample]
    private let hrv: [HRVSample]
    private let respiratory: [RespiratoryRateSample]
    /// Debug-only failure injection — Plan's build checklist needs a way to
    /// exercise its genuine-failure branch (distinct from "no permission"/
    /// "no data") in the simulator, where the mock otherwise never fails a
    /// query once authorized.
    private let failsQueries: Bool
    /// Debug-only delay on sleep queries, to hold Home on its skeleton.
    private let latency: Duration

    public init(
        scenario: MockScenario = .full,
        seed: UInt64 = 0x4E4F435449_53,
        historyDays: Int = 120,
        referenceDate: Date = .now,
        calendar: Calendar = .current,
        startAuthorized: Bool = false,
        isHealthDataAvailable: Bool = true,
        failsQueries: Bool = false,
        latency: Duration = .zero
    ) {
        self.scenario = scenario
        self.latency = latency
        self.status = startAuthorized ? .authorized : .notDetermined
        self.isHealthDataAvailable = isHealthDataAvailable
        self.failsQueries = failsQueries

        let lastNight: MockLastNight =
            switch scenario {
            case .lateBedtime: .later
            case .steady, .recoveryDip: .steady
            case .earlyBird, .weekendShift, .hrvDip, .steadyWeek, .improvedWeek, .laterWeek, .variedMonth: .usual
            case .messyNight: .messy
            case .highs: .best
            default: .laterAndShorter
            }
        let shape: MockShape =
            switch scenario {
            case .earlyBird: .earlyBird
            case .weekendShift: .weekendShift
            case .hrvDip: .hrvDip
            case .full: .fullStory
            case .steadyWeek: .steadyWeek
            case .improvedWeek: .improvedWeek
            case .laterWeek: .laterWeek
            case .variedMonth: .variedMonth
            default: .standard
            }
        // The early bird's story is 90 nights; the others keep the default.
        let historyDays = scenario == .earlyBird ? min(historyDays, 90) : historyDays
        let frame = MockReviewFrame(referenceDate: referenceDate, calendar: calendar)
        let generated = MockNightGenerator.generate(
            seed: seed, count: historyDays, referenceDate: referenceDate, calendar: calendar, lastNight: lastNight,
            dip: scenario == .recoveryDip,
            shape: shape, frame: frame
        )
        let nights: [NightProfile] =
            switch scenario {
            case .full, .sleepOnly, .stale, .lateBedtime, .steady, .messyNight, .recoveryDip, .highs, .earlyBird, .weekendShift, .hrvDip, .steadyWeek,
                .improvedWeek, .laterWeek, .variedMonth:
                generated
            case .learning: Array(generated.suffix(3))
            case .sparse: Array(generated.suffix(6))
            case .empty: []
            case .gap: Array(generated.dropLast())
            // The latest review week keeps its 1st, 3rd, 5th and 7th nights.
            case .sparseWeek: generated.filter { night in frame.weeksBack(ofNight: night.date) != 0 || frame.dayOfWeek(ofNight: night.date) % 2 == 0 }
            }
        let daytime = scenario == .empty ? [] : MockNightGenerator.daytimeHeartRate(referenceDate: referenceDate, nights: generated, seed: seed)
        let hasHeartData = scenario != .sleepOnly
        // Stale: everything stops 30 hours before now.
        let cutoff = scenario == .stale ? referenceDate.addingTimeInterval(-30 * 3600) : referenceDate

        let allSleep = nights.flatMap(\.sleepSamples)
        sleep = scenario == .stale ? allSleep.filter { $0.end <= cutoff } : allSleep
        heartRate = hasHeartData ? (nights.flatMap(\.heartRateSamples) + daytime).filter { $0.date <= cutoff }.sorted { $0.date < $1.date } : []
        resting = hasHeartData ? nights.map(\.restingHeartRate).filter { $0.date <= cutoff } : []
        hrv = hasHeartData ? nights.flatMap(\.hrvSamples).filter { $0.date <= cutoff } : []
        respiratory = hasHeartData ? nights.flatMap(\.respiratorySamples).filter { $0.date <= cutoff } : []
    }

    public func authorizationStatus() async -> HealthAuthorizationStatus { status }

    public func requestAuthorization(for kinds: [HealthDataKind]) async -> HealthAuthorizationStatus {
        status = .authorized
        return status
    }

    public func fetchSleepSamples(from start: Date, to end: Date) async throws -> [RawSleepSample] {
        try requireAuthorized()
        if latency > .zero { try await Task.sleep(for: latency) }
        if failsQueries { throw HealthProviderError.queryFailed }
        return sleep.filter { $0.start < end && $0.end > start }
    }

    public func fetchHeartRateSamples(from start: Date, to end: Date) async throws -> [HeartRateSample] {
        try requireAuthorized()
        return heartRate.filter { $0.date >= start && $0.date <= end }
    }

    public func fetchRestingHeartRate(from start: Date, to end: Date) async throws -> [HeartRateSample] {
        try requireAuthorized()
        return resting.filter { $0.date >= start && $0.date <= end }
    }

    public func fetchHRVSamples(from start: Date, to end: Date) async throws -> [HRVSample] {
        try requireAuthorized()
        return hrv.filter { $0.date >= start && $0.date <= end }
    }

    public func fetchRespiratorySamples(from start: Date, to end: Date) async throws -> [RespiratoryRateSample] {
        try requireAuthorized()
        return respiratory.filter { $0.date >= start && $0.date <= end }
    }

    /// The mock's data never changes after launch.
    public func sampleChanges() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    // MARK: Background delivery (a script, for tests and DEBUG runs)

    /// How many times background delivery was started and stopped, and the handler it was given.
    public private(set) var backgroundStarts = 0
    public private(set) var backgroundStops = 0
    private var wakeHandler: (@Sendable (_ done: @escaping @Sendable () -> Void) -> Void)?

    /// Plays one delivery from Apple Health: calls the handler with `done`, as HealthKit would. False when delivery is not started.
    @discardableResult
    public func simulateWake(done: @escaping @Sendable () -> Void) -> Bool {
        guard let wakeHandler else { return false }
        wakeHandler(done)
        return true
    }

    private func requireAuthorized() throws {
        guard status == .authorized else { throw HealthProviderError.unauthorized }
    }
}

extension MockHealthKitProvider: HealthBackgroundDelivering {
    public func startBackgroundDelivery(wake: @escaping @Sendable (_ done: @escaping @Sendable () -> Void) -> Void) async {
        backgroundStarts += 1
        wakeHandler = wake
    }

    public func stopBackgroundDelivery() async {
        backgroundStops += 1
        wakeHandler = nil
    }
}
#endif
