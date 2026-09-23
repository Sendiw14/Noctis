// DEBUG only: the mock's synthetic nights must never compile into a Release build.
#if DEBUG
import Foundation

/// One synthetic night: internally consistent so sleep quality, resting HR,
/// HRV and respiration all move together the way they would for a real body,
/// and so a 120-night history reads as a believable, slowly-improving trend.
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
}

enum MockNightGenerator {
    private static let sourceName = "Apple Watch (Simulated)"
    private static let bundleID = "com.noctis.mock"

    static func generate(seed: UInt64, count: Int, referenceDate: Date, calendar: Calendar) -> [NightProfile] {
        let anchorDay = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate)

        return (0..<count).map { i in
            let dayOffset = count - 1 - i
            let nightDay = calendar.date(byAdding: .day, value: -dayOffset, to: anchorDay) ?? anchorDay
            return generateNight(index: i, total: count, day: nightDay, seed: seed, calendar: calendar)
        }
    }

    private static func generateNight(index: Int, total: Int, day: Date, seed: UInt64, calendar: Calendar) -> NightProfile {
        var rng = SeededGenerator(seed: seed &+ UInt64(index) &* 0x9E3779B1)

        let weekday = calendar.component(.weekday, from: day)
        let isWeekend = weekday == 1 || weekday == 7

        let progress = Double(index) / Double(max(total - 1, 1))
        let trend = 0.42 + 0.28 * progress
        let noise = Double.random(in: -0.16...0.16, using: &rng)
        let quality = min(max(trend + noise, 0.12), 0.97)

        let bedtimeHourBase = isWeekend ? 23.6 : 23.0
        let bedtimeJitter = Double.random(in: -35...35, using: &rng)
        let bedtime = day.addingTimeInterval(bedtimeHourBase * 3600 + bedtimeJitter * 60)

        let totalSleepHours = 6.4 + quality * 2.1 + Double.random(in: -0.25...0.25, using: &rng)
        let totalSleepSeconds = totalSleepHours * 3600

        let latencyMinutes = Double.random(in: 3...16, using: &rng) * (1.3 - quality)
        let sleepOnset = bedtime.addingTimeInterval(latencyMinutes * 60)

        var cycleSegments: [(SleepStageValue, TimeInterval)] = []
        let cycleCount = min(max(Int((totalSleepHours / 1.5).rounded()), 4), 6)
        let baseCycleLength = totalSleepSeconds / Double(cycleCount)

        for cycle in 0..<cycleCount {
            let earlyBias = Double(cycleCount - cycle) / Double(cycleCount)
            let lateBias = Double(cycle + 1) / Double(cycleCount)
            let cycleDuration = baseCycleLength * Double.random(in: 0.86...1.14, using: &rng)

            let deepShare = max(0, 0.30 * earlyBias - 0.06) * (0.55 + 0.45 * quality)
            let remShare = (0.12 + 0.24 * lateBias) * (0.65 + 0.35 * quality)
            let coreShare = max(0.34, 1 - deepShare - remShare)

            let coreFirst = cycleDuration * coreShare * 0.55
            let deepDuration = cycleDuration * deepShare
            let coreSecond = cycleDuration * coreShare * 0.45
            let remDuration = cycleDuration * remShare

            cycleSegments.append((.core, coreFirst))
            if deepDuration > 60 { cycleSegments.append((.deep, deepDuration)) }
            cycleSegments.append((.core, coreSecond))
            if remDuration > 60 { cycleSegments.append((.rem, remDuration)) }

            let awakeChance = (1 - quality) * 0.45
            if Double.random(in: 0...1, using: &rng) < awakeChance {
                cycleSegments.append((.awake, Double.random(in: 60...240, using: &rng)))
            }
        }

        var cursor = sleepOnset
        var sleepSamples: [RawSleepSample] = [
            RawSleepSample(start: bedtime, end: sleepOnset, stage: .awake, sourceName: sourceName, sourceBundleID: bundleID),
        ]
        for (stage, duration) in cycleSegments {
            let end = cursor.addingTimeInterval(duration)
            sleepSamples.append(RawSleepSample(start: cursor, end: end, stage: stage, sourceName: sourceName, sourceBundleID: bundleID))
            cursor = end
        }
        let wakeTime = cursor

        let restingBaseline = 61.0 - 7.0 * progress
        let restingHR = restingBaseline - quality * 3.0 + Double.random(in: -1.5...1.5, using: &rng)
        let restingSample = HeartRateSample(date: wakeTime, bpm: restingHR.rounded(), sourceName: sourceName)

        var heartRateSamples: [HeartRateSample] = []
        var hrCursor = bedtime
        while hrCursor < wakeTime {
            let stageAtCursor = sleepSamples.first { $0.start <= hrCursor && hrCursor < $0.end }?.stage ?? .core
            let stageOffset: Double = switch stageAtCursor {
            case .deep: -6
            case .rem: 3
            case .awake: 8
            default: 0
            }
            let bpm = restingHR + stageOffset + Double.random(in: -2.5...2.5, using: &rng)
            heartRateSamples.append(HeartRateSample(date: hrCursor, bpm: max(bpm, 40).rounded(), sourceName: sourceName))
            hrCursor = hrCursor.addingTimeInterval(Double.random(in: 480...720, using: &rng))
        }

        let hrvBaseline = 44.0 + 22.0 * progress
        let hrv = hrvBaseline + quality * 9.0 + Double.random(in: -5...5, using: &rng)
        let hrvSamples = [HRVSample(date: wakeTime, sdnnMilliseconds: max(hrv, 15).rounded())]

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
