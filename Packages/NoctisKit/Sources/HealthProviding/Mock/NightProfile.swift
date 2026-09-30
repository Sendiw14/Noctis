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
    /// Use `MockNightGenerator.messySegments` for the night's stages.
    var messy = false
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
    /// Last night on the usual bedtime and length, for a history that isn't
    /// a steady sleeper's (so no baseline insight competes with its story).
    case usual
    /// A personal best: 1h 36m longer than usual, deep and restful, on the
    /// usual bedtime: the longest night, the best deep sleep and the
    /// highest recovery of the month.
    case best
    /// A restless night, for the sleep landscape: 11 awakenings (six of
    /// them under 3 minutes), uneven runs and a single 40-minute REM.
    case messy
}

/// How a whole history is shaped, for the insight scenarios. `standard` is
/// the original mock: nothing here may change it.
enum MockShape {
    case standard
    /// 90 nights whose bedtime swings ±80 minutes, and the earlier ones are
    /// the better ones: fewer awakenings and a higher HRV.
    case earlyBird
    /// Friday and Saturday evenings an hour later than the rest.
    case weekendShift
    /// HRV and resting heart rate off their usual for the last three nights.
    case hrvDip
    /// `full`: the standard history, and a last night with less deep and REM
    /// sleep than usual (nothing else about any night changes), so the stage
    /// insights have something to say beside the shifts.
    case fullStory
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
    /// How deep the recovery dip is on each of its four nights (0 = none),
    /// counted from the night `dipStartNightsBack` before the last.
    static let dipDepths: [Double] = [0.6, 1.0, 1.0, 0.7]
    static let dipStartNightsBack = 9
    /// The HRV dip runs to the last night.
    static let hrvDipDepths: [Double] = [1.0, 1.0, 1.0]
    static let hrvDipStartNightsBack = 3
    /// How much of its usual deep and REM sleep `full`'s last night keeps.
    static let fullLastNightDeepKept: Double = 0.5
    static let fullLastNightREMKept: Double = 0.7
    /// The early bird's bedtime swing (minutes either side of 11 PM), the
    /// difference in HRV a swing of one hour makes (ms) and the quality a
    /// swing of one hour takes off.
    static let earlyBirdSwingMinutes: Double = 80
    static let earlyBirdHRVPerHour: Double = 8
    static let earlyBirdQualityPerHour: Double = 0.30

    static func generate(
        seed: UInt64, count: Int, referenceDate: Date, calendar: Calendar, lastNight: MockLastNight = .laterAndShorter, dip: Bool = false,
        shape: MockShape = .standard
    ) -> [NightProfile] {
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
                case .steady, .usual:
                    LastNightOverride(bedtimeHour: meanBedtimeHour, asleepHours: meanAsleepHours, quality: 0.7)
                case .best:
                    LastNightOverride(bedtimeHour: meanBedtimeHour, asleepHours: meanAsleepHours + 1.6, quality: 1.0)
                case .messy:
                    LastNightOverride(bedtimeHour: meanBedtimeHour, asleepHours: meanAsleepHours, quality: 0.45, messy: true)
                }
            }
            // The dip: four nights, a week or so before the last.
            let depths = shape == .hrvDip ? hrvDipDepths : dipDepths
            let dipIndex = i - (count - (shape == .hrvDip ? hrvDipStartNightsBack : dipStartNightsBack))
            let depth = (dip || shape == .hrvDip) && depths.indices.contains(dipIndex) ? depths[dipIndex] : 0
            nights.append(generateNight(
                index: i, total: count, day: day, seed: seed, calendar: calendar, override: override, steady: lastNight == .steady, dip: depth,
                qualityCap: lastNight == .best ? 0.3 : nil, shape: shape
            ))
        }
        return nights
    }

    /// The messy night, in minutes: 11 awakenings (1, 2, 1.5, 2, 1 and
    /// 2.5 minutes are under 3), runs of every length, and one 40-minute
    /// REM. About 6h 55m asleep.
    static let messyMinutes: [(SleepStageValue, Double)] = [
        (.core, 22), (.deep, 30), (.core, 12), (.awake, 1), (.core, 18), (.rem, 9), (.core, 25), (.awake, 2),
        (.deep, 14), (.core, 10), (.rem, 40), (.awake, 5), (.core, 31), (.awake, 1.5), (.deep, 8), (.core, 20),
        (.awake, 3.5), (.rem, 16), (.core, 14), (.awake, 2), (.core, 27), (.deep, 6), (.awake, 7), (.core, 19),
        (.rem, 22), (.awake, 1), (.core, 24), (.awake, 4), (.rem, 12), (.core, 15), (.awake, 2.5), (.core, 21),
        (.awake, 9), (.core, 8),
    ]

    static var messySegments: [(SleepStageValue, TimeInterval)] {
        messyMinutes.map { ($0.0, $0.1 * 60) }
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

    private static func generateNight(
        index: Int, total: Int, day: Date, seed: UInt64, calendar: Calendar, override: LastNightOverride?, steady: Bool = false, dip: Double = 0, qualityCap: Double? = nil,
        shape: MockShape = .standard
    ) -> NightProfile {
        var rng = SeededGenerator(seed: seed &+ UInt64(index) &* 0x9E3779B1)

        let weekday = calendar.component(.weekday, from: day)
        let isWeekend = weekday == 1 || weekday == 7

        let progress = Double(index) / Double(max(total - 1, 1))
        let trend = 0.42 + 0.28 * progress
        let noise = Double.random(in: -0.16...0.16, using: &rng)
        let naturalQuality = min(max(trend + noise, 0.12), qualityCap ?? 0.97)

        // A steady sleeper keeps weekends and weeknights within minutes.
        // Fridays and Saturdays are the weekend the weekend-shift scenario moves.
        let isWeekendEvening = weekday == 6 || weekday == 7
        var bedtimeHourBase = isWeekend && !steady ? 23.6 : 23.0
        var bedtimeJitter = Double.random(in: -35...35, using: &rng) * (steady ? 0.25 : 1)
        switch shape {
        case .earlyBird:
            bedtimeHourBase = 23.0
            bedtimeJitter *= earlyBirdSwingMinutes / 35
        case .weekendShift:
            bedtimeHourBase = isWeekendEvening ? 24.0 : 23.0
            bedtimeJitter *= 0.6
        case .standard, .hrvDip, .fullStory:
            break
        }
        let bedtimeHour = override?.bedtimeHour ?? bedtimeHourBase + bedtimeJitter / 60 + dip * 50 / 60
        // How many hours later than 11 PM the night began (the early bird's story).
        let lateness = bedtimeHour - 23.0
        var quality = override?.quality ?? (dip > 0 ? naturalQuality * (1 - 0.8 * dip) : naturalQuality)
        if shape == .earlyBird, override == nil {
            quality = min(max(0.62 - earlyBirdQualityPerHour * lateness + noise * 0.4, 0.15), 0.97)
        }
        let bedtime = day.addingTimeInterval(bedtimeHour * 3600)

        let naturalSleepHours = 6.4 + quality * 2.1 + Double.random(in: -0.25...0.25, using: &rng)
        let totalSleepHours = override?.asleepHours ?? naturalSleepHours
        let totalSleepSeconds = totalSleepHours * 3600

        // The restless night falls asleep at once: its 11 awakenings are the
        // ones it lists, not one more at the start.
        let latencyMinutes = override?.messy == true ? 0 : Double.random(in: 3...16, using: &rng) * (1.3 - quality)
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

            var deepShare = max(0, 0.30 * earlyBias - 0.06) * (0.55 + 0.45 * quality)
            var remShare = (0.12 + 0.24 * lateBias) * (0.65 + 0.35 * quality)
            if shape == .fullStory, override != nil {
                deepShare *= fullLastNightDeepKept
                remShare *= fullLastNightREMKept
            }
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
            // The early bird's late nights are broken ones: up to six more
            // awakenings of a few minutes, each between stretches of sleep.
            if shape == .earlyBird, override == nil, cycle < cycleCount - 1 {
                let extra = Int((max(lateness, 0) * 6).rounded(.up))
                let share = (extra + cycleCount - 2) / max(cycleCount - 1, 1)
                for _ in 0..<share {
                    cycleSegments.append((.awake, Double.random(in: 180...300, using: &rng)))
                    cycleSegments.append((.core, 8 * 60))
                }
            }
        }

        // The restless night: its own stages, whatever the cycles said.
        if override?.messy == true { cycleSegments = Self.messySegments }

        var cursor = sleepOnset
        var sleepSamples: [RawSleepSample] = sleepOnset > bedtime
            ? [RawSleepSample(start: bedtime, end: sleepOnset, stage: .awake, sourceName: watchSource, sourceBundleID: watchBundleID)]
            : []
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
        let restingHR = restingBaseline - quality * 3.0 + Double.random(in: -1.5...1.5, using: &rng) + dip * 5
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
        var hrv = hrvBaseline + quality * 9.0 + Double.random(in: -5...5, using: &rng) - dip * 14
        if shape == .earlyBird, override == nil { hrv -= lateness * earlyBirdHRVPerHour }
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
