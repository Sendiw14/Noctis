import Foundation

// The small filters the sounds are built from. All value types, no allocation, no generics, no
// references: they run on the audio thread (APP_RULES.md R31).

enum SoundDSP {
    static let sampleRate: Float = 44_100
    static let twoPi: Float = 2 * .pi
}

/// A one-pole low-pass.
struct OnePoleLow {
    var y: Float = 0
    var a: Float

    init(cutoff: Float) {
        a = Self.coefficient(cutoff)
    }

    @inline(__always)
    static func coefficient(_ cutoff: Float) -> Float {
        1 - expf(-SoundDSP.twoPi * cutoff / SoundDSP.sampleRate)
    }

    @inline(__always)
    mutating func process(_ x: Float) -> Float {
        y += a * (x - y)
        return y
    }

    @inline(__always)
    mutating func setCutoff(_ cutoff: Float) {
        a = Self.coefficient(cutoff)
    }
}

/// A one-pole high-pass: the input less its low-passed self.
struct OnePoleHigh {
    var low: OnePoleLow

    init(cutoff: Float) {
        low = OnePoleLow(cutoff: cutoff)
    }

    @inline(__always)
    mutating func process(_ x: Float) -> Float {
        x - low.process(x)
    }
}

/// Takes the slow drift out of a signal (a high-pass at a few hertz), so no sound carries a
/// direct-current offset into the speaker.
struct DCBlocker {
    var x1: Float = 0
    var y1: Float = 0

    @inline(__always)
    mutating func process(_ x: Float) -> Float {
        let y = x - x1 + 0.9995 * y1
        x1 = x
        y1 = y
        return y
    }
}

/// Pink noise from white: three poles after Paul Kellet's economy filter, within about half a
/// decibel of -3 dB an octave over the audible range.
struct PinkFilter {
    var b0: Float = 0
    var b1: Float = 0
    var b2: Float = 0

    @inline(__always)
    mutating func process(_ w: Float) -> Float {
        b0 = 0.99765 * b0 + w * 0.0990460
        b1 = 0.96300 * b1 + w * 0.2965164
        b2 = 0.57000 * b2 + w * 1.0526913
        return b0 + b1 + b2 + w * 0.1848
    }
}

/// A band-pass (a state-variable filter in its trapezoidal form: stable while its center moves),
/// at unity gain at the center.
struct BandPass {
    var s1: Float = 0
    var s2: Float = 0
    var a1: Float = 0
    var a2: Float = 0
    var a3: Float = 0
    var k: Float = 1

    init() {}

    init(center: Float, q: Float) {
        set(center: center, q: q)
    }

    @inline(__always)
    mutating func set(center: Float, q: Float) {
        let g = tanf(.pi * min(center, SoundDSP.sampleRate * 0.45) / SoundDSP.sampleRate)
        k = 1 / q
        a1 = 1 / (1 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
    }

    @inline(__always)
    mutating func process(_ v0: Float) -> Float {
        let v3 = v0 - s2
        let v1 = a1 * s1 + a2 * v3
        let v2 = s2 + a2 * s1 + a3 * v3
        s1 = 2 * v1 - s1
        s2 = 2 * v2 - s2
        return v1 * k
    }
}

/// A sine from a rotating phasor: four multiplications a sample, no `sin`. It is put back on the
/// unit circle every so often so rounding can't make it drift.
struct Phasor {
    var re: Float
    var im: Float
    var cw: Float
    var sw: Float

    init(frequency: Float, phase: Float) {
        let w = SoundDSP.twoPi * frequency / SoundDSP.sampleRate
        re = cosf(phase)
        im = sinf(phase)
        cw = cosf(w)
        sw = sinf(w)
    }

    @inline(__always)
    mutating func next() -> Float {
        let r = re * cw - im * sw
        im = re * sw + im * cw
        re = r
        return im
    }

    @inline(__always)
    mutating func normalize() {
        let m = (re * re + im * im).squareRoot()
        re /= m
        im /= m
    }
}

/// A slow wander toward a new random target every few seconds, smoothed so it glides.
struct SlowWander {
    var value: Float
    var target: Float
    var countdown: Int = 0
    var smoothing: Float
    let low: Float
    let high: Float
    let minSeconds: Float
    let maxSeconds: Float
    /// How many times a second `next` is called: the sample rate, or a control rate.
    let tickRate: Float

    init(low: Float, high: Float, minSeconds: Float, maxSeconds: Float, glideSeconds: Float, tickRate: Float = SoundDSP.sampleRate, rng: inout SoundRandom) {
        self.low = low
        self.high = high
        self.minSeconds = minSeconds
        self.maxSeconds = maxSeconds
        self.tickRate = tickRate
        let first = rng.range(low, high)
        value = first
        target = first
        smoothing = 1 - expf(-1 / (glideSeconds * tickRate))
    }

    @inline(__always)
    mutating func next(_ rng: inout SoundRandom) -> Float {
        countdown -= 1
        if countdown <= 0 {
            target = rng.range(low, high)
            countdown = Int(rng.range(minSeconds, maxSeconds) * tickRate)
        }
        value += smoothing * (target - value)
        return value
    }
}
