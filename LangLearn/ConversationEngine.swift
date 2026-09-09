import AVFoundation
import Foundation
import Observation
import Speech

/// Dictation stays on-device; only the text the learner sends reaches OpenAI.
@MainActor @Observable
final class LessonSpeechInput {
    private(set) var isListening = false
    private(set) var isPreparing = false
    private(set) var partialTranscript = ""
    var errorMessage: String?
    /// The language being learned; dictation asks the system for its locale.
    var language: LearningLanguage = .italian
    private var transcriptionLocale = LearningLanguage.italian.locale
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var audioEngine: AVAudioEngine?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var feed: AnalyzerFeed?
    private var resultsTask: Task<String, Never>?
    private var analysisTask: Task<Void, Never>?

    /// Dictation needs `AnalyzerInputConverter`, which arrived in iOS 27. Rather
    /// than hand-rolling the conversion for one older release, the feature is
    /// simply absent below it and the UI hides the microphone.
    static var isSupported: Bool {
        if #available(iOS 27.0, visionOS 27.0, *) { SpeechTranscriber.isAvailable } else { false }
    }

    func begin(in language: LearningLanguage) async {
        self.language = language
        guard !isListening && !isPreparing else { return }
        isPreparing = true
        errorMessage = nil
        defer { isPreparing = false }
        guard #available(iOS 27.0, visionOS 27.0, *) else {
            errorMessage = "Diktering kräver iOS 27. Du kan skriva i stället."
            return
        }
        guard SpeechTranscriber.isAvailable else {
            errorMessage = "Taligenkänning är inte tillgänglig här. Du kan skriva i stället."
            return
        }
        guard await requestMicrophoneAccess() else {
            errorMessage = "Ge LangLearn mikrofonåtkomst i enhetens inställningar, eller skriv i stället."
            return
        }
        do {
            try Task.checkCancellation()
            try await prepareTranscriptionAssets()
            try Task.checkCancellation()
            partialTranscript = ""
            try await startTranscribing()
            try Task.checkCancellation()
            isListening = true
        } catch ConversationError.localeUnsupported {
            await tearDownListening()
            if !Task.isCancelled {
                errorMessage = "Diktering på \(language.displayName.lowercased()) finns inte på den här enheten. Du kan skriva i stället."
            }
        } catch {
            await tearDownListening()
            if !Task.isCancelled { errorMessage = "Mikrofonen kunde inte startas. Du kan skriva i stället." }
        }
    }

    func finish() async -> String {
        guard isListening else { return "" }
        isListening = false
        isPreparing = true
        defer { isPreparing = false }
        let text = await finishTranscribing()
        await tearDownListening()
        return text
    }

    func cancel() async {
        isListening = false
        await tearDownListening()
    }

    private func requestMicrophoneAccess() async -> Bool {
#if os(iOS) || os(visionOS)
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
#else
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
#endif
    }

    /// Reserves the locale being learned and downloads its on-device model if needed.
    private func prepareTranscriptionAssets() async throws {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: language.locale) else {
            throw ConversationError.localeUnsupported
        }
        transcriptionLocale = supported

        let probe = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [probe]) {
            try await request.downloadAndInstall()
        }
        try await AssetInventory.reserve(locale: supported)
    }

    @available(iOS 27.0, visionOS 27.0, *)
    private func startTranscribing() async throws {
        let transcriber = SpeechTranscriber(locale: transcriptionLocale, preset: .progressiveTranscription)
        let feed = try await Self.makeFeed(for: transcriber)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        self.transcriber = transcriber
        self.analyzer = analyzer
        self.feed = feed

        let (inputs, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation

        resultsTask = Task { [weak self] in
            var finalized = AttributedString()
            do {
                for try await result in transcriber.results {
                    if result.isFinal {
                        finalized.append(result.text)
                        self?.updatePartial(String(finalized.characters))
                    } else {
                        var preview = finalized
                        preview.append(result.text)
                        self?.updatePartial(String(preview.characters))
                    }
                }
            } catch {
                // Tearing the run down ends the stream; whatever was finalized
                // before that still counts as the learner's turn.
            }
            return String(finalized.characters)
        }

#if os(iOS) || os(visionOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers]
        )
        // Activating synchronously blocks the calling thread; the async form does not.
        try await audioSession.activate(options: [])
#endif

        let engine = AVAudioEngine()
        audioEngine = engine
        let inputNode = engine.inputNode

        // The tap runs on the audio render thread. AVAudioEngine serialises it,
        // so the feed is only ever touched from that one thread.
        //
        // iOS 27 deprecates this in favour of the throwing installTapOnBus:…:error:block:,
        // which this SDK only exposes under its `__`-prefixed name, so keep the classic tap.
        nonisolated(unsafe) let tapFeed = feed
        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: inputNode.outputFormat(forBus: 0)
        ) { buffer, time in
            guard let inputs = try? tapFeed.convert(buffer, time) else { return }
            for input in inputs {
                continuation.yield(input)
            }
        }

        engine.prepare()
        try engine.start()

        analysisTask = Task { [analyzer] in
            try? await analyzer.start(inputSequence: inputs)
        }
    }

    private func finishTranscribing() async -> String {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        if let feed, let continuation = inputContinuation {
            for input in (try? feed.flush()) ?? [] {
                continuation.yield(input)
            }
        }
        inputContinuation?.finish()
        inputContinuation = nil

        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        let heard = await resultsTask?.value ?? ""

        analyzer = nil
        transcriber = nil
        resultsTask = nil
        feed = nil
        return heard
    }

    private func tearDownListening() async {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputContinuation?.finish()
        inputContinuation = nil
        await analyzer?.cancelAndFinishNow()
        analyzer = nil
        transcriber = nil
        resultsTask?.cancel()
        resultsTask = nil
        analysisTask?.cancel()
        analysisTask = nil
        feed = nil

#if os(iOS) || os(visionOS)
        if #available(iOS 27.0, visionOS 27.0, *) {
            _ = try? await AVAudioSession.sharedInstance().deactivate(options: .notifyOthersOnDeactivation)
        }
#endif
    }

    private func updatePartial(_ text: String) {
        partialTranscript = text
    }

}

private enum ConversationError: Error { case localeUnsupported }

/// Turns microphone buffers into analyzer input.
///
/// The work is done by `AnalyzerInputConverter`, which exists only from iOS 27.
/// It is captured inside these closures rather than stored on the engine,
/// because its name cannot be spelled at all at the app's deployment target.
struct AnalyzerFeed {
    let convert: (AVAudioPCMBuffer, AVAudioTime?) throws -> [AnalyzerInput]
    let flush: () throws -> [AnalyzerInput]
}

@available(iOS 27.0, visionOS 27.0, *)
extension LessonSpeechInput {
    fileprivate static func makeFeed(for transcriber: SpeechTranscriber) async throws -> AnalyzerFeed {
        let converter = try await AnalyzerInputConverter.converter(compatibleWith: [transcriber])
        return AnalyzerFeed(
            convert: { try converter.convert($0, at: $1) },
            flush: { try converter.flush() }
        )
    }
}
