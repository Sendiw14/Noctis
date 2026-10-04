import AVFoundation
import Foundation
import MediaPlayer

// The real thing: AVAudioEngine, AVAudioSession and the lock screen's controls. Each closure the
// system will call on one of its own threads is made in a nonisolated type below, never inside a
// main-actor method, so it carries no actor isolation for the system to trip over.

// MARK: - The engine

/// Holds the engine. There is one `AVAudioSourceNode`, fed by the `SoundRenderer`, into the main
/// mixer. The engine exists only while something plays: pausing pauses it, stopping lets it go.
@MainActor
public final class AVSoundEngineDriver: SoundEngineDriving {
    private let renderer: SoundRenderer
    private var engine: AVAudioEngine?
    private var meter: SoundMeterTap?
    private var meterHandler: (@Sendable (Float) -> Void)?

    private static let format: AVAudioFormat = {
        // 44.1 kHz, two channels, one buffer a channel: what the sources are made at. The mixer
        // converts to whatever the hardware runs at.
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(SoundSynth.sampleRate), channels: 2, interleaved: false)
            ?? AVAudioFormat(standardFormatWithSampleRate: Double(SoundSynth.sampleRate), channels: 2) ?? AVAudioFormat()
    }()

    public init(renderer: SoundRenderer = SoundRenderer()) {
        self.renderer = renderer
    }

    public func start() throws {
        if engine == nil { build() }
        guard let engine else { return }
        if !engine.isRunning { try engine.start() }
        installMeterIfWanted()
    }

    public func pause() {
        removeMeter()
        engine?.pause()
    }

    public func stop() {
        removeMeter()
        engine?.stop()
        engine = nil
    }

    public func send(_ command: SoundCommand) {
        renderer.apply(command)
    }

    public func setMeter(_ handler: (@Sendable (Float) -> Void)?) {
        meterHandler = handler
        if handler == nil {
            removeMeter()
        } else if engine?.isRunning == true {
            installMeterIfWanted()
        }
    }

    public func rebuild() {
        removeMeter()
        engine?.stop()
        engine = nil
    }

    private func build() {
        let engine = AVAudioEngine()
        let node = renderer.makeSourceNode(format: Self.format)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: Self.format)
        engine.prepare()
        self.engine = engine
    }

    private func installMeterIfWanted() {
        guard let engine, let handler = meterHandler, meter == nil else { return }
        let tap = SoundMeterTap(handler: handler)
        tap.install(on: engine.mainMixerNode)
        meter = tap
    }

    private func removeMeter() {
        guard let engine, let tap = meter else { meter = nil; return }
        tap.remove(from: engine.mainMixerNode)
        meter = nil
    }
}

/// A tap on the mixer that reports a smoothed level 15 times a second. It exists only while the
/// Sounds screen is showing and playing; nothing is sampled otherwise (APP_RULES.md R31).
final class SoundMeterTap: @unchecked Sendable {
    /// The level is a window of this many frames' worth of the mixer's output: 1/15 s.
    static let reportsPerSecond = 15.0

    private let handler: @Sendable (Float) -> Void
    // Touched only by the tap's own thread.
    private var sumSquares: Double = 0
    private var frames = 0
    private var smoothed: Float = 0

    init(handler: @escaping @Sendable (Float) -> Void) {
        self.handler = handler
    }

    func install(on node: AVAudioMixerNode) {
        node.removeTap(onBus: 0)
        node.installTap(onBus: 0, bufferSize: 2048, format: nil) { [self] buffer, _ in
            consume(buffer)
        }
    }

    func remove(from node: AVAudioMixerNode) {
        node.removeTap(onBus: 0)
    }

    private func consume(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard count > 0, channelCount > 0 else { return }
        var sum: Double = 0
        for c in 0..<channelCount {
            let p = channels[c]
            for i in 0..<count { sum += Double(p[i]) * Double(p[i]) }
        }
        sumSquares += sum / Double(channelCount)
        frames += count
        let window = Int(buffer.format.sampleRate / Self.reportsPerSecond)
        if frames >= window {
            let rms = Float((sumSquares / Double(frames)).squareRoot())
            sumSquares = 0
            frames = 0
            handler(rms)
        }
    }
}

// MARK: - The session

@MainActor
public final class AVSoundSession: SoundSessionDriving {
    public var onEvent: ((SoundSessionEvent) -> Void)?
    private let mixWithOthers: Bool
    private var observer: SoundSessionObserver?

    /// `mixWithOthers` is off: a sleep sound takes the audio from whatever else is playing, as
    /// a music or podcast app would.
    public init(mixWithOthers: Bool = false) {
        self.mixWithOthers = mixWithOthers
        observer = SoundSessionObserver { [weak self] event in
            Task { @MainActor [weak self] in self?.onEvent?(event) }
        }
    }

    public func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: mixWithOthers ? [.mixWithOthers] : [])
        try session.setActive(true)
    }

    public func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Listens for the system's word about the audio session and says it in the player's terms.
final class SoundSessionObserver: @unchecked Sendable {
    private var tokens: [any NSObjectProtocol] = []

    init(handler: @escaping @Sendable (SoundSessionEvent) -> Void) {
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                handler(.interruptionBegan)
            case .ended:
                let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
                handler(.interruptionEnded(shouldResume: options.contains(.shouldResume)))
            @unknown default:
                break
            }
        })
        tokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
            handler(.routeLost)
        })
        tokens.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { _ in
            handler(.mediaServicesReset)
        })
    }

    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }
}

// MARK: - The lock screen

/// Now Playing (the title, "NOCTIS", no elapsed time: a sound has no length) and the play and
/// pause controls on the lock screen and the headphones.
@MainActor
public final class MediaNowPlaying: SoundNowPlayingDriving {
    public var onCommand: ((SoundRemoteCommand) -> Void)?
    private var bridge: RemoteCommandBridge?

    public init() {}

    public func show(title: String, isPlaying: Bool) {
        if bridge == nil {
            bridge = RemoteCommandBridge { [weak self] command in
                Task { @MainActor [weak self] in self?.onCommand?(command) }
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "NOCTIS",
            // A live sound: no duration, no scrubber, no elapsed time.
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    public func clear() {
        bridge = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}

/// Takes the play and pause commands, and leaves everything else (next, previous, seeking) off.
final class RemoteCommandBridge: @unchecked Sendable {
    private var targets: [(MPRemoteCommand, Any)] = []

    init(handler: @escaping @Sendable (SoundRemoteCommand) -> Void) {
        let center = MPRemoteCommandCenter.shared()
        for command in [center.nextTrackCommand, center.previousTrackCommand, center.seekForwardCommand, center.seekBackwardCommand,
                        center.skipForwardCommand, center.skipBackwardCommand, center.changePlaybackPositionCommand] {
            command.isEnabled = false
        }
        func add(_ command: MPRemoteCommand, _ mapped: SoundRemoteCommand) {
            command.isEnabled = true
            targets.append((command, command.addTarget { _ in
                handler(mapped)
                return .success
            }))
        }
        add(center.playCommand, .play)
        add(center.pauseCommand, .pause)
        add(center.togglePlayPauseCommand, .toggle)
    }

    deinit {
        for (command, target) in targets {
            command.removeTarget(target)
            command.isEnabled = false
        }
    }
}
