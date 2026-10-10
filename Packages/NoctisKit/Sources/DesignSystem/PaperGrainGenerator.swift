/// Deterministic RNG so generated visuals (paper grain) are stable across
/// launches instead of reshuffling every render. Shipped (the grain is in
/// Release); not the DEBUG-only `SeededGenerator` that drives the mock Health
/// data, and named differently so a Release binary that contains
/// "SeededGenerator" can only mean the mock leaked (QA_LEDGER.md).
struct PaperGrainGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
