import AVFoundation
import Foundation
import Observation

/// Uses the same local voice for audio and mouth animation, in whichever
/// language is being learned.
@MainActor @Observable
final class SpeechNarrator: NSObject, AVAudioPlayerDelegate {
    private(set) var playback = SpeechPlaybackState()
    private(set) var errorMessage: String?
    var isPreparing: Bool { playback.phase == .preparing }
    var isSpeaking: Bool { playback.phase == .playing }
    var mouthOpening: Float { playback.mouth }
    /// True while the speaker needs a place on screen: getting ready, playing, or
    /// holding a failure the learner can retry.
    var needsStage: Bool { isPreparing || isSpeaking || errorMessage != nil }
    @ObservationIgnored private var synthesizer: AVSpeechSynthesizer?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var writer: SpeechAudioWriter?
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var completion: (() -> Void)?
    @ObservationIgnored private var lastText = ""
    /// Retrying has to reach for the same voice, not a default one.
    @ObservationIgnored private var lastLanguage: LearningLanguage?
    @ObservationIgnored private var audioSessionToken: UUID?

    override init() {
        super.init()
#if os(iOS) || os(visionOS)
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted(_:)),
                                               name: AVAudioSession.interruptionNotification, object: nil)
#endif
    }

    deinit { NotificationCenter.default.removeObserver(self) }

#if os(iOS) || os(visionOS)
    @objc nonisolated private func interrupted(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              raw == AVAudioSession.InterruptionType.began.rawValue else { return }
        Task { @MainActor [weak self] in self?.stop() }
    }
#endif

    func speak(_ text: String, in language: LearningLanguage, completion: (() -> Void)? = nil) {
        stop()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        errorMessage = nil; lastText = text; lastLanguage = language; self.completion = completion
        let token = playback.begin()
        let writer = SpeechAudioWriter()
        self.writer = writer
        let synthesizer = AVSpeechSynthesizer()
        self.synthesizer = synthesizer
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(for: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        utterance.postUtteranceDelay = 0.1
        synthesizer.write(utterance, toBufferCallback: Self.bufferHandler(writer: writer) { result in
            Self.deliverPreparation(result: result, token: token, to: self)
        })
        timeoutTask = Task.detached(priority: .utility) { [token] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            await Self.timeoutFail(token: token, on: self)
        }
    }

    nonisolated private static func deliverPreparation(
        result: Result<URL, Error>, token: UUID, to narrator: SpeechNarrator
    ) {
        Task { @MainActor [result, token] in
            narrator.prepared(result, token: token)
        }
    }

    nonisolated private static func timeoutFail(token: UUID, on narrator: SpeechNarrator) async {
        await MainActor.run {
            narrator.fail(token)
        }
    }

    func retry() {
        guard let lastLanguage else { return }
        speak(lastText, in: lastLanguage)
    }

    func stop() {
        playback.cancel()
        completion = nil
        releaseAudio()
    }

    private func prepared(_ result: Result<URL, Error>, token: UUID) {
        guard token == playback.generation, playback.phase == .preparing else { return }
        timeoutTask?.cancel(); timeoutTask = nil
        do {
            let url = try result.get()
            Task { @MainActor [weak self] in
                await self?.startPlaybackIfPossible(url: url, token: token)
            }
        } catch { fail(token) }
    }

    @MainActor private func startPlaybackIfPossible(url: URL, token: UUID) async {
        guard token == playback.generation, playback.phase == .preparing else { return }
        do {
#if os(iOS) || os(visionOS)
            // Register ownership before suspension so stop() also releases a pending activation.
            audioSessionToken = token
            try await Self.audioSession.acquire(token)
            guard token == playback.generation, playback.phase == .preparing else { return }
#endif
            let player = try await Self.preparePlayer(url: url)
            guard token == playback.generation, playback.phase == .preparing else {
                await Self.stopPlayer(player)
                return
            }
            player.delegate = self
            self.player = player
            guard player.play(), playback.start(token) else { fail(token); return }
            meterTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
                    guard let self, token == self.playback.generation, let player = self.player else { return }
                    player.updateMeters()
                    self.playback.meter(decibels: player.averagePower(forChannel: 0), token: token)
                }
            }
        } catch { fail(token) }
    }

    /// AVAudioPlayer is Sendable in the SDK. Only this task owns it until preparation finishes.
    nonisolated private static func preparePlayer(url: URL) async throws -> AVAudioPlayer {
        try await Task.detached(priority: .userInitiated) {
            let player = try AVAudioPlayer(contentsOf: url)
            player.isMeteringEnabled = true
            guard player.prepareToPlay() else { throw SpeechSessionError.preparationFailed }
            return player
        }.value
    }

    nonisolated private static func stopPlayer(_ player: AVAudioPlayer?) async {
        guard let player else { return }
        await Task.detached(priority: .userInitiated) { player.stop() }.value
    }

#if os(iOS) || os(visionOS)
    @ObservationIgnored private static let audioSession = SpeechSessionCoordinator(
        activate: {
            // Category configuration also blocks while the audio route changes.
            try await Task.detached(priority: .userInitiated) {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            }.value
            if #available(iOS 27.0, visionOS 27.0, *) {
                guard try await AVAudioSession.sharedInstance().activate(options: []) else { throw SpeechSessionError.activationFailed }
            } else {
                try await Task.detached(priority: .userInitiated) {
                    try AVAudioSession.sharedInstance().setActive(true)
                }.value
            }
        },
        deactivate: {
            if #available(iOS 27.0, visionOS 27.0, *) {
                guard try await AVAudioSession.sharedInstance().deactivate(options: .notifyOthersOnDeactivation) else { throw SpeechSessionError.activationFailed }
            } else {
                try await Task.detached(priority: .userInitiated) {
                    try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                }.value
            }
        }
    )
#endif

    private func fail(_ token: UUID) {
        guard playback.finish(token) else { return }
        completion = nil
        releaseAudio()
        errorMessage = "Uppläsningen kunde inte starta. Försök igen."
    }

    private func releaseAudio() {
        meterTask?.cancel(); meterTask = nil
        timeoutTask?.cancel(); timeoutTask = nil
        let retiredPlayer = player; player = nil
        // Invalidate the writer before stopping synthesis, whose terminal callback may run immediately.
        writer?.cancel(); writer = nil
        synthesizer?.stopSpeaking(at: .immediate); synthesizer = nil
#if os(iOS) || os(visionOS)
        if let token = audioSessionToken {
            audioSessionToken = nil
            Self.audioSession.release(token, stopPlayback: { await Self.stopPlayer(retiredPlayer) })
        } else {
            Task { await Self.stopPlayer(retiredPlayer) }
        }
#else
        Task { await Self.stopPlayer(retiredPlayer) }
#endif
    }

    /// Voice lookup walks every installed voice, so the best match per language is cached.
    @ObservationIgnored private static var voices: [String: AVSpeechSynthesisVoice?] = [:]

    private static func voice(for language: LearningLanguage) -> AVSpeechSynthesisVoice? {
        if let cached = voices[language.code] { return cached }
        let candidates = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language.code) }
        let best = candidates.first { $0.quality == .premium }
            ?? candidates.first { $0.quality == .enhanced }
            ?? candidates.first
            ?? AVSpeechSynthesisVoice(language: language.localeIdentifier)
        voices[language.code] = best
        return best
    }

    nonisolated private static func bufferHandler(
        writer: SpeechAudioWriter,
        completed: @escaping @Sendable (Result<URL, Error>) -> Void
    ) -> AVSpeechSynthesizer.BufferCallback {
        { buffer in
            if let result = writer.append(buffer) { completed(result) }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.player, ObjectIdentifier(current) == identity else { return }
            let token = self.playback.generation
            if !flag { self.fail(token); return }
            guard self.playback.finish(token) else { return }
            let callback = self.completion; self.completion = nil
            self.releaseAudio(); callback?()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.player, ObjectIdentifier(current) == identity else { return }
            self.fail(self.playback.generation)
        }
    }
}

/// AVSpeech delivers PCM buffers on its own callback queue. No audio buffer crosses actors.
/// Locking serializes writes, terminal callbacks and cancellation; only a file URL leaves this object.
nonisolated final class SpeechAudioWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let url = FileManager.default.temporaryDirectory.appendingPathComponent("langlearn-speech-\(UUID()).caf")
    private var file: AVAudioFile?
    private var closed = false

    func append(_ buffer: AVAudioBuffer) -> Result<URL, Error>? {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return nil }
        guard let pcm = buffer as? AVAudioPCMBuffer else {
            closed = true; return .failure(AudioError.invalidBuffer)
        }
        if pcm.frameLength == 0 {
            closed = true
            guard file != nil else { return .failure(AudioError.empty) }
            file = nil // Flush/close before handing the URL to the player.
            return .success(url)
        }
        do {
            if file == nil {
                file = try AVAudioFile(forWriting: url, settings: pcm.format.settings,
                                       commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved)
            }
            try file?.write(from: pcm)
            return nil
        } catch { closed = true; file = nil; return .failure(error) }
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        closed = true; file = nil
        try? FileManager.default.removeItem(at: url)
    }
    deinit { cancel() }
    private enum AudioError: Error { case invalidBuffer, empty }
}

nonisolated enum SpeechSessionError: Error { case activationFailed, preparationFailed }

/// Serializes shared-session changes across awaits. A stale stop cannot deactivate a newer speaker.
@MainActor final class SpeechSessionCoordinator {
    private let activate: @Sendable () async throws -> Void
    private let deactivate: @Sendable () async throws -> Void
    private var tail: Task<Void, Error>?
    private var owner: UUID?

    init(activate: @escaping @Sendable () async throws -> Void, deactivate: @escaping @Sendable () async throws -> Void) {
        self.activate = activate; self.deactivate = deactivate
    }
    func acquire(_ token: UUID) async throws {
        let previous = tail
        let operation = Task {
            _ = try? await previous?.value
            try await activate()
            owner = token
        }
        tail = operation
        try await operation.value
    }
    @discardableResult func release(_ token: UUID, stopPlayback: @escaping @Sendable () async -> Void = {}) -> Task<Void, Error> {
        let previous = tail
        let operation = Task {
            _ = try? await previous?.value
            await stopPlayback()
            guard owner == token else { return }
            try await deactivate()
            owner = nil
        }
        tail = operation
        return operation
    }
}
