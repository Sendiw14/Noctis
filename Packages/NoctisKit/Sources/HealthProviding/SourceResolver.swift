import Foundation

/// Identifies where a sample came from. Two samples from the same app but
/// different device installs are still the "same" source for resolution
/// purposes — identity is by name/bundle, not by instance.
public nonisolated struct SourceIdentity: Sendable, Hashable {
    public let name: String
    public let bundleID: String?

    public init(name: String, bundleID: String? = nil) {
        self.name = name
        self.bundleID = bundleID
    }
}

/// A caller-supplied ranking of known sources, highest priority first.
/// NOCTIS never guesses which source is "better" from sample content —
/// priority is always an explicit, external decision.
public nonisolated struct SourcePriority: Sendable {
    private let ranks: [SourceIdentity: Int]

    public init(orderedHighestFirst: [SourceIdentity]) {
        var ranks: [SourceIdentity: Int] = [:]
        for (index, identity) in orderedHighestFirst.enumerated() {
            ranks[identity] = orderedHighestFirst.count - index
        }
        self.ranks = ranks
    }

    /// No known ranking — every source ties, and resolution falls back to
    /// a stable, deterministic tie-break (see `DefaultSourceResolver`).
    public static let unranked = SourcePriority(orderedHighestFirst: [])

    public func rank(of identity: SourceIdentity) -> Int {
        ranks[identity] ?? 0
    }
}

/// Resolves potentially overlapping, potentially duplicated samples from
/// one or more HealthKit sources into a single authoritative timeline.
///
/// This is the seam the architecture calls for between raw provider output
/// and the domain engines (`SleepSessionEngine`, `RecoveryEngine`, ...) —
/// those engines should never see two sources' overlapping claims about the
/// same night; they should see one resolved answer with resolution already
/// applied upstream.
public nonisolated protocol SourceResolving: Sendable {
    func resolveSleepSamples(_ samples: [RawSleepSample]) -> [RawSleepSample]
    func resolveHeartRateSamples(_ samples: [HeartRateSample]) -> [HeartRateSample]
}

/// The default resolver: exact-duplicate removal, then — when multiple
/// sources report overlapping data — the highest-priority source wins for
/// that overlap and lower-priority samples in the same window are dropped
/// entirely, never blended or double-counted.
///
/// Sources are ordered by explicit `SourcePriority` first; unranked ties
/// go to the source with the most staged (core, deep, REM) samples — the
/// richer tracker — and then to the source name, so the answer never
/// depends on input order.
///
/// A source never overrides itself: two overlapping samples from the
/// *same* source are both kept, with the later one trimmed to start where
/// the earlier one ends, so no time is counted twice.
///
/// With a single source (most real devices with only an Apple Watch), this is provably a no-op: there is
/// nothing to deduplicate and nothing to prioritize against. The behavior
/// only becomes visible once a second source exists.
public nonisolated struct DefaultSourceResolver: SourceResolving {
    private let priority: SourcePriority

    public init(priority: SourcePriority = .unranked) {
        self.priority = priority
    }

    public func resolveSleepSamples(_ samples: [RawSleepSample]) -> [RawSleepSample] {
        guard samples.count > 1 else { return samples }
        let deduplicated = removeExactDuplicates(samples)
        return removeLowerPriorityOverlaps(deduplicated)
    }

    public func resolveHeartRateSamples(_ samples: [HeartRateSample]) -> [HeartRateSample] {
        guard samples.count > 1 else { return samples }
        let deduplicated = removeExactHeartRateDuplicates(samples)
        return removeHeartRateTimestampCollisions(deduplicated)
    }

    // MARK: - Sleep samples

    private struct SleepDuplicateKey: Hashable {
        let start: Date
        let end: Date
        let stage: SleepStageValue
        let sourceBundleID: String
    }

    private func removeExactDuplicates(_ samples: [RawSleepSample]) -> [RawSleepSample] {
        var seen = Set<SleepDuplicateKey>()
        var result: [RawSleepSample] = []
        for sample in samples {
            let key = SleepDuplicateKey(start: sample.start, end: sample.end, stage: sample.stage, sourceBundleID: sample.sourceBundleID)
            if seen.insert(key).inserted {
                result.append(sample)
            }
        }
        return result
    }

    private func removeLowerPriorityOverlaps(_ samples: [RawSleepSample]) -> [RawSleepSample] {
        let bySource = Dictionary(grouping: samples) {
            SourceIdentity(name: $0.sourceName, bundleID: $0.sourceBundleID)
        }
        let stagedCounts = bySource.mapValues { samples in
            samples.count { [.core, .deep, .rem].contains($0.stage) }
        }
        let orderedSources = bySource.keys.sorted { lhs, rhs in
            let lhsRank = priority.rank(of: lhs)
            let rhsRank = priority.rank(of: rhs)
            if lhsRank != rhsRank { return lhsRank > rhsRank }
            let lhsStaged = stagedCounts[lhs] ?? 0
            let rhsStaged = stagedCounts[rhs] ?? 0
            if lhsStaged != rhsStaged { return lhsStaged > rhsStaged }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return (lhs.bundleID ?? "") < (rhs.bundleID ?? "")
        }

        var higherPriorityRanges: [(start: Date, end: Date)] = []
        var resolved: [RawSleepSample] = []

        for source in orderedSources {
            let sourceSamples = (bySource[source] ?? []).sorted { ($0.start, $0.end) < ($1.start, $1.end) }
            var accepted: [RawSleepSample] = []
            var coveredUntil = Date.distantPast
            for sample in sourceSamples {
                guard sample.end > sample.start else { continue }
                let overlapsHigherPriority = higherPriorityRanges.contains { strictlyOverlaps($0, (sample.start, sample.end)) }
                guard !overlapsHigherPriority else { continue }
                let start = max(sample.start, coveredUntil)
                guard sample.end > start else { continue }
                accepted.append(start == sample.start ? sample : RawSleepSample(
                    id: sample.id, start: start, end: sample.end, stage: sample.stage,
                    sourceName: sample.sourceName, sourceBundleID: sample.sourceBundleID, timeZone: sample.timeZone
                ))
                coveredUntil = sample.end
            }
            resolved += accepted
            higherPriorityRanges += accepted.map { ($0.start, $0.end) }
        }

        return resolved.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    /// `DateInterval.intersects` treats touching endpoints as overlapping —
    /// which is wrong here. Consecutive stage segments within one real night
    /// (Core ending exactly when Deep begins) touch at a boundary constantly
    /// and must NOT be treated as a duplicate/overlap claim.
    private func strictlyOverlaps(_ a: (start: Date, end: Date), _ b: (start: Date, end: Date)) -> Bool {
        max(a.start, b.start) < min(a.end, b.end)
    }

    // MARK: - Heart rate samples

    private struct HeartRateDuplicateKey: Hashable {
        let date: Date
        let bpm: Double
        let sourceName: String
    }

    private func removeExactHeartRateDuplicates(_ samples: [HeartRateSample]) -> [HeartRateSample] {
        var seen = Set<HeartRateDuplicateKey>()
        var result: [HeartRateSample] = []
        for sample in samples {
            let key = HeartRateDuplicateKey(date: sample.date, bpm: sample.bpm, sourceName: sample.sourceName)
            if seen.insert(key).inserted {
                result.append(sample)
            }
        }
        return result
    }

    /// When two different sources report a reading at the exact same
    /// instant, keep only the highest-priority source's value.
    private func removeHeartRateTimestampCollisions(_ samples: [HeartRateSample]) -> [HeartRateSample] {
        let byTimestamp = Dictionary(grouping: samples, by: \.date)
        let resolved = byTimestamp.values.compactMap { group -> HeartRateSample? in
            group.max { lhs, rhs in
                priority.rank(of: SourceIdentity(name: lhs.sourceName)) < priority.rank(of: SourceIdentity(name: rhs.sourceName))
            }
        }
        return resolved.sorted { $0.date < $1.date }
    }
}
