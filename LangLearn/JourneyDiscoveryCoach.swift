import Foundation
import Observation

@MainActor @Observable
final class JourneyDiscoveryCoach {
    private(set) var isWorking = false
    var errorMessage: String?
    private let service: any JourneyDiscoveryService
    private var task: Task<Void, Never>?
    private var generation = UUID()
    var requiresAPIKey: Bool { service.requiresAPIKey }

    init(service: any JourneyDiscoveryService = OpenAIDiscoveryService()) { self.service = service }
    func cancel() { generation = UUID(); task?.cancel(); task = nil; isWorking = false }
    func perform(_ work: () throws -> Void) {
        do { try work(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
    func begin(store: LearningStore, course: LanguageCourse) {
        if let saved = store.journey.discovery, saved.targetLanguage == course.target.code,
           saved.explanationLanguage == course.native.code, saved.stage != .finished { return }
        perform {
            try store.updateJourney {
                $0.discovery = JourneyDiscovery(targetLanguage: course.target.code, explanationLanguage: course.native.code,
                    story: $0.profile?.goal ?? store.state.activePlan?.profile.goal ?? "", minutes: $0.profile?.minutes ?? 5)
            }
        }
    }
    func edit(store: LearningStore, _ change: (inout JourneyDiscovery) throws -> Void) {
        perform {
            try store.updateJourney {
                guard var draft = $0.discovery, draft.targetLanguage == store.language?.code else { throw LearningValidationError.invalidResponse }
                try change(&draft); $0.discovery = draft
            }
        }
    }
    func restart(store: LearningStore) {
        cancel()
        edit(store: store) { $0.stage = .story; $0.turns = []; $0.draft = ""; $0.usedHelp = false; $0.heardAudio = false; $0.isLocalStart = false; $0.difficultyFeedback = nil }
    }
    func chooseReading(_ reading: JourneyProfile.Reading, store: LearningStore) {
        edit(store: store) {
            guard $0.stage == .script else { throw LearningValidationError.invalidResponse }
            $0.reading = reading
            $0.isLocalStart = $0.startsFromZero
            $0.stage = $0.startsFromZero ? .ready : .conversation
        }
    }
    func submit(store: LearningStore, course: LanguageCourse, text: String? = nil, choiceID: String? = nil, skip: Bool = false) {
        guard !isWorking, let discovery = store.journey.discovery, discovery.stage == .conversation else { return }
        if discovery.pending != nil { request(store: store, course: course); return }
        edit(store: store) { draft in
            guard draft.turns.count < 3 else { throw LearningValidationError.invalidResponse }
            let reply = draft.reply
            let answer = (text ?? draft.draft).trimmingCharacters(in: .whitespacesAndNewlines)
            var turn: DiscoveryTurn
            if draft.turns.isEmpty {
                turn = DiscoveryTurn(text: draft.story, source: .story)
            } else if skip {
                turn = DiscoveryTurn(text: "Jag vill gå vidare utan att svara på just den här uppgiften.", source: .skip)
            } else if answer.isEmpty, draft.difficultyFeedback == .tooHard, choiceID == nil {
                turn = DiscoveryTurn(text: "Det här är för svårt för mig. Jag vill prova en enklare uppgift.", source: .feedback)
            } else if reply?.mode == .listen, choiceID != nil {
                guard draft.heardAudio || draft.usedHelp, let choice = reply?.choices.first(where: { $0.id == choiceID }) else { throw LearningValidationError.invalidResponse }
                turn = DiscoveryTurn(text: choice.text, source: .listening, usedHelp: draft.usedHelp,
                                     heardAudio: draft.heardAudio, correctChoice: choiceID == reply?.correctChoiceID)
            } else {
                guard !answer.isEmpty, answer.count <= 700 else { throw LearningValidationError.invalidResponse }
                turn = DiscoveryTurn(text: answer, source: reply?.kind == .question ? .clarification : reply?.mode == .listen ? .openResponse : .writing, usedHelp: draft.usedHelp, heardAudio: draft.heardAudio)
            }
            turn.usedHelp = draft.usedHelp; turn.heardAudio = draft.heardAudio
            turn.difficultyFeedback = draft.difficultyFeedback
            draft.turns.append(turn)
        }
        guard errorMessage == nil else { return }
        request(store: store, course: course)
    }
    private func request(store: LearningStore, course: LanguageCourse) {
        guard let discovery = store.journey.discovery, let pending = discovery.pending else { return }
        cancel(); let token = generation
        let previous = store.journey.profile
        isWorking = true; errorMessage = nil
        task = Task {
            defer { if generation == token { isWorking = false; task = nil } }
            do {
                let request = try DiscoveryRequest(course: course, discovery: discovery, previousProfile: previous, priorAssessment: store.state.activePlan?.profile)
                let reply = try await service.reply(to: request)
                try Task.checkCancellation()
                try reply.validate(for: request)
                guard generation == token, store.language == course.target, store.journey.profile == previous,
                      store.journey.discovery?.id == discovery.id, store.journey.discovery?.pending?.id == pending.id,
                      store.journey.discovery?.explanationLanguage == course.native.code else { return }
                try store.updateJourney {
                    guard var current = $0.discovery, !current.turns.isEmpty else { throw LearningValidationError.invalidResponse }
                    current.turns[current.turns.count - 1].reply = reply
                    current.stage = reply.kind == .recommendation ? .ready : .conversation
                    current.draft = ""; current.usedHelp = false; current.heardAudio = false; current.difficultyFeedback = nil
                    $0.discovery = current
                }
            } catch is CancellationError { }
            catch { if generation == token { errorMessage = error.localizedDescription } }
        }
    }
    func accept(store: LearningStore) -> Bool {
        perform {
            try store.updateJourney {
                guard let discovery = $0.discovery, discovery.targetLanguage == store.language?.code else { throw LearningValidationError.invalidResponse }
                $0.profile = try discovery.candidate(existing: $0.profile)
                $0.discovery?.stage = .finished
            }
        }
        return errorMessage == nil
    }
}
