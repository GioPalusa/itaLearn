import AVFoundation
import Foundation
import Observation
import Speech

/// Italian dictation stays on-device; only the text the learner sends reaches OpenAI.
@MainActor @Observable
final class LessonSpeechInput {
    private(set) var isListening = false
    private(set) var isPreparing = false
    private(set) var partialTranscript = ""
    var errorMessage: String?
    private let requestedLocale = Locale(identifier: "it-IT")
    private var transcriptionLocale = Locale(identifier: "it-IT")
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var audioEngine: AVAudioEngine?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AnalyzerInputConverter?
    private var resultsTask: Task<String, Never>?
    private var analysisTask: Task<Void, Never>?

    func begin() async {
        guard !isListening && !isPreparing else { return }
        isPreparing = true
        errorMessage = nil
        defer { isPreparing = false }
        guard SpeechTranscriber.isAvailable else {
            errorMessage = "Taligenkänning är inte tillgänglig här. Du kan skriva i stället."
            return
        }
        guard await requestMicrophoneAccess() else {
            errorMessage = "Ge ItaLearn mikrofonåtkomst i enhetens inställningar, eller skriv i stället."
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

    /// Reserves the Italian locale and downloads its on-device model if needed.
    private func prepareTranscriptionAssets() async throws {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw ConversationError.localeUnsupported
        }
        transcriptionLocale = supported

        let probe = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [probe]) {
            try await request.downloadAndInstall()
        }
        try await AssetInventory.reserve(locale: supported)
    }

    private func startTranscribing() async throws {
        let transcriber = SpeechTranscriber(locale: transcriptionLocale, preset: .progressiveTranscription)
        let converter = try await AnalyzerInputConverter.converter(compatibleWith: [transcriber])
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        self.transcriber = transcriber
        self.analyzer = analyzer
        self.converter = converter

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
        // Activating synchronously blocks the main thread; the async form does not.
        try await audioSession.activate(options: [])
#endif

        let engine = AVAudioEngine()
        audioEngine = engine
        let inputNode = engine.inputNode

        // The tap runs on the audio render thread. AVAudioEngine serialises it,
        // so the converter is only ever touched from that one thread.
        //
        // iOS 27 deprecates this in favour of the throwing installTapOnBus:…:error:block:,
        // which this SDK only exposes under its `__`-prefixed name, so keep the classic tap.
        nonisolated(unsafe) let tapConverter = converter
        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: inputNode.outputFormat(forBus: 0)
        ) { buffer, time in
            guard let inputs = try? tapConverter.convert(buffer, at: time) else { return }
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

        if let converter, let continuation = inputContinuation {
            for input in (try? converter.flush()) ?? [] {
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
        converter = nil
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
        converter = nil

#if os(iOS) || os(visionOS)
        _ = try? await AVAudioSession.sharedInstance().deactivate(options: .notifyOthersOnDeactivation)
#endif
    }

    private func updatePartial(_ text: String) {
        partialTranscript = text
    }

}

private enum ConversationError: Error { case localeUnsupported }
