import Foundation
import SoundCatalog

// A voice is one sound in stereo: two channels of the same source with different seeds. The six
// voices live together in one block of memory (`SoundVoiceBank`) that is set aside before any
// sound plays and given back when the bank goes, so the audio thread only ever walks pointers.

struct BrownVoice {
    var left: BrownSource
    var right: BrownSource

    @inline(__always)
    mutating func render(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ count: Int) {
        var i = 0
        while i < count {
            l[i] = left.next()
            r[i] = right.next()
            i += 1
        }
    }
}

struct RainVoice {
    var left: RainSource
    var right: RainSource

    @inline(__always)
    mutating func render(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ count: Int) {
        var i = 0
        while i < count {
            l[i] = left.next()
            r[i] = right.next()
            i += 1
        }
    }
}

struct OceanVoice {
    var left: OceanSource
    var right: OceanSource

    @inline(__always)
    mutating func render(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ count: Int) {
        var i = 0
        while i < count {
            l[i] = left.next()
            r[i] = right.next()
            i += 1
        }
    }
}

struct WindVoice {
    var left: WindSource
    var right: WindSource

    @inline(__always)
    mutating func render(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ count: Int) {
        var i = 0
        while i < count {
            l[i] = left.next()
            r[i] = right.next()
            i += 1
        }
    }
}

struct FireVoice {
    var left: FireSource
    var right: FireSource

    @inline(__always)
    mutating func render(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ count: Int) {
        var i = 0
        while i < count {
            l[i] = left.next()
            r[i] = right.next()
            i += 1
        }
    }
}

struct AmbientVoice {
    var left: AmbientSource
    var right: AmbientSource

    @inline(__always)
    mutating func render(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ count: Int) {
        var i = 0
        while i < count {
            l[i] = left.next()
            r[i] = right.next()
            i += 1
        }
    }
}

/// All six, in one value.
struct SoundVoices {
    var brown: BrownVoice
    var rain: RainVoice
    var ocean: OceanVoice
    var wind: WindVoice
    var fire: FireVoice
    var ambient: AmbientVoice

    /// Renders `count` frames of `kind` into `l` and `r`.
    @inline(__always)
    mutating func render(_ kind: Int, _ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ count: Int) {
        switch kind {
        case 0: brown.render(l, r, count)
        case 1: rain.render(l, r, count)
        case 2: ocean.render(l, r, count)
        case 3: wind.render(l, r, count)
        case 4: fire.render(l, r, count)
        default: ambient.render(l, r, count)
        }
    }
}

/// The memory behind the voices: the voices themselves and the pools their droplets, crackles and
/// pad oscillators draw on. Everything is allocated here, once, off the audio thread.
///
/// The audio thread is the only one that touches the voices once sound is playing (the main thread
/// hands it commands through atomics, never through this memory), which is why this is
/// `@unchecked Sendable`.
final class SoundVoiceBank: @unchecked Sendable {
    let voices: UnsafeMutablePointer<SoundVoices>
    private let drops: UnsafeMutablePointer<Droplet>
    private let crackles: UnsafeMutablePointer<Crackle>
    private let pads: UnsafeMutablePointer<PadOscillator>

    /// A bank where each sound starts from its own default seed (`seeds` overrides one).
    init(seeds: [SoundKind: UInt64] = [:]) {
        func seed(_ kind: SoundKind, _ side: UInt64) -> UInt64 {
            (seeds[kind] ?? kind.defaultSeed) &+ side &* 0x9E37_79B9_7F4A_7C15
        }
        drops = .allocate(capacity: RainSource.dropCount * 2)
        crackles = .allocate(capacity: FireSource.crackleCount * 2)
        pads = .allocate(capacity: AmbientSource.count * 2)
        voices = .allocate(capacity: 1)
        voices.initialize(to: SoundVoices(
            brown: BrownVoice(left: BrownSource(seed: seed(.brown, 0)), right: BrownSource(seed: seed(.brown, 1))),
            rain: RainVoice(
                left: RainSource(seed: seed(.rain, 0), drops: drops),
                right: RainSource(seed: seed(.rain, 1), drops: drops + RainSource.dropCount)
            ),
            ocean: OceanVoice(left: OceanSource(seed: seed(.ocean, 0)), right: OceanSource(seed: seed(.ocean, 1))),
            wind: WindVoice(left: WindSource(seed: seed(.wind, 0)), right: WindSource(seed: seed(.wind, 1))),
            fire: FireVoice(
                left: FireSource(seed: seed(.fireplace, 0), crackles: crackles),
                right: FireSource(seed: seed(.fireplace, 1), crackles: crackles + FireSource.crackleCount)
            ),
            ambient: AmbientVoice(
                left: AmbientSource(seed: seed(.ambient, 0), oscillators: pads),
                right: AmbientSource(seed: seed(.ambient, 1), oscillators: pads + AmbientSource.count)
            )
        ))
    }

    deinit {
        voices.deinitialize(count: 1)
        voices.deallocate()
        drops.deallocate()
        crackles.deallocate()
        pads.deallocate()
    }
}

/// A sound rendered offline: for tests, and for anything that wants the sound without the engine.
/// It allocates freely; it is never called from the audio thread.
public enum SoundSynth {
    public static let sampleRate = 44_100

    public struct Buffer: Sendable, Equatable {
        public var left: [Float]
        public var right: [Float]

        public var frameCount: Int { left.count }
    }

    /// `seconds` of `kind` at its natural level (before any app gain), from `seed` (the sound's
    /// default when nil). The same seed gives the same samples.
    public static func render(_ kind: SoundKind, seconds: Double, seed: UInt64? = nil) -> Buffer {
        let frames = Int(seconds * Double(sampleRate))
        let bank = SoundVoiceBank(seeds: seed.map { [kind: $0] } ?? [:])
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                guard let lp = l.baseAddress, let rp = r.baseAddress else { return }
                // In the same size of pieces the mixer uses, so the offline sound is the live one.
                var done = 0
                while done < frames {
                    let n = min(frames - done, SoundRenderer.chunk)
                    bank.voices.pointee.render(kind.index, lp + done, rp + done, n)
                    done += n
                }
            }
        }
        return Buffer(left: left, right: right)
    }
}
