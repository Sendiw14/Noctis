import AVFoundation

/// S8: soft synthesized tones for onboarding's small moments — no audio
/// files, everything is a sine buffer generated on the fly. `.ambient`
/// respects the silent switch and mixes with whatever else is playing.
/// Any engine failure (no hardware, a route change mid-generation) is
/// swallowed — a missed sound is never worth surfacing, same policy as
/// `NoctisHaptics.swell()`.
public enum NoctisSound {
    /// User-facing toggle — off by default respects nothing, so callers
    /// should default this `true` and let Settings flip it.
    public static var isEnabled = true

    /// A slightly lower, firmer tick — an interactive snap (drag settling
    /// onto a value, a page-dot tap).
    public static func snap() {
        engine?.playTone(frequencies: [660], duration: 0.08, volume: 0.16)
    }

    /// A small three-note chord — a "this resolved nicely" moment.
    public static func chime() {
        engine?.playTone(frequencies: [660, 880, 990], duration: 0.4, volume: 0.12)
    }

    /// A slow rising low tone — pairs with `NoctisHaptics.swell()` for a
    /// genuine arrival (onboarding completing).
    public static func swell() {
        engine?.playTone(frequencies: [220], duration: 1.2, volume: 0.1, fadeIn: true)
    }

    /// `nil` only if this device can't even construct a mono 44.1kHz
    /// format (never observed in practice) — every call site above is a
    /// no-op in that case rather than crashing.
    private static let engine = NoctisSoundEngine()
}

private final class NoctisSoundEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate = 44100.0
    /// The exact format the player is wired to the mixer with — every
    /// buffer is built against this SAME instance. Passing `format: nil`
    /// to `connect` (the previous approach) lets the engine pick
    /// whatever the mixer's own format happens to be (commonly stereo),
    /// and scheduling a buffer built with a *different* format — mono, as
    /// every tone here is — throws
    /// "_outputFormat.channelCount == buffer.format.channelCount", a real,
    /// crash confirmed on-device via `NoctisSound.chime()` from
    /// `WelcomeScreen`'s Begin button.
    private let format: AVAudioFormat
    private var started = false
    private let lock = NSLock()

    init?() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return nil }
        self.format = format
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        } catch {
            // Best-effort — playback attempts below no-op if the session
            // never configures correctly.
        }
    }

    func playTone(frequencies: [Double], duration: Double, volume: Float, fadeIn: Bool = false) {
        guard NoctisSound.isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        ensureStarted()
        guard started else { return }

        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channelData = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = frameCount

        let attack = sampleRate * (fadeIn ? 0.35 : 0.006)
        let release = sampleRate * 0.03
        let total = Double(frameCount)
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let attackEnvelope = min(1, Double(frame) / max(attack, 1))
            let releaseEnvelope = min(1, (total - Double(frame)) / max(release, 1))
            let envelope = min(attackEnvelope, releaseEnvelope)
            var sample = 0.0
            for frequency in frequencies {
                sample += sin(2 * .pi * frequency * t)
            }
            sample /= Double(frequencies.count)
            channelData[frame] = Float(sample * envelope) * volume
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying {
            player.play()
        }
    }

    private func ensureStarted() {
        guard !started else { return }
        do {
            try engine.start()
            started = true
        } catch {
            started = false
        }
    }
}
