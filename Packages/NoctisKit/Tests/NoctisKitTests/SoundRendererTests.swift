import Foundation
import Testing

@testable import SoundKit

/// The audio thread's mixer (APP_RULES.md R31): what a command does, sample by sample.
struct SoundRendererTests {
    static let rate = Double(SoundSynth.sampleRate)

    /// Renders `seconds` in buffers of `size`, returning both channels.
    static func render(_ renderer: SoundRenderer, seconds: Double, size: Int = 512) -> (l: [Float], r: [Float]) {
        let total = Int(seconds * rate)
        var l = [Float](repeating: 0, count: total)
        var r = [Float](repeating: 0, count: total)
        l.withUnsafeMutableBufferPointer { lp in
            r.withUnsafeMutableBufferPointer { rp in
                guard let lb = lp.baseAddress, let rb = rp.baseAddress else { return }
                var done = 0
                while done < total {
                    let n = min(size, total - done)
                    renderer.renderStereo(left: lb + done, right: rb + done, count: n)
                    done += n
                }
            }
        }
        return (l, r)
    }

    static func level(_ x: [Float], from: Double, to: Double) -> Double {
        let a = Int(from * rate), b = min(Int(to * rate), x.count)
        return SoundSynthTests.rms(x[a..<b])
    }

    static let seeds: [SoundKind: UInt64] = Dictionary(uniqueKeysWithValues: SoundKind.allCases.map { ($0, $0.defaultSeed) })

    @Test func silentUntilAskedAndSaysSo() {
        let renderer = SoundRenderer(seeds: Self.seeds)
        var l = [Float](repeating: 1, count: 1000), r = [Float](repeating: 1, count: 1000)
        let silent = l.withUnsafeMutableBufferPointer { lp in
            r.withUnsafeMutableBufferPointer { rp in renderer.renderStereo(left: lp.baseAddress!, right: rp.baseAddress!, count: 1000) }
        }
        #expect(silent)
        #expect(l.allSatisfy { $0 == 0 } && r.allSatisfy { $0 == 0 })
    }

    @Test func aSoundPlaysAtItsGain() {
        let natural = SoundSynthTests.rms(SoundSynth.render(.brown, seconds: 3).left[...])
        let renderer = SoundRenderer(seeds: Self.seeds)
        renderer.apply(SoundCommand(kind: .brown, gain: 0.4))
        let out = Self.render(renderer, seconds: 3)
        let level = Self.level(out.l, from: 0.5, to: 3)
        #expect(abs(level / (natural * 0.4) - 1) < 0.08, Comment(rawValue: "level \(level) against \(natural * 0.4)"))
    }

    @Test func theGainGlidesAndNeverClicks() {
        let renderer = SoundRenderer(seeds: Self.seeds)
        renderer.apply(SoundCommand(kind: .brown, gain: 0.1))
        let before = Self.render(renderer, seconds: 0.5).l
        renderer.apply(SoundCommand(kind: .brown, gain: 0.9, fader: nil))
        let out = Self.render(renderer, seconds: 0.5).l
        // The sound's own movement is small from one sample to the next; a step in gain would not be.
        var biggest: Float = 0
        for i in 1..<out.count { biggest = max(biggest, abs(out[i] - out[i - 1])) }
        #expect(biggest < 0.2)
        // And it gets there: nine times the gain, nine times the level, within the half second.
        let ratio = Self.level(out, from: 0.3, to: 0.5) / Self.level(before, from: 0.2, to: 0.5)
        #expect(ratio > 6, Comment(rawValue: "gain moved the level \(ratio)x"))
    }

    @Test func theFaderRampsInSquared() {
        let renderer = SoundRenderer(seeds: Self.seeds)
        renderer.apply(SoundCommand(kind: .brown, gain: 0.4, fader: 1, faderSeconds: 0.5))
        let out = Self.render(renderer, seconds: 1).l
        let start = Self.level(out, from: 0, to: 0.02)
        let middle = Self.level(out, from: 0.24, to: 0.26)
        let end = Self.level(out, from: 0.8, to: 1)
        #expect(start < end * 0.05)
        // Halfway through the ramp the fader is 0.5 and the gain on the signal is 0.25.
        #expect(abs(middle / end - 0.25) < 0.09, Comment(rawValue: "middle \(middle / end)"))
    }

    @Test func aFadeOutReachesSilenceAndSaysSo() {
        let renderer = SoundRenderer(seeds: Self.seeds)
        renderer.apply(SoundCommand(kind: .rain, gain: 0.5))
        _ = Self.render(renderer, seconds: 0.2)
        renderer.apply(SoundCommand(kind: .rain, gain: 0.5, fader: 0, faderSeconds: 1))
        let fade = Self.render(renderer, seconds: 1.2).l
        #expect(Self.level(fade, from: 0, to: 0.1) > 0.02)
        #expect(Self.level(fade, from: 1.05, to: 1.2) == 0)
        var l = [Float](repeating: 1, count: 512), r = [Float](repeating: 1, count: 512)
        let silent = l.withUnsafeMutableBufferPointer { lp in
            r.withUnsafeMutableBufferPointer { rp in renderer.renderStereo(left: lp.baseAddress!, right: rp.baseAddress!, count: 512) }
        }
        #expect(silent)
    }

    @Test func aChangeOfGainDoesNotUnMuteAPause() {
        let renderer = SoundRenderer(seeds: Self.seeds)
        renderer.apply(SoundCommand(kind: .wind, gain: 0.4))
        _ = Self.render(renderer, seconds: 0.2)
        renderer.apply(SoundCommand(kind: .wind, gain: 0.4, fader: 0, faderSeconds: 0.1))
        _ = Self.render(renderer, seconds: 0.3)
        renderer.apply(SoundCommand(kind: .wind, gain: 0.9, fader: nil))
        let out = Self.render(renderer, seconds: 0.3).l
        #expect(SoundSynthTests.peak(out) == 0)
    }

    @Test func switchingCrossesInEqualPowerOverOneAndAHalfSeconds() {
        let renderer = SoundRenderer(seeds: Self.seeds)
        renderer.apply(SoundCommand(kind: .brown, gain: 0.4))
        _ = Self.render(renderer, seconds: 1)
        renderer.apply(SoundCommand(kind: .rain, gain: 0.4, crossfadeSeconds: 1.5))
        let out = Self.render(renderer, seconds: 3).l
        // Through the crossing the loudness holds, as two unrelated sounds do under equal power.
        let before = Self.level(out, from: 0, to: 0.05)
        let levels = stride(from: 0.1, to: 1.5, by: 0.1).map { Self.level(out, from: $0, to: $0 + 0.1) }
        for level in levels {
            #expect(level > before * 0.55 && level < before * 1.6, Comment(rawValue: "level \(level) while \(before) before"))
        }
        // After it, it is the new sound alone: rain's level, not brown's.
        let rain = SoundSynthTests.rms(SoundSynth.render(.rain, seconds: 3).left[...]) * 0.4
        #expect(abs(Self.level(out, from: 2, to: 3) / rain - 1) < 0.1)
    }

    @Test func eachSoundKeepsItsOwnGainThroughACrossing() {
        let renderer = SoundRenderer(seeds: Self.seeds)
        renderer.apply(SoundCommand(kind: .brown, gain: 0.8))
        _ = Self.render(renderer, seconds: 1)
        renderer.apply(SoundCommand(kind: .rain, gain: 0.2, crossfadeSeconds: 1))
        let out = Self.render(renderer, seconds: 2).l
        let brown = SoundSynthTests.rms(SoundSynth.render(.brown, seconds: 2).left[...]) * 0.8
        let rain = SoundSynthTests.rms(SoundSynth.render(.rain, seconds: 2).left[...]) * 0.2
        #expect(abs(Self.level(out, from: 1.4, to: 2) / rain - 1) < 0.12)
        #expect(brown > rain)
    }

    @Test func fullGainNeverClips() {
        for kind in SoundKind.allCases {
            let renderer = SoundRenderer(seeds: Self.seeds)
            renderer.apply(SoundCommand(kind: kind, gain: 1))
            let out = Self.render(renderer, seconds: 6)
            #expect(SoundSynthTests.peak(out.l) < 0.95, Comment(rawValue: "\(kind)"))
            #expect(SoundSynthTests.peak(out.r) < 0.95)
        }
    }

    @Test func theSoundIsTheSameHoweverTheSystemCutsTheBuffers() {
        func render(size: Int) -> [Float] {
            let renderer = SoundRenderer(seeds: Self.seeds)
            renderer.apply(SoundCommand(kind: .fireplace, gain: 0.5))
            return Self.render(renderer, seconds: 2, size: size).l
        }
        let big = render(size: 4096)
        for size in [1, 7, 256, 511, 513, 1156, 2048] {
            #expect(render(size: size) == big, Comment(rawValue: "buffer size \(size)"))
        }
    }

    @Test func aCommandIsTakenBetweenBuffers() {
        let renderer = SoundRenderer(seeds: Self.seeds)
        renderer.apply(SoundCommand(kind: .brown, gain: 0.4))
        renderer.apply(SoundCommand(kind: .ocean, gain: 0.4))
        let out = Self.render(renderer, seconds: 1).l
        // Only the last command counts: it is the ocean from the first buffer.
        let ocean = SoundSynth.render(.ocean, seconds: 1).left.map { $0 * 0.4 }
        #expect(zip(out.prefix(2000), ocean.prefix(2000)).allSatisfy { abs($0 - $1) < 0.004 })
    }
}
