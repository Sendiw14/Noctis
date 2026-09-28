// DEBUG only: the mock's synthetic nights must never compile into a Release build.
#if DEBUG
import Foundation

/// One synthetic night: internally consistent so sleep quality, resting HR,
/// HRV and respiration all move together the way they would for a real body,
/// and so a long history reads as a believable, slowly-improving trend.
struct NightProfile: Sendable {
    let date: Date
    let bedtime: Date
    let wakeTime: Date
    let sleepSamples: [RawSleepSample]
    let heartRateSamples: [HeartRateSample]
    let restingHeartRate: HeartRateSample
    let hrvSamples: [HRVSample]
    let respiratorySamples: [RespiratoryRateSample]
    let qualityFactor: Double

    var asleepSeconds: TimeInterval {
        sleepSamples.filter(\.stage.isAsleep).reduce(0) { $0 + $1.duration }
    }
}

/// How the last night departs from the ones before it, so the mock's
/// baselines have something to compare.
struct LastNightOverride {
    /// Hours after the evening's midnight (23.9 = 11:54 PM).
    let bedtimeHour: Double
    let asleepHours: Double
    let quality: Double
}

/// How the mock's last night relates to the nights before it, which
/// decides the insight Home shows.
enum MockLastNight {
    /// 55 minutes later and 70 minutes shorter: the duration shift wins.
    case laterAndShorter
    /// 55 minutes later, the usual length: a bedtime shift.
    case later
    /// A steady sleeper whose last night is on the usual: a bedtime streak.
    case steady
}

enum MockNightGenerator {
    static let watchSource = "Apple Watch (Simulated)"
    static let watchBundleID = "com.noctis.mock.watch"
    static let phoneSource = "iPhone (Simulated)"
    static let phoneBundleID = "com.noctis.mock.iphone"

    /// Last night vs the 14 nights before it: 55 minutes later to bed and
    /// 70 minutes less sleep, so a baseline insight fires.
    static let lastNightBedtimeShiftMinutes: Double = 55
    static let lastNightDurationShiftMinutes: Double = -70

    /// `count` nights ending with last night. Last night is the night of
    /// yesterday's evening once it's 9 AM (so it has surely ended), or the
    /// evening before that earlier in the morning.
    static func generate(seed: UInt64, count: Int, referenceDate: Date, calendar: Calendar, lastNight: MockLastNight = .laterAndShorter) -> [NightProfile] {
        guard count > 0 else { return [] }
        let hour = calendar.component(.hour, from: referenceDate)
        let today = calendar.startOfDay(for: referenceDate)
        let lastDay = calendar.date(byAdding: .day, value: hour >= 9 ? -1 : -2, to: today) ?? today

        var nights: [NightProfile] = []
        for i in 0..<count {
            let dayOffset = count - 1 - i
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: lastDay) ?? lastDay
            var override: LastNightOverride?
            if i == count - 1, count > 1 {
                let previous = nights.suffix(14)
                let meanBedtimeHour = previous.map { $0.bedtime.timeIntervalSince(calendar.startOfDay(for: $0.date)) / 3600 }.reduce(0, +) / Double(previous.count)
                let meanAsleepHours = previous.map(\.asleepSeconds).reduce(0, +) / Double(previous.count) / 3600
                override = switch lastNight {
                case .laterAndShorter:
                    LastNightOverride(
                        bedtimeHour: meanBedtimeHour + lastNightBedtimeShiftMinutes / 60,
                        asleepHours: meanAsleepHours + lastNightDurationShiftMinutes / 60,
                        quality: 0.3
                    )
                case .later:
                    LastNightOverride(bedtimeHour: meanBedtimeHour + lastNightBedtimeShiftMinutes / 60, asleepHours: meanAsleepHours, quality: 0.55)
                case .steady:
                    LastNightOverride(bedtimeHour: meanBedtimeHour, asleepHours: meanAsleepHours, quality: 0.7)
                }
            }
            nights.append(generateNight(index: i, total: count, day: day, seed: seed, calendar: calendar, override: override, steady: lastNight == .steady))
        }
        return nights
    }

    /// Daytime heart rate every 15 minutes over the 48 hours before
    /// `referenceDate`, outside every night's sleep.
    static func daytimeHeartRate(referenceDate: Date, nights: [NightProfile], seed: UInt64) -> [HeartRateSample] {
        var rng = SeededGenerator(seed: seed &+ 0xDA7)
        var samples: [HeartRateSample] = []
        var cursor = referenceDate.addingTimeInterval(-48 * 3600)
        while cursor <= referenceDate {
            let asleep = nights.contains { $0.bedtime <= cursor && cursor <= $0.wakeTime }
            if !asleep {
                let bpm = Double.random(in: 66...84, using: &rng).rounded()
                samples.append(HeartRateSample(date: cursor, bpm: bpm, sourceName: watchSource))
            }
            cursor = cursor.addingTimeInterval(15 * 60)
        }
        return samples
    }

    private static func generateNight(index: Int, total: Int, day: Date, seed: UInt64, calendar: Calendar, override: LastNightOverride?, steady: Bool = false) -> NightProfile {
        var rng = SeededGenerator(seed: seed &+ UInt64(index) &* 0x9E3779B1)

        let weekday = calendar.component(.weekday, from: day)
        let isWeekend = weekday == 1 || weekday == 7

        let progress = Double(index) / Double(max(total - 1, 1))
        let trend = 0.42 + 0.28 * progress
        let noise = Double.random(in: -0.16...0.16, using: &rng)
        let quality = override?.quality ?? min(max(trend + noise, 0.12), 0.97)

        // A steady sleeper keeps weekends and weeknights within minutes.
        let bedtimeHourBase = isWeekend && !steady ? 23.6 : 23.0
        let bedtimeJitter = Double.random(in: -35...35, using: &rng) * (steady ? 0.25 : 1)
        let bedtimeHour = override?.bedtimeHour ?? bedtimeHourBase + bedtimeJitter / 60
        let bedtime = day.addingTimeInterval(bedtimeHour * 3600)

        let naturalSleepHours = 6.4 + quality * 2.1 + Double.random(in: -0.25...0.25, using: &rng)
        let totalSleepHours = override?.asleepHours ?? naturalSleepHours
        let totalSleepSeconds = totalSleepHours * 3600

        let latencyMinutes = Double.random(in: 3...16, using: &rng) * (1.3 - quality)
        let sleepOnset = bedtime.addingTimeInterval(latencyMinutes * 60)

        var cycleSegments: [(SleepStageValue, TimeInterval)] = []
        let cycleCount = min(max(Int((totalSleepHours / 1.5).rounded()), 4), 6)
        let baseCycleLength = totalSleepSeconds / Double(cycleCount)

        for cycle in 0..<cycleCount {
            let earlyBias = Double(cycleCount - cycle) / Double(cycleCount)
            let lateBias = Double(cycle + 1) / Double(cycleCount)
            // The last cycle absorbs the jitter so asleep time lands on target.
            let cycleDuration = cycle == cycleCount - 1
                ? max(totalSleepSeconds - cycleSegments.filter { $0.0.isAsleep }.reduce(0) { $0 + $1.1 }, 20 * 60)
                : baseCycleLength * Double.random(in: 0.86...1.14, using: &rng)

            let deepShare = max(0, 0.30 * earlyBias - 0.06) * (0.55 + 0.45 * quality)
            let remShare = (0.12 + 0.24 * lateBias) * (0.65 + 0.35 * quality)
            let coreShare = max(0.34, 1 - deepShare - remShare)
            let shareTotal = coreShare + deepShare + remShare

            let coreFirst = cycleDuration * coreShare / shareTotal * 0.55
            let deepDuration = cycleDuration * deepShare / shareTotal
            let coreSecond = cycleDuration * coreShare / shareTotal * 0.45
            let remDuration = cycleDuration * remShare / shareTotal

            cycleSegments.append((.core, coreFirst))
            if deepDuration > 60 { cycleSegments.append((.deep, deepDuration)) } else { cycleSegments.append((.core, deepDuration)) }
            cycleSegments.append((.core, coreSecond))
            if remDuration > 60 { cycleSegments.append((.rem, remDuration)) } else { cycleSegments.append((.core, remDuration)) }

            let awakeChance = (1 - quality) * 0.45
            if cycle < cycleCount - 1, Double.random(in: 0...1, using: &rng) < awakeChance {
                cycleSegments.append((.awake, Double.random(in: 60...240, using: &rng)))
            }
        }

        var cursor = sleepOnset
        var sleepSamples: [RawSleepSample] = [
            RawSleepSample(start: bedtime, end: sleepOnset, stage: .awake, sourceName: watchSource, sourceBundleID: watchBundleID),
        ]
        for (stage, duration) in cycleSegments {
            let end = cursor.addingTimeInterval(duration)
            sleepSamples.append(RawSleepSample(start: cursor, end: end, stage: stage, sourceName: watchSource, sourceBundleID: watchBundleID))
            cursor = end
        }
        let wakeTime = cursor

        // The iPhone's own in-bed estimate: a second, overlapping source.
        let inBedStart = bedtime.addingTimeInterval(-Double.random(in: 5...15, using: &rng) * 60)
        let inBedEnd = wakeTime.addingTimeInterval(Double.random(in: 3...12, using: &rng) * 60)
        sleepSamples.append(RawSleepSample(start: inBedStart, end: inBedEnd, stage: .inBed, sourceName: phoneSource, sourceBundleID: phoneBundleID))

        let restingBaseline = 61.0 - 7.0 * progress
        let restingHR = restingBaseline - quality * 3.0 + Double.random(in: -1.5...1.5, using: &rng)
        let restingSample = HeartRateSample(date: wakeTime.addingTimeInterval(25 * 60), bpm: restingHR.rounded(), sourceName: watchSource)

        var heartRateSamples: [HeartRateSample] = []
        var hrCursor = bedtime
        while hrCursor < wakeTime {
            let stageAtCursor = sleepSamples.first { $0.stage != .inBed && $0.start <= hrCursor && hrCursor < $0.end }?.stage ?? .core
            let stageOffset: Double = switch stageAtCursor {
            case .deep: -6
            case .rem: 3
            case .awake: 8
            default: 0
            }
            let bpm = restingHR + stageOffset + Double.random(in: -2.5...2.5, using: &rng)
            heartRateSamples.append(HeartRateSample(date: hrCursor, bpm: max(bpm, 40).rounded(), sourceName: watchSource))
            hrCursor = hrCursor.addingTimeInterval(Double.random(in: 480...720, using: &rng))
        }

        let hrvBaseline = 44.0 + 22.0 * progress
        let hrv = hrvBaseline + quality * 9.0 + Double.random(in: -5...5, using: &rng)
        let span = wakeTime.timeIntervalSince(sleepOnset)
        let hrvSamples = [0.2, 0.45, 0.7, 0.95].map { fraction in
            HRVSample(
                date: sleepOnset.addingTimeInterval(span * fraction),
                sdnnMilliseconds: max(hrv + Double.random(in: -6...6, using: &rng), 15).rounded()
            )
        }

        let respiratory = 14.2 + (1 - quality) * 1.1 + Double.random(in: -0.4...0.4, using: &rng)
        let respiratorySamples = [RespiratoryRateSample(date: wakeTime.addingTimeInterval(-1800), breathsPerMinute: (respiratory * 10).rounded() / 10)]

        return NightProfile(
            date: day,
            bedtime: bedtime,
            wakeTime: wakeTime,
            sleepSamples: sleepSamples,
            heartRateSamples: heartRateSamples,
            restingHeartRate: restingSample,
            hrvSamples: hrvSamples,
            respiratorySamples: respiratorySamples,
            qualityFactor: quality
        )
    }
}
#endif
