import Foundation
import Testing
@testable import HealthProviding

struct SourceResolverTests {
    private let reference = Date(timeIntervalSince1970: 1_700_000_000)

    private func sleepSample(start: TimeInterval, end: TimeInterval, source: String, bundleID: String, stage: SleepStageValue = .core) -> RawSleepSample {
        RawSleepSample(
            start: reference.addingTimeInterval(start),
            end: reference.addingTimeInterval(end),
            stage: stage,
            sourceName: source,
            sourceBundleID: bundleID
        )
    }

    private func heartRateSample(at offset: TimeInterval, bpm: Double, source: String) -> HeartRateSample {
        HeartRateSample(date: reference.addingTimeInterval(offset), bpm: bpm, sourceName: source)
    }

    // MARK: - Single source (today's real-world case: MockHealthKitProvider)

    @Test func singleSourceNonOverlappingSamplesPassThroughUnchanged() {
        let samples = [
            sleepSample(start: 0, end: 3600, source: "Watch", bundleID: "com.apple.health"),
            sleepSample(start: 3600, end: 7200, source: "Watch", bundleID: "com.apple.health"),
        ]
        let resolved = DefaultSourceResolver().resolveSleepSamples(samples)
        #expect(resolved.count == 2)
        #expect(resolved.map(\.id) == samples.map(\.id))
    }

    /// Regression guard: `DateInterval.intersects` treats touching endpoints
    /// as overlapping, and every real night is built from segments that
    /// touch exactly this way (Core ends the instant Deep begins). A naive
    /// `intersects`-based overlap check would wrongly discard nearly an
    /// entire night's worth of same-source samples.
    @Test func backToBackSegmentsWithinOneNightAreAllKept() {
        let segments = [
            sleepSample(start: 0, end: 2700, source: "Watch", bundleID: "com.apple.health", stage: .core),
            sleepSample(start: 2700, end: 4200, source: "Watch", bundleID: "com.apple.health", stage: .deep),
            sleepSample(start: 4200, end: 7200, source: "Watch", bundleID: "com.apple.health", stage: .core),
            sleepSample(start: 7200, end: 8700, source: "Watch", bundleID: "com.apple.health", stage: .rem),
        ]
        let resolved = DefaultSourceResolver().resolveSleepSamples(segments)
        #expect(resolved.count == segments.count)
    }

    @Test func emptyAndSingleSampleInputsAreUnaffected() {
        let resolver = DefaultSourceResolver()
        #expect(resolver.resolveSleepSamples([]).isEmpty)

        let one = [sleepSample(start: 0, end: 3600, source: "Watch", bundleID: "com.apple.health")]
        #expect(resolver.resolveSleepSamples(one).count == 1)
    }

    // MARK: - Exact duplicates

    @Test func exactDuplicateSleepSamplesAreRemoved() {
        let sample = sleepSample(start: 0, end: 3600, source: "Watch", bundleID: "com.apple.health")
        let duplicate = RawSleepSample(start: sample.start, end: sample.end, stage: sample.stage, sourceName: sample.sourceName, sourceBundleID: sample.sourceBundleID)
        let resolved = DefaultSourceResolver().resolveSleepSamples([sample, duplicate])
        #expect(resolved.count == 1)
    }

    @Test func exactDuplicateHeartRateSamplesAreRemoved() {
        let sample = heartRateSample(at: 0, bpm: 58, source: "Watch")
        let duplicate = HeartRateSample(date: sample.date, bpm: sample.bpm, sourceName: sample.sourceName)
        let resolved = DefaultSourceResolver().resolveHeartRateSamples([sample, duplicate])
        #expect(resolved.count == 1)
    }

    // MARK: - Multi-source overlap (future capability, tested now)

    @Test func higherPrioritySourceWinsOverlappingSleepRange() {
        let watch = SourceIdentity(name: "Watch", bundleID: "com.apple.health")
        let priority = SourcePriority(orderedHighestFirst: [watch])
        let resolver = DefaultSourceResolver(priority: priority)

        let watchSample = sleepSample(start: 0, end: 28_800, source: "Watch", bundleID: "com.apple.health")
        let thirdPartySample = sleepSample(start: 3600, end: 32_400, source: "ThirdPartyApp", bundleID: "com.example.sleep")

        let resolved = resolver.resolveSleepSamples([thirdPartySample, watchSample])

        #expect(resolved.count == 1)
        #expect(resolved.first?.sourceName == "Watch")
    }

    @Test func nonOverlappingSamplesFromDifferentSourcesAreBothKept() {
        let watch = SourceIdentity(name: "Watch", bundleID: "com.apple.health")
        let priority = SourcePriority(orderedHighestFirst: [watch])
        let resolver = DefaultSourceResolver(priority: priority)

        let watchSample = sleepSample(start: 0, end: 3600, source: "Watch", bundleID: "com.apple.health")
        let thirdPartySample = sleepSample(start: 7200, end: 10_800, source: "ThirdPartyApp", bundleID: "com.example.sleep")

        let resolved = resolver.resolveSleepSamples([thirdPartySample, watchSample])

        #expect(resolved.count == 2)
    }

    @Test func unrankedSourcesTieBreakDeterministicallyByName() {
        // Neither source is in the priority list, so both rank 0 — the
        // resolver must still produce a stable, repeatable answer.
        let sampleA = sleepSample(start: 0, end: 3600, source: "AppOne", bundleID: "com.example.one")
        let sampleB = sleepSample(start: 1800, end: 5400, source: "AppTwo", bundleID: "com.example.two")

        let first = DefaultSourceResolver().resolveSleepSamples([sampleA, sampleB])
        let second = DefaultSourceResolver().resolveSleepSamples([sampleB, sampleA])

        #expect(first.count == 1)
        #expect(second.count == 1)
        #expect(first.first?.sourceName == second.first?.sourceName)
        // "AppOne" sorts before "AppTwo" — alphabetical tie-break wins.
        #expect(first.first?.sourceName == "AppOne")
    }

    @Test func overlappingSamplesFromTheSameSourceAreTrimmedNotDropped() {
        let first = sleepSample(start: 0, end: 3600, source: "Watch", bundleID: "com.example.watch")
        let second = sleepSample(start: 1800, end: 5400, source: "Watch", bundleID: "com.example.watch", stage: .deep)
        let resolved = DefaultSourceResolver().resolveSleepSamples([first, second])
        #expect(resolved.count == 2)
        #expect(resolved[1].start == first.end)
        #expect(resolved[1].end == second.end)
        #expect(resolved.reduce(0) { $0 + $1.duration } == 5400)
    }

    @Test func unrankedTiesGoToTheSourceWithMoreStagedSamples() {
        let staged = [
            sleepSample(start: 0, end: 1800, source: "ZWatch", bundleID: "com.example.z", stage: .core),
            sleepSample(start: 1800, end: 3600, source: "ZWatch", bundleID: "com.example.z", stage: .deep),
        ]
        let unstaged = sleepSample(start: 0, end: 3600, source: "AApp", bundleID: "com.example.a", stage: .unspecified)
        let resolved = DefaultSourceResolver().resolveSleepSamples(staged + [unstaged])
        #expect(resolved.map(\.sourceName) == ["ZWatch", "ZWatch"])
    }

    @Test func higherPrioritySourceWinsHeartRateTimestampCollision() {
        let watch = SourceIdentity(name: "Watch")
        let priority = SourcePriority(orderedHighestFirst: [watch])
        let resolver = DefaultSourceResolver(priority: priority)

        let watchReading = heartRateSample(at: 0, bpm: 54, source: "Watch")
        let thirdPartyReading = heartRateSample(at: 0, bpm: 61, source: "ThirdPartyApp")

        let resolved = resolver.resolveHeartRateSamples([thirdPartyReading, watchReading])

        #expect(resolved.count == 1)
        #expect(resolved.first?.bpm == 54)
    }

    // MARK: - Priority ranking

    @Test func priorityRanksHigherForEarlierEntriesInOrderedList() {
        let first = SourceIdentity(name: "First")
        let second = SourceIdentity(name: "Second")
        let unranked = SourceIdentity(name: "Unranked")
        let priority = SourcePriority(orderedHighestFirst: [first, second])

        #expect(priority.rank(of: first) > priority.rank(of: second))
        #expect(priority.rank(of: second) > priority.rank(of: unranked))
        #expect(priority.rank(of: unranked) == 0)
    }
}
