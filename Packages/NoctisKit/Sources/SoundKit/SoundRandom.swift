import Foundation

/// A small seeded random source (xorshift64*): a value type with no allocation, safe on the audio
/// thread. The same seed gives the same numbers, which is what lets a test render the same
/// buffer twice.
public struct SoundRandom: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        // SplitMix64 turns any seed, a small one included, into a well mixed non-zero state.
        var z = seed &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        state = z == 0 ? 0x2545_F491_4F6C_DD1D : z
    }

    @inline(__always)
    public mutating func nextBits() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2_685_821_657_736_338_717
    }

    /// Uniform in -1 ..< 1.
    @inline(__always)
    public mutating func bipolar() -> Float {
        Float(Int32(truncatingIfNeeded: nextBits() >> 32)) * (1.0 / 2_147_483_648.0)
    }

    /// Uniform in 0 ..< 1.
    @inline(__always)
    public mutating func unit() -> Float {
        Float(nextBits() >> 40) * (1.0 / 16_777_216.0)
    }

    @inline(__always)
    public mutating func range(_ low: Float, _ high: Float) -> Float {
        low + (high - low) * unit()
    }

    /// Samples until the next event of a process with `rate` events a second (exponential gaps).
    @inline(__always)
    public mutating func gap(rate: Float, sampleRate: Float) -> Int {
        let u = max(unit(), 1e-6)
        return max(Int(-logf(u) / rate * sampleRate), 1)
    }
}
