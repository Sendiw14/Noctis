import AVFoundation
import Foundation
import NightKit
import OSLog

/// What the meditation sounds besides a sleep sound: soft chimes, and (if asked) the lines read aloud.
@MainActor
public protocol MeditationAudioPlaying: AnyObject {
    /// This device has a system voice to read with. The switch is only offered where it is true.
    var canSpeak: Bool { get }
    /// Get ready to sound: the audio session up (mixing with whatever else is playing), the chimes made.
    func prepare()
    func chime(_ kind: MeditationChimeKind)
    /// Reads `text` in the system voice, ending whatever was being read.
    func speak(_ text: String)
    /// Stops a line being read.
    func silence()
    /// All done: nothing sounding, and the session let go of if it was this that brought it up.
    func release()
}

/// Sounds nothing and remembers what it was asked. For tests and screenshots.
@MainActor
public final class SilentMeditationAudio: MeditationAudioPlaying {
    public enum Event: Equatable {
        case prepare
        case chime(MeditationChimeKind)
        case speak(String)
        case silence
        case release
    }

    public let canSpeak: Bool
    public private(set) var events: [Event] = []

    public init(canSpeak: Bool = true) {
        self.canSpeak = canSpeak
    }

    public func prepare() { events.append(.prepare) }
    public func chime(_ kind: MeditationChimeKind) { events.append(.chime(kind)) }
    public func speak(_ text: String) { events.append(.speak(text)) }
    public func silence() { events.append(.silence) }
    public func release() { events.append(.release) }

    public var chimes: [MeditationChimeKind] {
        events.compactMap { if case .chime(let kind) = $0 { kind } else { nil } }
    }

    public var spoken: [String] {
        events.compactMap { if case .speak(let text) = $0 { text } else { nil } }
    }
}

/// The real thing: chimes synthesized in code (`ChimeSynth`, a sine with a soft decay) held as in-memory
/// WAV data and played with `AVAudioPlayer`, and `AVSpeechSynthesizer` with the system voice. Its
/// session mixes with other audio and is only brought up here when no sleep sound has already done it.
@MainActor
public final class SystemMeditationAudio: MeditationAudioPlaying {
    private static let log = Logger(subsystem: "com.noctis.app", category: "meditation-audio")
    private let isSoundActive: () -> Bool
    private var players: [MeditationChimeKind: AVAudioPlayer] = [:]
    private let synthesizer = AVSpeechSynthesizer()
    private var activatedSession = false

    /// `isSoundActive`: a sleep sound is up, which means the audio session already is.
    public init(isSoundActive: @escaping () -> Bool = { false }) {
        self.isSoundActive = isSoundActive
    }

    public var canSpeak: Bool {
        !AVSpeechSynthesisVoice.speechVoices().isEmpty
    }

    public func prepare() {
        if !isSoundActive() {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
                activatedSession = true
            } catch {
                Self.log.error("could not start the audio session: \(String(describing: error), privacy: .public)")
            }
        }
        for kind in MeditationChimeKind.allCases { _ = player(for: kind) }
    }

    public func chime(_ kind: MeditationChimeKind) {
        guard let player = player(for: kind) else { return }
        player.currentTime = 0
        player.play()
    }

    public func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.82
        utterance.pitchMultiplier = 0.92
        utterance.volume = 0.8
        // After the chime that may have just sounded.
        utterance.preUtteranceDelay = 1.0
        synthesizer.speak(utterance)
    }

    public func silence() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    public func release() {
        silence()
        for player in players.values { player.stop() }
        if activatedSession, !isSoundActive() {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        activatedSession = false
    }

    private func player(for kind: MeditationChimeKind) -> AVAudioPlayer? {
        if let player = players[kind] { return player }
        do {
            let player = try AVAudioPlayer(data: ChimeSynth.wav(ChimeSynth.render(kind)))
            player.prepareToPlay()
            players[kind] = player
            return player
        } catch {
            Self.log.error("could not make the \(kind.rawValue, privacy: .public) chime: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
