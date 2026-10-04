import AVFoundation
import Foundation
import SoundCatalog
import Synchronization

/// What the main thread asks of the audio thread: which sound, how loud, and how to get there.
public struct SoundCommand: Sendable, Equatable {
    /// The sound to play; nil for none.
    public var kind: SoundKind?
    /// The sound's own gain, 0...1.
    public var gain: Float
    /// The master fader's target, 0...1: 0 is silent. It is applied squared, so a fade is smooth.
    /// Nil leaves the fader where it is (a change of gain mustn't un-mute a pause).
    public var fader: Float?
    public var faderSeconds: Double
    /// How long to cross from the sound that was playing, when `kind` is a different one.
    public var crossfadeSeconds: Double

    public init(kind: SoundKind?, gain: Float, fader: Float? = 1, faderSeconds: Double = 0, crossfadeSeconds: Double = 0) {
        self.kind = kind
        self.gain = gain
        self.fader = fader
        self.faderSeconds = faderSeconds
        self.crossfadeSeconds = crossfadeSeconds
    }
}

/// The mixer on the audio thread (APP_RULES.md R31).
///
/// The audio thread's rule is that it never waits and never asks the system for anything: no
/// allocation, no lock, no Swift concurrency, no actor, no reference counting, no `Array`, no
/// `String`, no class property that Swift would police with a runtime access check. So:
///
/// - All of its state is a plain struct in one block of memory that was set aside in `init`,
///   reached through a pointer (which the runtime does not police).
/// - The main thread never touches that memory. It posts a command into a small mailbox of
///   atomics (a version number written last, read twice by the audio thread so a half-written
///   command is simply picked up on the next buffer) and the audio thread picks it up between
///   buffers.
/// - The sounds are the value-type voices of `SoundVoiceBank`; rendering is a `switch` and plain loops.
///
/// iOS 27 adds `AVAudioSourceNodeRenderBlockRealtimeSafe` and marks it unavailable to Swift
/// ("Swift is not supported for use with audio realtime threads"): this uses the ordinary
/// render block, which Swift can use, and a test (`SoundRealtimeSafetyTests`) hooks `malloc` on the
/// rendering thread to show that rendering allocates nothing.
public final class SoundRenderer: @unchecked Sendable {
    /// The most frames mixed at once; a longer buffer is mixed in pieces.
    static let chunk = 512

    struct MixState {
        var seenSerial: UInt32 = 0
        var kind: Int32 = -1
        var previous: Int32 = -1
        var gain: Float = 0
        var gainTarget: Float = 0
        var previousGain: Float = 0
        var fader: Float = 0
        var faderTarget: Float = 0
        var faderStep: Float = 0
        /// 0 at the start of a crossfade, 1 when it is over.
        var crossfade: Float = 1
        var crossfadeStep: Float = 0
    }

    // The mailbox. The serial is written last.
    private let serial = Atomic<UInt32>(0)
    private let mailKind = Atomic<Int32>(-1)
    private let mailGain = Atomic<UInt32>(0)
    private let mailFader = Atomic<UInt32>(0)
    private let mailFaderFrames = Atomic<Int32>(0)
    private let mailCrossfadeFrames = Atomic<Int32>(0)

    // The audio thread's.
    private let bank: SoundVoiceBank
    private let state: UnsafeMutablePointer<MixState>
    private let scratch: UnsafeMutablePointer<Float>

    public init() {
        bank = SoundVoiceBank()
        state = .allocate(capacity: 1)
        state.initialize(to: MixState())
        scratch = .allocate(capacity: Self.chunk * 4)
        scratch.initialize(repeating: 0, count: Self.chunk * 4)
    }

    /// For tests: a renderer whose sounds start from `seeds`.
    init(seeds: [SoundKind: UInt64]) {
        bank = SoundVoiceBank(seeds: seeds)
        state = .allocate(capacity: 1)
        state.initialize(to: MixState())
        scratch = .allocate(capacity: Self.chunk * 4)
        scratch.initialize(repeating: 0, count: Self.chunk * 4)
    }

    deinit {
        state.deinitialize(count: 1)
        state.deallocate()
        scratch.deallocate()
    }

    // MARK: Main thread

    /// Posts a command. Safe from any thread; the audio thread takes it between buffers.
    public func apply(_ command: SoundCommand) {
        let rate = Double(SoundSynth.sampleRate)
        mailKind.store(Int32(command.kind?.index ?? -1), ordering: .relaxed)
        mailGain.store(min(max(command.gain, 0), 1).bitPattern, ordering: .relaxed)
        var fader = Float.nan
        if let wanted = command.fader { fader = min(max(wanted, 0), 1) }
        mailFader.store(fader.bitPattern, ordering: .relaxed)
        mailFaderFrames.store(Int32(max(command.faderSeconds, 0) * rate), ordering: .relaxed)
        mailCrossfadeFrames.store(Int32(max(command.crossfadeSeconds, 0) * rate), ordering: .relaxed)
        serial.wrappingAdd(1, ordering: .releasing)
    }

    /// The node to attach to an engine. The block is made here, in a nonisolated class, so it
    /// carries no actor isolation for the audio thread to trip over.
    public func makeSourceNode(format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { [self] isSilence, _, frames, bufferList in
            render(isSilence: isSilence, frames: Int(frames), bufferList: bufferList)
        }
    }

    // MARK: Audio thread

    private func render(isSilence: UnsafeMutablePointer<ObjCBool>, frames: Int, bufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard buffers.count >= 1, let first = buffers[0].mData else { return noErr }
        let l = first.assumingMemoryBound(to: Float.self)
        let r: UnsafeMutablePointer<Float>
        if buffers.count >= 2, let second = buffers[1].mData {
            r = second.assumingMemoryBound(to: Float.self)
        } else {
            r = l
        }
        isSilence.pointee = ObjCBool(renderStereo(left: l, right: r, count: frames))
        return noErr
    }

    /// Mixes `count` frames. Returns true when they are all silent. Not for the main thread's use
    /// while an engine is pulling from the same renderer.
    @discardableResult
    func renderStereo(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, count: Int) -> Bool {
        poll()
        var silent = true
        var done = 0
        while done < count {
            let n = min(count - done, Self.chunk)
            if mix(left + done, right + done, n) { silent = silent && true } else { silent = false }
            done += n
        }
        return silent
    }

    private func poll() {
        let first = serial.load(ordering: .acquiring)
        if first == state.pointee.seenSerial { return }
        let kind = mailKind.load(ordering: .relaxed)
        let gain = Float(bitPattern: mailGain.load(ordering: .relaxed))
        let fader = Float(bitPattern: mailFader.load(ordering: .relaxed))
        let faderFrames = mailFaderFrames.load(ordering: .relaxed)
        let crossfadeFrames = mailCrossfadeFrames.load(ordering: .relaxed)
        // A command written while this was read is taken on the next buffer.
        if serial.load(ordering: .acquiring) != first { return }
        state.pointee.seenSerial = first

        if kind != state.pointee.kind {
            if crossfadeFrames > 0, state.pointee.kind >= 0, state.pointee.fader > 0.001 {
                state.pointee.previous = state.pointee.kind
                state.pointee.previousGain = state.pointee.gain
                state.pointee.crossfade = 0
                state.pointee.crossfadeStep = 1 / Float(crossfadeFrames)
            } else {
                state.pointee.previous = -1
                state.pointee.crossfade = 1
            }
            state.pointee.kind = kind
            state.pointee.gain = gain
        }
        state.pointee.gainTarget = gain
        // A NaN fader is "leave it".
        if !fader.isNaN {
            state.pointee.faderTarget = fader
            if faderFrames <= 0 {
                state.pointee.fader = fader
                state.pointee.faderStep = 0
            } else {
                state.pointee.faderStep = (fader - state.pointee.fader) / Float(faderFrames)
            }
        }
    }

    /// One piece. Returns true if it was silent.
    private func mix(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ n: Int) -> Bool {
        let st = state
        // Nothing to play, or faded all the way out: silence, and the voices don't run.
        if st.pointee.kind < 0 || (st.pointee.fader <= 0 && st.pointee.faderStep <= 0) {
            var z = 0
            while z < n {
                l[z] = 0
                r[z] = 0
                z += 1
            }
            if st.pointee.fader > 0 || st.pointee.faderStep > 0 { return false }
            return true
        }

        let aL = scratch
        let aR = scratch + Self.chunk
        let bL = scratch + Self.chunk * 2
        let bR = scratch + Self.chunk * 3
        bank.voices.pointee.render(Int(st.pointee.kind), aL, aR, n)

        let crossing = st.pointee.previous >= 0 && st.pointee.crossfade < 1
        var wIn0: Float = 1
        var wIn1: Float = 1
        var wOut0: Float = 0
        var wOut1: Float = 0
        var progressEnd: Float = 1
        if crossing {
            bank.voices.pointee.render(Int(st.pointee.previous), bL, bR, n)
            let p0 = st.pointee.crossfade
            progressEnd = min(p0 + st.pointee.crossfadeStep * Float(n), 1)
            // Equal power: two unrelated sounds keep their combined loudness while one takes over.
            wIn0 = sinf(p0 * .pi / 2)
            wIn1 = sinf(progressEnd * .pi / 2)
            wOut0 = cosf(p0 * .pi / 2)
            wOut1 = cosf(progressEnd * .pi / 2)
        }

        let previousGain = st.pointee.previousGain
        let inverse = 1 / Float(n)
        var i = 0
        while i < n {
            // The sound's gain glides to its target over about 30 ms, so a slider never clicks.
            st.pointee.gain += (st.pointee.gainTarget - st.pointee.gain) * 0.0008
            if st.pointee.faderStep != 0 {
                st.pointee.fader += st.pointee.faderStep
                if (st.pointee.faderStep > 0 && st.pointee.fader >= st.pointee.faderTarget)
                    || (st.pointee.faderStep < 0 && st.pointee.fader <= st.pointee.faderTarget) {
                    st.pointee.fader = st.pointee.faderTarget
                    st.pointee.faderStep = 0
                }
            }
            let master = st.pointee.fader * st.pointee.fader
            let t = Float(i) * inverse
            let weightIn = wIn0 + (wIn1 - wIn0) * t
            var sl = aL[i] * st.pointee.gain * weightIn
            var sr = aR[i] * st.pointee.gain * weightIn
            if crossing {
                let weightOut = wOut0 + (wOut1 - wOut0) * t
                sl += bL[i] * previousGain * weightOut
                sr += bR[i] * previousGain * weightOut
            }
            l[i] = Self.limit(sl * master)
            r[i] = Self.limit(sr * master)
            i += 1
        }

        if crossing {
            st.pointee.crossfade = progressEnd
            if progressEnd >= 1 { st.pointee.previous = -1 }
        }
        return false
    }

    /// Keeps a loud moment under full scale without touching anything below 0.9.
    @inline(__always)
    private static func limit(_ x: Float) -> Float {
        let a = abs(x)
        if a <= 0.9 { return x }
        let o = 0.9 + 0.1 * tanhf((a - 0.9) * 10)
        return x < 0 ? -o : o
    }
}
