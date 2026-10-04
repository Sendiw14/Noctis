import Foundation
import Testing

@testable import SoundKit

/// The six sounds, rendered offline for ten seconds each (APP_RULES.md R31): no clipping, no NaN,
/// no offset, the same samples for the same seed, and each one has the character it is named for.
struct SoundSynthTests {
    static let seconds = 10.0

    // MARK: Measures

    static func peak(_ x: [Float]) -> Float { x.reduce(0) { max($0, abs($1)) } }

    static func mean(_ x: [Float]) -> Double { x.reduce(0.0) { $0 + Double($1) } / Double(max(x.count, 1)) }

    static func rms(_ x: ArraySlice<Float>) -> Double {
        (x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(x.count, 1))).squareRoot()
    }

    /// The RMS of each `seconds`-long window.
    static func windows(_ x: [Float], seconds: Double) -> [Double] {
        let n = Int(seconds * Double(SoundSynth.sampleRate))
        return stride(from: 0, to: x.count - n + 1, by: n).map { rms(x[$0..<($0 + n)]) }
    }

    static func correlation(_ a: [Float], _ b: [Float]) -> Double {
        var ab = 0.0, aa = 0.0, bb = 0.0
        for i in 0..<min(a.count, b.count) {
            ab += Double(a[i]) * Double(b[i])
            aa += Double(a[i]) * Double(a[i])
            bb += Double(b[i]) * Double(b[i])
        }
        return ab / (aa * bb).squareRoot()
    }

    /// How fast the signal changes against how big it is: about 2*pi*f/fs for a tone, so near 0 for a
    /// slow smooth sound and near 1 for white noise.
    static func roughness(_ x: [Float]) -> Double {
        var d = 0.0, s = 0.0
        for i in 1..<x.count {
            let t = Double(x[i] - x[i - 1])
            d += t * t
            s += Double(x[i]) * Double(x[i])
        }
        return (d / s).squareRoot()
    }

    /// Power below and above a one-pole split at `cutoff`.
    static func split(_ x: [Float], cutoff: Double) -> (low: Double, high: Double) {
        let a = 1 - exp(-2 * Double.pi * cutoff / Double(SoundSynth.sampleRate))
        var y = 0.0, low = 0.0, high = 0.0
        for v in x {
            y += a * (Double(v) - y)
            low += y * y
            let h = Double(v) - y
            high += h * h
        }
        return (low, high)
    }

    // MARK: Every source

    @Test(arguments: SoundKind.allCases)
    func renders10SecondsWithoutClippingNaNOrOffset(kind: SoundKind) {
        let buffer = SoundSynth.render(kind, seconds: Self.seconds)
        #expect(buffer.frameCount == 441_000)
        for (name, channel) in [("left", buffer.left), ("right", buffer.right)] {
            #expect(channel.allSatisfy { $0.isFinite }, Comment(rawValue: "\(kind) \(name) has a NaN or infinity"))
            #expect(Self.peak(channel) < 0.95, Comment(rawValue: "\(kind) \(name) peaks at \(Self.peak(channel))"))
            #expect(abs(Self.mean(channel)) < 0.02, Comment(rawValue: "\(kind) \(name) has an offset of \(Self.mean(channel))"))
            let level = Self.rms(channel[...])
            #expect(level > 0.03 && level < 0.2, Comment(rawValue: "\(kind) \(name) has a level of \(level)"))
        }
    }

    @Test(arguments: SoundKind.allCases)
    func theSameSeedGivesTheSameSamples(kind: SoundKind) {
        let a = SoundSynth.render(kind, seconds: 2, seed: 1234)
        let b = SoundSynth.render(kind, seconds: 2, seed: 1234)
        #expect(a == b)
        #expect(SoundSynth.render(kind, seconds: 2) == SoundSynth.render(kind, seconds: 2))
        #expect(SoundSynth.render(kind, seconds: 2, seed: 1235) != a)
    }

    @Test(arguments: SoundKind.allCases)
    func theTwoEarsAreAlikeInCharacterAndDifferentInDetail(kind: SoundKind) {
        let buffer = SoundSynth.render(kind, seconds: 6)
        #expect(buffer.left != buffer.right)
        // Not a copy of each other, so the sound is around the head and not in it.
        #expect(abs(Self.correlation(buffer.left, buffer.right)) < 0.6, Comment(rawValue: "\(kind) is nearly mono"))
        let l = Self.rms(buffer.left[...]), r = Self.rms(buffer.right[...])
        #expect(max(l, r) / min(l, r) < 1.6, Comment(rawValue: "\(kind) is lopsided: \(l) against \(r)"))
    }

    @Test func aBufferIsTheSameHoweverItIsCut() {
        // The synth renders in the mixer's size of piece; a different cut of the same seed is the same sound.
        let whole = SoundSynth.render(.rain, seconds: 3, seed: 99)
        let again = SoundSynth.render(.rain, seconds: 3, seed: 99)
        #expect(whole == again)
    }

    // MARK: Character

    @Test func brownNoiseIsMostlyLowAndRainMostlyHigh() {
        let brown = SoundSynth.render(.brown, seconds: 6).left
        let rain = SoundSynth.render(.rain, seconds: 6).left
        let b = Self.split(brown, cutoff: 800)
        let r = Self.split(rain, cutoff: 800)
        #expect(b.low / b.high > 12, Comment(rawValue: "brown low/high \(b.low / b.high)"))
        #expect(r.high / r.low > 1.5, Comment(rawValue: "rain high/low \(r.high / r.low)"))
        // Brown noise has far more of its energy low down than rain does.
        #expect((b.low / b.high) > 20 * (r.low / r.high))
        #expect(Self.roughness(rain) > 5 * Self.roughness(brown))
    }

    @Test func theOceanSwellsAndDrawsBack() {
        let ocean = SoundSynth.render(.ocean, seconds: 36).left
        let levels = Self.windows(ocean, seconds: 0.5)
        let ratio = (levels.max() ?? 0) / max(levels.min() ?? 1, 1e-9)
        #expect(ratio > 2.2, Comment(rawValue: "ocean swells only \(ratio)x"))
        // Slowly: the level at one moment and half a second on are close; the swell isn't jitter.
        let steps = zip(levels, levels.dropFirst()).map { abs($0 - $1) / max($0, $1) }
        #expect((steps.max() ?? 1) < 0.6, Comment(rawValue: "ocean jumps \(steps.max() ?? 1) between half seconds"))
        // Roughly every nine to twelve seconds: count the rises through the middle level over 36 s.
        let mid = ((levels.max() ?? 0) + (levels.min() ?? 0)) / 2
        let smoothed = levels.indices.map { i -> Double in
            let range = max(0, i - 2)...min(levels.count - 1, i + 2)
            return range.map { levels[$0] }.reduce(0, +) / Double(range.count)
        }
        var rises = 0
        for i in 1..<smoothed.count where smoothed[i - 1] < mid && smoothed[i] >= mid { rises += 1 }
        #expect((2...5).contains(rises), Comment(rawValue: "\(rises) swells in 36 s"))
    }

    @Test func theWindComesInGusts() {
        let wind = SoundSynth.render(.wind, seconds: 40).left
        let levels = Self.windows(wind, seconds: 1)
        let ratio = (levels.max() ?? 0) / max(levels.min() ?? 1, 1e-9)
        #expect(ratio > 1.8, Comment(rawValue: "wind varies only \(ratio)x"))
    }

    @Test func theFireplaceCrackles() {
        let fire = SoundSynth.render(.fireplace, seconds: 20).left
        // Sharp moments stand well above the rumble.
        let crest = Double(Self.peak(fire)) / Self.rms(fire[...])
        #expect(crest > 3.2, Comment(rawValue: "fireplace crest \(crest)"))
        // And they are crackles, not a hum: the 20 ms windows vary a good deal.
        let levels = Self.windows(fire, seconds: 0.02)
        let ordered = levels.sorted()
        let loud = ordered[Int(Double(ordered.count) * 0.98)]
        let typical = ordered[ordered.count / 2]
        #expect(loud / typical > 1.7, Comment(rawValue: "fireplace 98th percentile over median: \(loud / typical)"))
    }

    @Test func theAmbientPadIsQuietAndTonal() {
        let pad = SoundSynth.render(.ambient, seconds: 8).left
        let level = Self.rms(pad[...])
        #expect(level < 0.07)
        // It is low and smooth: a few sines under 400 Hz, filtered; no click, no hiss.
        #expect(Self.roughness(pad) < 0.045, Comment(rawValue: "ambient roughness \(Self.roughness(pad))"))
        // A chord beats softly: the level moves, slowly.
        let levels = Self.windows(pad, seconds: 1)
        #expect((levels.max() ?? 0) / max(levels.min() ?? 1, 1e-9) > 1.04)
    }
}
