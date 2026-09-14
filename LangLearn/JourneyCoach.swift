import Foundation
import Observation

extension LearningStore {
    var journey: JourneyProgress { state.journey ?? JourneyProgress() }

    func updateJourney(_ change: (inout JourneyProgress) throws -> Void) throws {
        try update { state in
            var progress = state.journey ?? JourneyProgress()
            try change(&progress)
            state.journey = progress
        }
    }

    func editJourneySession(_ id: UUID, stepID: String? = nil, _ change: (inout JourneySession) throws -> Void) throws {
        try updateJourney { progress in
            guard let index = progress.sessions.firstIndex(where: { $0.id == id }),
                  stepID == nil || progress.sessions[index].step?.id == stepID else { throw LearningValidationError.invalidResponse }
            try change(&progress.sessions[index])
        }
    }

    func recordJourneyAnswer(sessionID: UUID, attemptID: UUID, answer: String, evaluation: JourneyEvaluation, selfReported: Bool = false) throws {
        try updateJourney { progress in
            guard let index = progress.sessions.firstIndex(where: { $0.id == sessionID }),
                  let step = progress.sessions[index].step, step.id == evaluation.stepID,
                  !progress.sessions[index].canAdvance else { throw LearningValidationError.invalidResponse }
            var session = progress.sessions[index]
            if step.kind == .write {
                guard session.pendingAttemptID == attemptID, session.pendingAnswer == answer else { throw LearningValidationError.invalidResponse }
                try evaluation.validate(step: step, answer: answer)
            }
            let supported = session.hintCount > 0 || session.revealedText || session.attempts > 0 || step.kind == .build || (step.kind == .meaningChoice && session.heardAudio)
            let skill: JourneySkill = step.kind == .listeningChoice && session.revealedText ? .reading : step.skill
            progress.record(JourneyObservation(id: attemptID, skillID: step.skillID, title: step.skillTitle,
                skill: skill, correct: evaluation.accepted, independent: !supported && !selfReported,
                selfReported: selfReported, date: .now, phrase: step.target, translation: step.translation, sessionID: sessionID))
            session.evaluation = evaluation; session.attempts += 1
            session.pendingAttemptID = nil; session.pendingAnswer = nil
            progress.sessions[index] = session
        }
    }
}

/// Each visible lesson owns a coach. Canceled or superseded requests cannot publish to another course.
@MainActor @Observable
final class JourneyCoach {
    private(set) var isWorking = false
    var errorMessage: String?
    var openedSession: UUID?
    private let service: any JourneyService
    private var task: Task<Void, Never>?
    private var generation = UUID()

    init(service: any JourneyService = OpenAIJourneyService()) { self.service = service }

    func cancel() { generation = UUID(); task?.cancel(); task = nil; isWorking = false }

    func perform(_ work: () throws -> Void) {
        do { try work(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    func start(store: LearningStore, course: LanguageCourse, track: JourneyTrack, topic: String, tone: String, firstGreeting: Bool = false) {
        guard !isWorking else { return }
        cancel()
        let token = generation
        let profile = store.journey.profile
        isWorking = true; errorMessage = nil
        task = Task {
            defer { if generation == token { isWorking = false; task = nil } }
            do {
                let pack: JourneyPack
                if firstGreeting, let local = FoundationContent.welcome(course: course) { pack = local }
                else {
                    let request = try JourneyRequest(course: course, progress: store.journey, track: track, topic: topic, tone: tone)
                    pack = try await service.generate(request)
                    try request.validate(pack)
                }
                try Task.checkCancellation()
                guard generation == token, store.language == course.target, store.journey.profile == profile else { return }
                try pack.validate(course: course, track: track)
                let session = JourneySession(pack: pack)
                try store.updateJourney { $0.sessions.append(session) }
                openedSession = session.id
            } catch is CancellationError { }
            catch { if generation == token { errorMessage = error.localizedDescription } }
        }
    }

    func answer(store: LearningStore, sessionID: UUID, course: LanguageCourse, answer: String) {
        guard !isWorking, let session = store.journey.sessions.first(where: { $0.id == sessionID }),
              let step = session.step, !session.canAdvance, session.pack.targetLanguage == course.target.code else { return }
        if step.kind != .write {
            perform {
                guard step.kind != .example else { return }
                guard step.kind != .listeningChoice || session.heardAudio || session.revealedText else { throw LearningValidationError.invalidResponse }
                let correct: Bool
                switch step.kind {
                case .meaningChoice, .listeningChoice, .scriptChoice: correct = answer == step.correctChoiceID
                case .build: correct = step.acceptedAnswers.map(JourneyStep.normalized).contains(JourneyStep.normalized(answer))
                case .say: correct = true
                default: throw LearningValidationError.invalidResponse
                }
                let evaluation = JourneyEvaluation(stepID: step.id, accepted: correct, feedback: step.explanation,
                    correction: correct ? "" : step.translation, evidence: answer)
                try store.recordJourneyAnswer(sessionID: sessionID, attemptID: UUID(), answer: answer,
                                              evaluation: evaluation, selfReported: step.kind == .say)
            }
            return
        }
        let submitted = session.pendingAnswer ?? answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submitted.isEmpty, submitted.count <= 500 else { return }
        let attempt = session.pendingAttemptID ?? UUID()
        do {
            try store.editJourneySession(sessionID, stepID: step.id) { $0.pendingAttemptID = attempt; $0.pendingAnswer = submitted; $0.draft = submitted }
        } catch { errorMessage = error.localizedDescription; return }
        cancel(); let token = generation
        isWorking = true; errorMessage = nil
        task = Task {
            defer { if generation == token { isWorking = false; task = nil } }
            do {
                let result = try await service.evaluate(course: course, step: step, answer: submitted)
                try Task.checkCancellation()
                guard token == generation, store.language == course.target else { return }
                try store.recordJourneyAnswer(sessionID: sessionID, attemptID: attempt, answer: submitted, evaluation: result)
            } catch is CancellationError { }
            catch { if token == generation { errorMessage = error.localizedDescription } }
        }
    }

    func skipSpeech(store: LearningStore, sessionID: UUID) {
        perform {
            try store.editJourneySession(sessionID) { session in
                guard let step = session.step, step.kind == .say else { throw LearningValidationError.invalidResponse }
                session.evaluation = JourneyEvaluation(stepID: step.id, accepted: true, feedback: step.explanation, correction: "", evidence: "")
                try session.advance()
            }
        }
    }
}
