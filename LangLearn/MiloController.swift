import Foundation
import Observation

/// Stable command names for app code or a decoded function-call argument.
nonisolated enum MiloAction: String, Codable, Sendable {
    case idle, laugh, applaud, wave, think, listen, encourage, speak, stop
}

nonisolated struct MiloCommand: Codable, Equatable, Sendable {
    var action: MiloAction
    var text: String? = nil
    /// Language code from LearningLanguage.catalog, for example "it" or "sv".
    var language: String? = nil
}

nonisolated enum MiloCommandError: Error, Equatable {
    case missingSpeechText, unsupportedLanguage
}

/// Own one controller per live avatar. A new command replaces the previous one.
/// Reactions end on the renderer's timeline, so model loading cannot consume them.
@MainActor @Observable
final class MiloController {
    let narrator = SpeechNarrator()
    private(set) var reaction: MiloMood = .idle
    private(set) var trigger = 0

    var mood: MiloMood {
        if narrator.isSpeaking { return .speaking }
        if narrator.isPreparing { return .thinking }
        return reaction
    }

    func laugh() { react(.laughing) }
    func applaud() { react(.applauding) }
    func wave() { react(.greeting) }
    func think() { react(.thinking) }
    func listen() { react(.listening) }
    func encourage() { react(.encouraging) }
    func idle() { react(.idle) }

    func speak(_ text: String, in language: LearningLanguage) {
        stop()
        narrator.speak(text, in: language)
    }

    func stop() {
        narrator.stop()
        reaction = .idle
        trigger &+= 1
    }

    /// Validate before interrupting an existing reaction or spoken response.
    func perform(_ command: MiloCommand) throws {
        switch command.action {
        case .laugh: laugh()
        case .applaud: applaud()
        case .wave: wave()
        case .think: think()
        case .listen: listen()
        case .encourage: encourage()
        case .idle: idle()
        case .stop: stop()
        case .speak:
            guard let text = command.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MiloCommandError.missingSpeechText
            }
            guard let code = command.language, let language = LearningLanguage.named(code) else {
                throw MiloCommandError.unsupportedLanguage
            }
            speak(text, in: language)
        }
    }

    func perform(json data: Data) throws {
        try perform(JSONDecoder().decode(MiloCommand.self, from: data))
    }

    func animationCompleted(trigger completedTrigger: Int) {
        guard trigger == completedTrigger else { return }
        reaction = .idle
    }

    private func react(_ mood: MiloMood) {
        narrator.stop()
        reaction = mood
        trigger &+= 1
    }
}
