#if DEBUG
import Foundation
import SoundCatalog

// For screenshots and UI tests (`-mockSound`): the same player, the same mixer and the same six
// sounds, but nothing reaches a speaker, so a simulator run is silent. The meter still reads the
// real synthesized sound, rendered here at the pace of the clock while the meter is on.

@MainActor
public final class SilentSoundEngine: SoundEngineDriving {
    private let renderer: SoundRenderer
    private var running = false
    private var handler: (@Sendable (Float) -> Void)?
    private var task: Task<Void, Never>?

    public init(renderer: SoundRenderer = SoundRenderer()) {
        self.renderer = renderer
    }

    public func start() throws {
        running = true
        runMeterIfWanted()
    }

    public func pause() {
        running = false
        task?.cancel()
        task = nil
    }

    public func stop() {
        pause()
    }

    public func send(_ command: SoundCommand) {
        renderer.apply(command)
    }

    public func setMeter(_ handler: (@Sendable (Float) -> Void)?) {
        self.handler = handler
        if handler == nil {
            task?.cancel()
            task = nil
        } else {
            runMeterIfWanted()
        }
    }

    public func rebuild() {
        pause()
    }

    private func runMeterIfWanted() {
        guard running, handler != nil, task == nil else { return }
        let renderer = renderer
        let frames = SoundSynth.sampleRate / 15
        task = Task { [weak self] in
            var left = [Float](repeating: 0, count: frames)
            var right = [Float](repeating: 0, count: frames)
            while !Task.isCancelled {
                let rms: Float = left.withUnsafeMutableBufferPointer { l in
                    right.withUnsafeMutableBufferPointer { r in
                        guard let lp = l.baseAddress, let rp = r.baseAddress else { return 0 }
                        renderer.renderStereo(left: lp, right: rp, count: frames)
                        var sum: Double = 0
                        for i in 0..<frames { sum += Double(lp[i]) * Double(lp[i]) + Double(rp[i]) * Double(rp[i]) }
                        return Float((sum / Double(frames * 2)).squareRoot())
                    }
                }
                self?.handler?(rms)
                try? await Task.sleep(for: .milliseconds(66))
            }
        }
    }
}

@MainActor
public final class SilentSoundSession: SoundSessionDriving {
    public var onEvent: ((SoundSessionEvent) -> Void)?

    public init() {}

    public func activate() throws {}

    public func deactivate() {}

    /// Plays the system's part: a call comes in, the headphones come out.
    public func emit(_ event: SoundSessionEvent) {
        onEvent?(event)
    }
}

@MainActor
public final class SilentNowPlaying: SoundNowPlayingDriving {
    public var onCommand: ((SoundRemoteCommand) -> Void)?

    public init() {}

    public func show(title: String, isPlaying: Bool) {}

    public func clear() {}
}

/// What `-mockSound` can ask for.
public struct MockSoundScript: Sendable, Equatable {
    public enum Mode: String, Sendable {
        /// Nothing playing.
        case silent
        case playing
        case interrupted
        /// Playing with the sleep timer running (`timer:rain:30`).
        case timer
        /// The real engine, at a low gain (`real:rain`), to look at the process's CPU.
        case real
    }

    public let mode: Mode
    public let kind: SoundKind
    public let minutes: Int

    /// "silent", "playing:rain", "interrupted:ocean", "timer:rain:30", "real:wind".
    public init?(argument: String) {
        let parts = argument.split(separator: ":").map(String.init)
        guard let mode = parts.first.flatMap(Mode.init(rawValue:)) else { return nil }
        self.mode = mode
        kind = parts.dropFirst().first.flatMap(SoundKind.init(rawValue:)) ?? .rain
        minutes = parts.dropFirst(2).first.flatMap(Int.init) ?? 30
    }
}
#endif
