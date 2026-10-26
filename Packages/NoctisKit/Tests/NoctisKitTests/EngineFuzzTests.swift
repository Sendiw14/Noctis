import Foundation
import Testing

@testable import HealthProviding
@testable import NightKit
@testable import NoctisCore
@testable import RecoveryKit
@testable import SleepAnalysisKit
@testable import SleepKit

// QA part 3, step 2: seeded property tests over the sleep, quality, recovery and bedtime engines.
// The seed is fixed (CI) unless NOCTIS_FUZZ_SEED is set; NOCTIS_FUZZ_CASES sets how many random timelines run (default 1500).
// A failure prints the seed, the case and the smallest sample list that still fails, as a Swift literal to paste into a fixture.

/// SplitMix64: the same sequence for the same seed on every platform.
struct FuzzRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum FuzzConfig {
    static let seed: UInt64 = UInt64(ProcessInfo.processInfo.environment["NOCTIS_FUZZ_SEED"] ?? "") ?? 20_260_924
    static let cases: Int = Int(ProcessInfo.processInfo.environment["NOCTIS_FUZZ_CASES"] ?? "") ?? 1500
}

/// One random multi-night timeline and the clock it is read at.
struct FuzzTimeline {
    var samples: [RawSleepSample]
    var now: Date
    var timeZone: TimeZone

    static let zones = ["America/New_York", "Europe/London", "Australia/Sydney", "Australia/Lord_Howe", "Asia/Tokyo", "Pacific/Auckland"]
        .compactMap(TimeZone.init(identifier:))
    /// Weeks around spring-forward and fall-back in the northern and southern hemispheres, and a plain month.
    static let anchors: [DateComponents] = [
        .init(year: 2026, month: 3, day: 1), .init(year: 2026, month: 3, day: 22), .init(year: 2026, month: 9, day: 20),
        .init(year: 2026, month: 10, day: 25), .init(year: 2026, month: 4, day: 1), .init(year: 2026, month: 6, day: 10),
    ]

    static func make(_ rng: inout FuzzRandom) -> FuzzTimeline {
        let zone = zones.randomElement(using: &rng)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let anchor = calendar.date(from: anchors.randomElement(using: &rng)!)!
        let nights = Int.random(in: 1...12, using: &rng)
        var samples: [RawSleepSample] = []
        let sources = [("Watch", "com.apple.health.watch"), ("Phone", "com.apple.health.phone"), ("Ring", "com.example.ring")]

        func add(_ start: Date, _ end: Date, _ stage: SleepStageValue, _ source: (String, String), tz: TimeZone? = nil) {
            samples.append(RawSleepSample(start: start, end: end, stage: stage, sourceName: source.0, sourceBundleID: source.1, timeZone: tz))
        }

        for index in 0..<nights {
            let day = calendar.date(byAdding: .day, value: index, to: anchor)!
            let bedtime = day.addingTimeInterval(Double(Int.random(in: 19 * 60...(26 * 60), using: &rng)) * 60)
            let source = sources.randomElement(using: &rng)!
            let tz: TimeZone? = Int.random(in: 0..<6, using: &rng) == 0 ? zones.randomElement(using: &rng) : nil
            switch Int.random(in: 0..<14, using: &rng) {
            case 0:  // in-bed only
                add(bedtime, bedtime.addingTimeInterval(Double(Int.random(in: 4...10, using: &rng)) * 3600), .inBed, source, tz: tz)
            case 1:  // unspecified only
                add(bedtime, bedtime.addingTimeInterval(Double(Int.random(in: 3...10, using: &rng)) * 3600), .unspecified, source, tz: tz)
            case 2:  // a nap
                let nap = day.addingTimeInterval(Double(Int.random(in: 12...17, using: &rng)) * 3600)
                add(nap, nap.addingTimeInterval(Double(Int.random(in: 10...100, using: &rng)) * 60), .core, source, tz: tz)
            case 3:  // zero and negative durations, and a very long one
                add(bedtime, bedtime, .core, source)
                add(bedtime.addingTimeInterval(600), bedtime, .deep, source)
                add(bedtime, bedtime.addingTimeInterval(Double(Int.random(in: 25...40, using: &rng)) * 3600), .core, source, tz: tz)
            default:  // a staged night with awakenings, gaps, overlaps and duplicates
                var cursor = bedtime
                let length = Double(Int.random(in: 120...660, using: &rng)) * 60
                let end = bedtime.addingTimeInterval(length)
                if Bool.random(using: &rng) { add(cursor, cursor.addingTimeInterval(Double(Int.random(in: 0...45, using: &rng)) * 60), .inBed, source, tz: tz) }
                while cursor < end {
                    let span = Double(Int.random(in: 1...120, using: &rng)) * 60
                    let stage = [SleepStageValue.core, .core, .deep, .rem, .awake, .unspecified].randomElement(using: &rng)!
                    let segmentEnd = min(cursor.addingTimeInterval(span), end)
                    add(cursor, segmentEnd, stage, source, tz: tz)
                    if Int.random(in: 0..<8, using: &rng) == 0 { add(cursor, segmentEnd, stage, source, tz: tz) }  // duplicate
                    if Int.random(in: 0..<10, using: &rng) == 0 {  // a second source overlaps
                        let other = sources.randomElement(using: &rng)!
                        add(cursor.addingTimeInterval(-300), segmentEnd.addingTimeInterval(300), .core, other, tz: tz)
                    }
                    if Int.random(in: 0..<10, using: &rng) == 0 {  // a gap, sometimes past the join gap
                        cursor = segmentEnd.addingTimeInterval(Double(Int.random(in: 1...150, using: &rng)) * 60)
                    } else {
                        cursor = segmentEnd
                    }
                }
            }
        }
        samples.shuffle(using: &rng)
        let lastDay = calendar.date(byAdding: .day, value: nights, to: anchor)!
        // The clock may fall mid-night, so a night can still be in progress; future samples are added beyond the join gap.
        let now = lastDay.addingTimeInterval(Double(Int.random(in: -12...30, using: &rng)) * 3600)
        return FuzzTimeline(samples: samples, now: now, timeZone: zone)
    }
}

/// Every property of the session engine; returns a description of each violation.
func sessionViolations(_ timeline: FuzzTimeline) -> [String] {
    var out: [String] = []
    let history = SleepSessionEngine.history(from: timeline.samples, asOf: timeline.now, timeZone: timeline.timeZone)
    let all = history.nights + history.naps
    for session in all {
        let t = session.totals
        let values = [t.asleep, t.inBed, t.awake, t.core, t.deep, t.rem, t.unspecified]
        if values.contains(where: { !$0.isFinite || $0 < 0 }) { out.append("non-finite or negative total in \(session.night)") }
        if session.wakeTime > timeline.now { out.append("wake after now in \(session.night)") }
        if session.wakeTime < session.bedtime { out.append("wake before bedtime in \(session.night)") }
        if session.completeness.hasInBedData, t.asleep > t.inBed + 0.5 { out.append("asleep \(t.asleep) > in bed \(t.inBed) in \(session.night)") }
        if let efficiency = session.efficiency, !(0...1).contains(efficiency) { out.append("efficiency \(efficiency)") }
        if !(0...1).contains(session.completeness.coverage) { out.append("coverage \(session.completeness.coverage)") }
        if t.asleep > t.inBed + 0.5 { out.append("asleep exceeds in-bed span in \(session.night)") }
        if t.core + t.deep + t.rem + t.unspecified > t.asleep + 0.5 { out.append("stage totals exceed asleep") }
        let sorted = session.timeline.sorted { $0.interval.start < $1.interval.start }
        for (a, b) in zip(sorted, sorted.dropFirst()) where b.interval.start < a.interval.end - 0.5 { out.append("overlapping segments in \(session.night)") }
    }
    if Set(history.nights.map(\.night)).count != history.nights.count { out.append("two main sleeps for one night") }
    // Deterministic, and independent of input order.
    let again = SleepSessionEngine.history(from: timeline.samples.reversed(), asOf: timeline.now, timeZone: timeline.timeZone)
    if again != history { out.append("history depends on input order") }
    // Idempotent under duplication.
    let doubled =
        timeline.samples
        + timeline.samples.map {
            RawSleepSample(start: $0.start, end: $0.end, stage: $0.stage, sourceName: $0.sourceName, sourceBundleID: $0.sourceBundleID, timeZone: $0.timeZone)
        }
    if SleepSessionEngine.history(from: doubled, asOf: timeline.now, timeZone: timeline.timeZone) != history {
        out.append("duplicating every sample changes the history")
    }
    // No lookahead: samples that start more than the join gap after now change nothing.
    let future = RawSleepSample(
        start: timeline.now.addingTimeInterval(4 * 3600), end: timeline.now.addingTimeInterval(12 * 3600), stage: .core, sourceName: "Watch",
        sourceBundleID: "com.apple.health.watch"
    )
    if SleepSessionEngine.history(from: timeline.samples + [future], asOf: timeline.now, timeZone: timeline.timeZone) != history {
        out.append("a future sample changes the history")
    }
    return out
}

/// Quality and recovery over the history the session engine built.
func scoreViolations(_ timeline: FuzzTimeline, rng: inout FuzzRandom) -> [String] {
    var out: [String] = []
    let history = SleepSessionEngine.history(from: timeline.samples, asOf: timeline.now, timeZone: timeline.timeZone)
    let need = Double(Int.random(in: 300...600, using: &rng))
    let series = SleepQualityEngine.series(history: history.nights, needMinutes: need)
    if series != SleepQualityEngine.series(history: history.nights, needMinutes: need) { out.append("quality series not deterministic") }
    for result in series {
        if !(0...100).contains(result.score) { out.append("quality score \(result.score)") }
        if result.factors.contains(where: { !(0...100).contains($0.score) || !$0.weight.isFinite }) { out.append("quality factor out of range") }
        let sum = result.factors.reduce(0) { $0 + $1.weight }
        if !result.factors.isEmpty, abs(sum - 1) > 1e-9 { out.append("quality weights sum \(sum)") }
        if let usual = result.usual, !usual.isFinite || !(0...100).contains(usual) { out.append("quality usual \(usual)") }
    }

    // Recovery from the same nights, with random heart data (some missing, some extreme).
    let metrics: [NightMetrics] = history.nights.map { session in
        NightMetrics(
            night: session.night, wakeTime: session.wakeTime, asleepMinutes: session.totals.asleep / 60,
            bedtimeMinutes: session.bedtimeMinutesAfterNoon, wakeMinutes: session.wakeMinutesAfterNoon,
            hrv: Int.random(in: 0..<5, using: &rng) == 0 ? nil : Double.random(in: 0...400, using: &rng),
            restingHeartRate: Int.random(in: 0..<5, using: &rng) == 0 ? nil : Double.random(in: 0...250, using: &rng)
        )
    }
    let state = RecoveryEngine.evaluate(history: metrics, needMinutes: need, asOf: timeline.now)
    if state != RecoveryEngine.evaluate(history: metrics, needMinutes: need, asOf: timeline.now) { out.append("recovery not deterministic") }
    if case .scored(let result) = state {
        if !(0...100).contains(result.score) { out.append("recovery score \(result.score)") }
        if result.factors.contains(where: { !(0...100).contains($0.score) || !$0.weight.isFinite || !$0.value.isFinite }) {
            out.append("recovery factor out of range")
        }
        let sum = result.factors.reduce(0) { $0 + $1.weight }
        if abs(sum - 1) > 1e-9 { out.append("recovery weights sum \(sum)") }
    }
    // No lookahead: nights that end after now change nothing.
    let later = NightMetrics(
        night: SleepNightKey(containing: timeline.now.addingTimeInterval(86_400), in: timeline.timeZone), wakeTime: timeline.now.addingTimeInterval(90_000),
        asleepMinutes: 480, bedtimeMinutes: 660, wakeMinutes: 1140, hrv: 80, restingHeartRate: 50
    )
    if RecoveryEngine.evaluate(history: metrics + [later], needMinutes: need, asOf: timeline.now) != state {
        out.append("recovery reads a night that has not ended")
    }
    for (_, score) in RecoveryEngine.nightlyScores(history: metrics, nights: metrics.map(\.night), needMinutes: need, asOf: timeline.now)
    where !(0...100).contains(score) {
        out.append("nightly score \(score)")
    }
    return out
}

/// Removes samples while the violation persists, to the smallest list that still fails.
func shrink(_ timeline: FuzzTimeline, fails: (FuzzTimeline) -> Bool) -> FuzzTimeline {
    var current = timeline
    var chunk = max(current.samples.count / 2, 1)
    while chunk >= 1 {
        var index = 0
        while index < current.samples.count {
            var candidate = current
            candidate.samples.removeSubrange(index..<min(index + chunk, candidate.samples.count))
            if fails(candidate) { current = candidate } else { index += chunk }
        }
        chunk /= 2
    }
    return current
}

func literal(_ timeline: FuzzTimeline) -> String {
    let lines = timeline.samples.sorted { $0.start < $1.start }.map {
        "  sample(\($0.start.timeIntervalSince1970), \($0.end.timeIntervalSince1970), .\($0.stage.rawValue), source: \"\($0.sourceName)\", tz: \($0.timeZone?.identifier ?? "nil"))"
    }
    return "now \(timeline.now.timeIntervalSince1970) zone \(timeline.timeZone.identifier)\n" + lines.joined(separator: "\n")
}

struct EngineFuzzTests {
    @Test func sessionEngineHoldsItsInvariantsOnRandomTimelines() {
        var rng = FuzzRandom(seed: FuzzConfig.seed)
        var failures = 0
        var withNights = 0
        for index in 0..<FuzzConfig.cases {
            let timeline = FuzzTimeline.make(&rng)
            if !SleepSessionEngine.history(from: timeline.samples, asOf: timeline.now, timeZone: timeline.timeZone).nights.isEmpty { withNights += 1 }
            let violations = sessionViolations(timeline)
            guard !violations.isEmpty, failures < 3 else { continue }
            failures += 1
            let small = shrink(timeline) { !sessionViolations($0).isEmpty }
            Issue.record("seed \(FuzzConfig.seed) case \(index): \(Set(sessionViolations(small)).sorted())\n\(literal(small))")
        }
        // The generator must produce nights, or the invariants hold over nothing.
        #expect(withNights * 2 > FuzzConfig.cases, "only \(withNights) of \(FuzzConfig.cases) timelines had a main sleep")
    }

    @Test func qualityAndRecoveryHoldTheirInvariantsOnRandomTimelines() {
        var rng = FuzzRandom(seed: FuzzConfig.seed &+ 1)
        var failures = 0
        for index in 0..<FuzzConfig.cases / 3 {
            let timeline = FuzzTimeline.make(&rng)
            var copy = rng
            let violations = scoreViolations(timeline, rng: &copy)
            _ = rng.next()
            guard !violations.isEmpty, failures < 3 else { continue }
            failures += 1
            Issue.record("seed \(FuzzConfig.seed &+ 1) case \(index): \(Set(violations).sorted())")
        }
    }

    @Test func moreSleepNeverLowersTheDurationScore() {
        var rng = FuzzRandom(seed: FuzzConfig.seed &+ 2)
        for _ in 0..<FuzzConfig.cases {
            let need = Double(Int.random(in: 240...720, using: &rng))
            let night = Fixture.date(2026, 9, 20, 23)
            func score(hours: Double) -> Int {
                let session = SleepSessionEngine.history(
                    from: [Fixture.sample(night, night.addingTimeInterval(hours * 3600))], asOf: night.addingTimeInterval(20 * 3600), timeZone: Fixture.newYork
                ).nights
                return SleepQualityEngine.score(night: session[0], history: session, needMinutes: need).factor(.duration)?.score ?? -1
            }
            let a = Double.random(in: 3.1...9, using: &rng)
            let b = a + Double.random(in: 0...3, using: &rng)
            #expect(score(hours: a) <= score(hours: b), "need \(need): \(a) h scored above \(b) h")
        }
    }

    @Test func bedtimeStaysNearWakeMinusNeed() {
        var rng = FuzzRandom(seed: FuzzConfig.seed &+ 3)
        for _ in 0..<FuzzConfig.cases * 4 {
            let usual: Int? = Bool.random(using: &rng) ? Int.random(in: 0..<1440, using: &rng) : nil
            let inputs = BedtimeInputs(
                wakeMinutes: Int.random(in: -3000...3000, using: &rng), needMinutes: Int.random(in: 240...720, using: &rng),
                balanceMinutes: Bool.random(using: &rng) ? Double.random(in: -600...600, using: &rng) : nil, usualBedtimeMinutes: usual,
                bedtimeSpreadMinutes: Bool.random(using: &rng) ? Double.random(in: 0...300, using: &rng) : nil,
                nights: Int.random(in: 0...14, using: &rng), clockChangeMinutes: [-60, 0, 0, 60].randomElement(using: &rng)!
            )
            let result = BedtimeRecommendationEngine.recommend(inputs)
            let target = BedtimeClock.wrap(inputs.wakeMinutes - inputs.needMinutes - inputs.clockChangeMinutes)
            #expect((0..<1440).contains(result.centerMinutes))
            #expect(result.expectedSleepMinutes >= 0 && result.expectedSleepMinutes <= 1440 + 60)
            if let window = result.window { #expect(window.lengthMinutes <= 60, "window \(window)") }
            if inputs.usualBedtimeMinutes == nil || result.kind == .single {
                #expect(
                    abs(BedtimeClock.signedDistance(from: target, to: result.centerMinutes)) <= 30,
                    "center \(result.centerMinutes) target \(target) inputs \(inputs)")
            } else if let usual = inputs.usualBedtimeMinutes {
                let toUsual = abs(BedtimeClock.signedDistance(from: usual, to: result.centerMinutes))
                let targetToUsual = abs(BedtimeClock.signedDistance(from: usual, to: target))
                #expect(toUsual <= max(45, targetToUsual), "center \(result.centerMinutes) usual \(usual) target \(target)")
            }
        }
    }
}
