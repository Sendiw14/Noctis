import Foundation

// The meditation's chimes (APP_RULES.md R34): one sine, a short soft attack and an exponential decay,
// made here in code. No audio file ships (R31). Rendered ahead into plain samples, not on the audio
// thread, so none of the real-time rules of the sleep sounds apply: it is a short array and a WAV header.

public extension MeditationChimeKind {
    /// C5 to begin, E5 for a change of part, G4 (lower, longer) to close.
    var frequency: Double {
        switch self {
        case .start: 523.25
        case .transition: 659.25
        case .end: 392.0
        }
    }

    /// How long it rings before it is gone.
    var seconds: Double {
        switch self {
        case .start: 4.5
        case .transition: 3.5
        case .end: 6.0
        }
    }
}

public enum ChimeSynth {
    public static let sampleRate = 44_100.0
    /// Soft: a third of full scale at the loudest.
    public static let peak: Float = 0.3
    /// A rise this long keeps the start from clicking.
    public static let attackSeconds = 0.02
    /// A fall this long to nothing at the end, so the last sample is exactly 0.
    public static let releaseSeconds = 0.05
    /// The decay reaches -60 dB (a thousandth) at the end of the chime.
    static let decayDecades = 6.9

    /// A sine at `frequency` ringing for `seconds` and fading away.
    public static func render(frequency: Double, seconds: Double, sampleRate: Double = sampleRate) -> [Float] {
        let count = max(Int(seconds * sampleRate), 1)
        let tau = seconds / decayDecades
        let attack = attackSeconds * sampleRate
        let release = releaseSeconds * sampleRate
        var samples = [Float](repeating: 0, count: count)
        var i = 0
        while i < count {
            let t = Double(i) / sampleRate
            var envelope = exp(-t / tau)
            if Double(i) < attack { envelope *= Double(i) / attack }
            let toEnd = Double(count - 1 - i)
            if toEnd < release { envelope *= toEnd / release }
            samples[i] = Float(Double(peak) * envelope * sin(2 * Double.pi * frequency * t))
            i += 1
        }
        return samples
    }

    public static func render(_ kind: MeditationChimeKind) -> [Float] {
        render(frequency: kind.frequency, seconds: kind.seconds)
    }

    /// The samples as a WAV file in memory: 16-bit mono PCM.
    public static func wav(_ samples: [Float], sampleRate: Double = sampleRate) -> Data {
        let dataBytes = samples.count * 2
        var data = Data()
        data.reserveCapacity(44 + dataBytes)
        func append(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        append("RIFF")
        append32(UInt32(36 + dataBytes))
        append("WAVE")
        append("fmt ")
        append32(16)
        append16(1)
        append16(1)
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate) * 2)
        append16(2)
        append16(16)
        append("data")
        append32(UInt32(dataBytes))
        for sample in samples {
            let clipped = min(max(sample, -1), 1)
            append16(UInt16(bitPattern: Int16((clipped * Float(Int16.max)).rounded())))
        }
        return data
    }
}
