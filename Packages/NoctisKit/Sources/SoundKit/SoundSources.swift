import Foundation

// The six sounds, one channel each. A voice (SoundVoices.swift) is two of these with different
// seeds, so left and right are alike in character and never in detail. Everything here runs on
// the audio thread (APP_RULES.md R31): value types, plain loops, memory that was set aside before
// the sound started, no allocation, no locks, no references to follow.

/// Control values (a filter's cutoff, a swell) are worked out once every this many samples.
let soundControlInterval = 32

// MARK: - Brown noise

/// White noise leaked through an integrator: a steady, deep rumble, -6 dB an octave.
struct BrownSource {
    var rng: SoundRandom
    var y: Float = 0
    var dc = DCBlocker()

    static let leak: Float = 0.995
    /// Sets the level: the integrator's gain for white noise of this size.
    static let input: Float = 0.0237

    init(seed: UInt64) {
        rng = SoundRandom(seed: seed)
    }

    @inline(__always)
    mutating func next() -> Float {
        y = Self.leak * y + Self.input * rng.bipolar()
        return dc.process(y)
    }
}

// MARK: - Rain

struct Droplet {
    var env: Float = 0
    var decay: Float = 0.99
    var amp: Float = 0
    var band = BandPass()

    @inline(__always)
    mutating func step(_ noise: Float) -> Float {
        let y = band.process(noise) * env * amp
        env *= decay
        if env < 0.001 { env = 0 }
        return y
    }
}

/// Pink noise with the low end taken off (the hiss of steady rain), and now and then a short
/// filtered burst: a drop on a leaf, at a low gain.
struct RainSource {
    var rng: SoundRandom
    var pink = PinkFilter()
    var high = OnePoleHigh(cutoff: 450)
    var dc = DCBlocker()
    var countdown: Int
    let drops: UnsafeMutablePointer<Droplet>

    static let dropCount = 6
    static let bed: Float = 0.105
    static let dropGain: Float = 0.40
    static let dropsPerSecond: Float = 24

    init(seed: UInt64, drops: UnsafeMutablePointer<Droplet>) {
        rng = SoundRandom(seed: seed)
        self.drops = drops
        drops.initialize(repeating: Droplet(), count: Self.dropCount)
        countdown = rng.gap(rate: Self.dropsPerSecond, sampleRate: SoundDSP.sampleRate)
    }

    @inline(__always)
    mutating func next() -> Float {
        let w = rng.bipolar()
        var out = high.process(pink.process(w)) * Self.bed
        countdown -= 1
        if countdown <= 0 {
            spawn()
            countdown = rng.gap(rate: Self.dropsPerSecond, sampleRate: SoundDSP.sampleRate)
        }
        let n = rng.bipolar()
        var i = 0
        while i < Self.dropCount {
            if drops[i].env > 0 { out += drops[i].step(n) }
            i += 1
        }
        return dc.process(out)
    }

    @inline(__always)
    mutating func spawn() {
        var slot = 0
        var quietest: Float = .greatestFiniteMagnitude
        var i = 0
        while i < Self.dropCount {
            if drops[i].env <= 0 {
                slot = i
                break
            }
            if drops[i].env < quietest {
                quietest = drops[i].env
                slot = i
            }
            i += 1
        }
        let seconds = rng.range(0.006, 0.018)
        drops[slot].env = 1
        drops[slot].decay = expf(-1 / (seconds * SoundDSP.sampleRate))
        drops[slot].amp = rng.range(0.55, 1) * Self.dropGain
        drops[slot].band.set(center: rng.range(1800, 5200), q: 6)
    }
}

// MARK: - Ocean

/// Pink and brown noise through a low-pass that opens and closes with a swell: louder and brighter
/// as a wave builds, quieter and darker as it draws back, every nine to twelve seconds, with the
/// cutoff drifting a little on its own.
struct OceanSource {
    var rng: SoundRandom
    var pink = PinkFilter()
    var brown: Float = 0
    var low = OnePoleLow(cutoff: 600)
    var foam = OnePoleHigh(cutoff: 2600)
    var dc = DCBlocker()
    var drift: SlowWander
    var phase: Float
    var period: Float
    var amp: Float = 0.2
    var foamAmp: Float = 0
    var tick = 0

    static let level: Float = 0.62
    static let foamLevel: Float = 0.05

    init(seed: UInt64) {
        var r = SoundRandom(seed: seed)
        drift = SlowWander(
            low: -140, high: 140, minSeconds: 5, maxSeconds: 10, glideSeconds: 3, tickRate: SoundDSP.sampleRate / Float(soundControlInterval), rng: &r)
        phase = r.unit()
        period = r.range(9, 12)
        rng = r
    }

    @inline(__always)
    mutating func next() -> Float {
        let w = rng.bipolar()
        brown = 0.995 * brown + 0.0237 * rng.bipolar()
        let base = 0.65 * pink.process(w) * 0.32 + 0.35 * brown * 1.4
        tick -= 1
        if tick <= 0 {
            tick = soundControlInterval
            control()
        }
        let wave = low.process(base) * amp * Self.level
        return dc.process(wave + foam.process(w) * foamAmp)
    }

    @inline(__always)
    mutating func control() {
        phase += Float(soundControlInterval) / (period * SoundDSP.sampleRate)
        if phase >= 1 {
            phase -= 1
            period = rng.range(9, 12)
        }
        let swell = 0.5 - 0.5 * cosf(SoundDSP.twoPi * phase)
        let shaped = swell * swell.squareRoot()
        amp = 0.18 + 0.82 * shaped
        foamAmp = Self.foamLevel * shaped * shaped
        low.setCutoff(max(160 + 1900 * shaped + drift.next(&rng), 90))
    }
}

// MARK: - Wind

/// Noise through a band-pass whose center wanders and whose loudness rises and falls in gusts.
struct WindSource {
    var rng: SoundRandom
    var band = BandPass(center: 500, q: 1.4)
    var rumble = OnePoleLow(cutoff: 140)
    var dc = DCBlocker()
    var center: SlowWander
    var gust: SlowWander
    var gain: Float = 0.5
    var tick = 0

    static let level: Float = 1.7
    static let rumbleLevel: Float = 0.25

    init(seed: UInt64) {
        var r = SoundRandom(seed: seed)
        let control = SoundDSP.sampleRate / Float(soundControlInterval)
        center = SlowWander(low: 280, high: 900, minSeconds: 2.5, maxSeconds: 6, glideSeconds: 1.5, tickRate: control, rng: &r)
        gust = SlowWander(low: 0.15, high: 1, minSeconds: 3, maxSeconds: 8, glideSeconds: 1.6, tickRate: control, rng: &r)
        rng = r
    }

    @inline(__always)
    mutating func next() -> Float {
        let w = rng.bipolar()
        tick -= 1
        if tick <= 0 {
            tick = soundControlInterval
            band.set(center: center.next(&rng), q: 1.4)
            let g = gust.next(&rng)
            gain = g * g.squareRoot()
        }
        let v = band.process(w) * gain * Self.level + rumble.process(w) * Self.rumbleLevel * gain
        return dc.process(v)
    }
}

// MARK: - Fireplace

struct Crackle {
    var env: Float = 0
    var decay: Float = 0.99
    var amp: Float = 0
    var band = BandPass()

    @inline(__always)
    mutating func step(_ noise: Float) -> Float {
        let y = band.process(noise) * env * amp
        env *= decay
        if env < 0.002 { env = 0 }
        return y
    }
}

/// A low rumble that flickers, and crackles at random times: short sharp bursts, mostly small and
/// now and then a loud one, sometimes two close together.
struct FireSource {
    var rng: SoundRandom
    var rumbleLow = OnePoleLow(cutoff: 130)
    var brown: Float = 0
    var hiss = OnePoleHigh(cutoff: 1500)
    var pink = PinkFilter()
    var dc = DCBlocker()
    var flicker: SlowWander
    var level: Float = 0.8
    var tick = 0
    var countdown: Int
    let crackles: UnsafeMutablePointer<Crackle>

    static let crackleCount = 5
    static let cracklesPerSecond: Float = 6.5
    static let rumble: Float = 1.6
    static let crackleGain: Float = 0.65
    static let hissLevel: Float = 0.014

    init(seed: UInt64, crackles: UnsafeMutablePointer<Crackle>) {
        var r = SoundRandom(seed: seed)
        flicker = SlowWander(
            low: 0.55, high: 1, minSeconds: 0.4, maxSeconds: 1.6, glideSeconds: 0.25, tickRate: SoundDSP.sampleRate / Float(soundControlInterval), rng: &r)
        self.crackles = crackles
        crackles.initialize(repeating: Crackle(), count: Self.crackleCount)
        countdown = r.gap(rate: Self.cracklesPerSecond, sampleRate: SoundDSP.sampleRate)
        rng = r
    }

    @inline(__always)
    mutating func next() -> Float {
        brown = 0.996 * brown + 0.02 * rng.bipolar()
        tick -= 1
        if tick <= 0 {
            tick = soundControlInterval
            level = flicker.next(&rng)
        }
        var out = rumbleLow.process(brown) * Self.rumble * level
        out += hiss.process(pink.process(rng.bipolar())) * Self.hissLevel * level
        countdown -= 1
        if countdown <= 0 {
            spawn()
            // Sometimes the next one follows at once, as a stick settles.
            countdown =
                rng.unit() < 0.3 ? rng.gap(rate: 55, sampleRate: SoundDSP.sampleRate) : rng.gap(rate: Self.cracklesPerSecond, sampleRate: SoundDSP.sampleRate)
        }
        let n = rng.bipolar()
        var i = 0
        while i < Self.crackleCount {
            if crackles[i].env > 0 { out += crackles[i].step(n) }
            i += 1
        }
        return dc.process(out)
    }

    @inline(__always)
    mutating func spawn() {
        var slot = 0
        var quietest: Float = .greatestFiniteMagnitude
        var i = 0
        while i < Self.crackleCount {
            if crackles[i].env <= 0 {
                slot = i
                break
            }
            if crackles[i].env < quietest {
                quietest = crackles[i].env
                slot = i
            }
            i += 1
        }
        let u = rng.unit()
        let seconds = rng.range(0.0012, 0.005)
        crackles[slot].env = 1
        crackles[slot].decay = expf(-1 / (seconds * SoundDSP.sampleRate))
        crackles[slot].amp = (0.10 + 0.90 * u * u * u) * Self.crackleGain
        crackles[slot].band.set(center: rng.range(1200, 5500), q: 1.8)
    }
}

// MARK: - Ambient

struct PadOscillator {
    var phasor: Phasor
    var lfoPhase: Float
    var lfoStep: Float
    var weight: Float
    /// Where its loudness is heading (set at the control rate), and where it is now (glides to it
    /// every sample, so a step in the target is never a click).
    var target: Float = 0
    var level: Float = 0
}

/// A slow pad: a quiet fixed chord (D, A, E and F sharp over a low D), each note three sines a
/// few cents apart so they shimmer, each breathing on its own slow cycle, through a low-pass that
/// opens and closes over half a minute.
struct AmbientSource {
    var rng: SoundRandom
    var low = OnePoleLow(cutoff: 800)
    var dc = DCBlocker()
    var cutoffPhase: Float
    var tick = 0
    var renorm = 0
    let oscillators: UnsafeMutablePointer<PadOscillator>

    static let count = 13
    static let level: Float = 0.095

    /// Frequency, weight and detune of every oscillator.
    static let notes: [(frequency: Float, weight: Float)] = [(146.83, 1.0), (220.0, 0.8), (329.63, 0.5), (369.99, 0.32)]
    static let detune: [Float] = [-0.0035, 0, 0.0035]

    init(seed: UInt64, oscillators: UnsafeMutablePointer<PadOscillator>) {
        var r = SoundRandom(seed: seed)
        self.oscillators = oscillators
        var index = 0
        for note in Self.notes {
            for detune in Self.detune {
                let seconds = r.range(8, 20)
                (oscillators + index).initialize(
                    to: PadOscillator(
                        phasor: Phasor(frequency: note.frequency * (1 + detune), phase: r.range(0, SoundDSP.twoPi)),
                        lfoPhase: r.unit(), lfoStep: Float(soundControlInterval) / (seconds * SoundDSP.sampleRate), weight: note.weight / 3
                    ))
                index += 1
            }
        }
        // A low D underneath, alone.
        let seconds = r.range(14, 22)
        (oscillators + index).initialize(
            to: PadOscillator(
                phasor: Phasor(frequency: 73.42, phase: r.range(0, SoundDSP.twoPi)),
                lfoPhase: r.unit(), lfoStep: Float(soundControlInterval) / (seconds * SoundDSP.sampleRate), weight: 0.45
            ))
        cutoffPhase = r.unit()
        rng = r
    }

    @inline(__always)
    mutating func next() -> Float {
        tick -= 1
        if tick <= 0 {
            tick = soundControlInterval
            control()
        }
        var sum: Float = 0
        var i = 0
        while i < Self.count {
            oscillators[i].level += (oscillators[i].target - oscillators[i].level) * 0.002
            sum += oscillators[i].phasor.next() * oscillators[i].level
            i += 1
        }
        return dc.process(low.process(sum) * Self.level)
    }

    @inline(__always)
    mutating func control() {
        var i = 0
        while i < Self.count {
            var phase = oscillators[i].lfoPhase + oscillators[i].lfoStep
            if phase >= 1 { phase -= 1 }
            oscillators[i].lfoPhase = phase
            oscillators[i].target = oscillators[i].weight * (0.35 + 0.65 * (0.5 - 0.5 * cosf(SoundDSP.twoPi * phase)))
            i += 1
        }
        cutoffPhase += Float(soundControlInterval) / (37 * SoundDSP.sampleRate)
        if cutoffPhase >= 1 { cutoffPhase -= 1 }
        low.setCutoff(650 + 520 * (0.5 - 0.5 * cosf(SoundDSP.twoPi * cutoffPhase)))
        renorm += 1
        if renorm >= 32 {
            renorm = 0
            var k = 0
            while k < Self.count {
                oscillators[k].phasor.normalize()
                k += 1
            }
        }
    }
}
