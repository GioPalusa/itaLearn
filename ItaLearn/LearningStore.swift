import Foundation
import Observation
import SwiftData

/// Added alongside LessonRecord so existing writing history remains readable.
@Model
final class LearningSnapshot {
    var id: UUID = UUID()
    var updatedAt: Date = Date()
    var payload: Data = Data()

    init(payload: Data) { self.payload = payload }
}

@MainActor @Observable
final class LearningStore {
    private(set) var state = LearningState()
    private(set) var isLoaded = false
    var errorMessage: String?
    private var context: ModelContext?
    private var snapshot: LearningSnapshot?

    func load(container: ModelContainer) {
        guard !isLoaded else { return }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let snapshots = try context.fetch(FetchDescriptor<LearningSnapshot>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            ))
            if let snapshot = snapshots.first {
                let decoded = try JSONDecoder().decode(LearningState.self, from: snapshot.payload)
                guard decoded.schemaVersion == 1 else { throw LearningValidationError.unsupportedVersion }
                state = decoded
                self.snapshot = snapshot
            }
            self.context = context
            isLoaded = true
            errorMessage = nil
        } catch {
            errorMessage = "Dina sparade studier kunde inte läsas. Inga data har skrivits över. \(error.localizedDescription)"
        }
    }

    /// Publish state only after an explicit successful disk save.
    func update(_ change: (inout LearningState) throws -> Void) throws {
        guard let context, isLoaded else { throw LearningValidationError.invalidResponse }
        var next = state
        try change(&next)
        let payload = try JSONEncoder().encode(next)
        let record = snapshot ?? LearningSnapshot(payload: payload)
        do {
            if snapshot == nil { context.insert(record) }
            record.payload = payload
            record.updatedAt = .now
            try context.save()
            snapshot = record
            state = next
            errorMessage = nil
        } catch {
            context.rollback()
            errorMessage = "Studierna kunde inte sparas på enheten. Försök igen."
            throw error
        }
    }

    func beginAssessment() throws {
        guard state.assessment == nil else { return }
        try update { $0.assessment = AssessmentSession() }
    }

    func lessonSession(for lesson: PlannedLesson) throws -> UUID {
        guard let plan = state.activePlan,
              plan.lessons.contains(where: { $0.id == lesson.id }),
              lesson.prerequisites.allSatisfy({ plan.completedLessonIDs.contains($0) }) else {
            throw LearningValidationError.invalidResponse
        }
        if let existing = state.sessions.last(where: { $0.planID == plan.id && $0.lessonID == lesson.id }) {
            return existing.id
        }
        let session = LessonSession(planID: plan.id, lessonID: lesson.id)
        try update { $0.sessions.append(session) }
        return session.id
    }
    func continueLesson(sessionID: UUID) throws -> UUID {
        guard let previous = state.sessions.first(where: { $0.id == sessionID }),
              previous.wrapUp != nil || previous.isComplete,
              state.activePlan?.id == previous.planID else { throw LearningValidationError.invalidResponse }
        var next = LessonSession(planID: previous.planID, lessonID: previous.lessonID)
        next.memory = previous.memory + "\n" + (previous.wrapUp?.summary ?? "")
        next.achievedObjectives = previous.achievedObjectives
        next.practice = previous.practice
        try update { $0.sessions.append(next) }
        return next.id
    }

    func lessonContext(sessionID: UUID, settings: TutorSettings) throws -> LessonContext {
        guard let session = state.sessions.first(where: { $0.id == sessionID }),
              let plan = ([state.activePlan].compactMap { $0 } + state.archivedPlans).first(where: { $0.id == session.planID }),
              let lesson = plan.lessons.first(where: { $0.id == session.lessonID }) else { throw LearningValidationError.invalidResponse }
        return LessonContext(profile: plan.profile, lesson: lesson,
                             recentMessages: Array(session.messages.suffix(32)), learnerAnswer: nil,
                             memory: session.memory, achievedObjectives: session.achievedObjectives.sorted(),
                             awaitingRetry: session.requiresRetry, tone: settings.tone.modelInstruction,
                             correctsSpelling: settings.correctsSpelling,
                             turnsRemaining: max(0, LessonSession.answerBudget - session.answerCount))
    }

}

/// Retains and cancels requests explicitly; failed requests leave a persisted pending answer.
@MainActor @Observable
final class LearningChat {
    private(set) var isWorking = false
    var errorMessage: String?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private let service: any LearningService

    init(service: any LearningService = OpenAILearningService()) { self.service = service }

    func waitForCurrentRequest() async { await task?.value }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        isWorking = false
    }

    func assessment(store: LearningStore, answer: String? = nil) {
        guard !isWorking else { return }
        run {
            try store.beginAssessment()
            if let answer {
                let trimmed = try Self.validatedAnswer(answer)
                guard store.state.assessment?.pendingAnswer == nil else { throw LearningValidationError.invalidResponse }
                try store.update { $0.assessment?.pendingAnswer = trimmed }
            }
            guard var interview = store.state.assessment else { return }
            if let pending = interview.pendingAnswer {
                interview.messages.append(ChatMessage(role: .user, text: pending))
            }
            // Opening is local. Subsequent questions and final assessment are generated by Sol.
            guard interview.pendingAnswer != nil || interview.answeredCount == AssessmentSession.questionCount else { return }
            let context = AssessmentContext(
                messages: interview.messages,
                questionNumber: interview.answeredCount + 1,
                currentPlan: store.state.activePlan,
                recentLearningMemory: store.state.sessions.suffix(6).map(\.memory)
            )
            if interview.answeredCount < AssessmentSession.questionCount {
                let question = try await self.service.question(context)
                try Task.checkCancellation()
                try question.validate()
                interview.pendingAnswer = nil
                interview.messages.append(ChatMessage(role: .assistant, text: question.question, translation: question.translation))
                let savedInterview = interview
                try store.update { $0.assessment = savedInterview }
            } else {
                let result = try await self.service.assess(context)
                try Task.checkCancellation()
                interview.pendingAnswer = nil
                let completedInterview = interview
                try store.update {
                    $0.assessment = completedInterview
                    try $0.apply(result.value, rawJSON: result.json)
                }
            }
        }
    }

    func lesson(store: LearningStore, sessionID: UUID, settings: TutorSettings, answer: String? = nil) {
        guard !isWorking else { return }
        guard let existing = store.state.sessions.first(where: { $0.id == sessionID }),
              existing.wrapUp == nil else { return }
        if existing.pendingAnswer == nil,
           let context = try? store.lessonContext(sessionID: sessionID, settings: settings),
           existing.shouldWrapUp(objectiveCount: context.lesson.objectives.count) {
            finishLesson(store: store, sessionID: sessionID, settings: settings)
            return
        }
        guard !existing.isComplete,
              answer != nil || existing.pendingAnswer != nil || existing.messages.isEmpty else { return }
        run {
            guard let index = store.state.sessions.firstIndex(where: { $0.id == sessionID }),
                  let plan = store.state.activePlan,
                  store.state.sessions[index].planID == plan.id,
                  let lesson = plan.lessons.first(where: { $0.id == store.state.sessions[index].lessonID }),
                  !store.state.sessions[index].isComplete else { return }
            if let answer {
                let trimmed = try Self.validatedAnswer(answer)
                guard store.state.sessions[index].pendingAnswer == nil else { throw LearningValidationError.invalidResponse }
                try store.update { $0.sessions[index].pendingAnswer = trimmed }
            }
            let session = store.state.sessions[index]
            guard session.messages.isEmpty || session.pendingAnswer != nil else { return }
            let context = LessonContext(
                profile: plan.profile, lesson: lesson,
                recentMessages: Array(session.messages.suffix(16)), learnerAnswer: session.pendingAnswer,
                memory: session.memory, achievedObjectives: session.achievedObjectives.sorted(),
                awaitingRetry: session.requiresRetry, tone: settings.tone.modelInstruction,
                correctsSpelling: settings.correctsSpelling,
                turnsRemaining: max(0, LessonSession.answerBudget - session.answerCount - (session.pendingAnswer == nil ? 0 : 1))
            )
            let reply = try await self.service.teach(context)
            try Task.checkCancellation()
            try store.update { state in
                try state.sessions[index].accept(reply, objectiveCount: lesson.objectives.count)
            }
            if store.state.sessions[index].shouldWrapUp(objectiveCount: lesson.objectives.count) {
                try await self.saveWrapUp(store: store, sessionID: sessionID, settings: settings)
            }
        }
    }

    func finishLesson(store: LearningStore, sessionID: UUID, settings: TutorSettings) {
        guard !isWorking else { return }
        run { try await self.saveWrapUp(store: store, sessionID: sessionID, settings: settings) }
    }

    private func saveWrapUp(store: LearningStore, sessionID: UUID, settings: TutorSettings) async throws {
        guard let session = store.state.sessions.first(where: { $0.id == sessionID }),
              session.wrapUp == nil, session.pendingAnswer == nil, session.answerCount >= 2 else { return }
        // Persist the request so cancellation/relaunch can resume only the summarization step.
        try store.update { state in
            guard let index = state.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
            state.sessions[index].wrapUpRequested = true
        }
        let context = try store.lessonContext(sessionID: sessionID, settings: settings)
        let summary = try await service.wrapUp(context)
        try Task.checkCancellation()
        try store.update { state in
            guard let index = state.sessions.firstIndex(where: { $0.id == sessionID }),
                  state.activePlan?.id == state.sessions[index].planID else { throw LearningValidationError.invalidResponse }
            try state.sessions[index].finish(summary, objectiveCount: context.lesson.objectives.count)
            if state.sessions[index].isComplete { state.activePlan?.completedLessonIDs.insert(context.lesson.id) }
        }
    }

    func generatePractice(store: LearningStore, sessionID: UUID, settings: TutorSettings) {
        guard !isWorking, store.state.sessions.first(where: { $0.id == sessionID })?.practice == nil else { return }
        run {
            let context = try store.lessonContext(sessionID: sessionID, settings: settings)
            let pack = try await self.service.practice(context)
            try Task.checkCancellation()
            try pack.validate()
            try store.update { state in
                guard let index = state.sessions.firstIndex(where: { $0.id == sessionID }) else { throw LearningValidationError.invalidResponse }
                state.sessions[index].practice = PracticeProgress(pack: pack)
            }
        }
    }

    /// Lets the learner edit a refused/failed answer without duplicating a submitted turn.
    func recoverPendingAnswer(store: LearningStore, sessionID: UUID?) -> String? {
        guard !isWorking else { return nil }
        let answer: String?
        if let sessionID { answer = store.state.sessions.first { $0.id == sessionID }?.pendingAnswer }
        else { answer = store.state.assessment?.pendingAnswer }
        do {
            try store.update { state in
                if let sessionID, let index = state.sessions.firstIndex(where: { $0.id == sessionID }) {
                    state.sessions[index].pendingAnswer = nil
                } else if sessionID == nil { state.assessment?.pendingAnswer = nil }
            }
            errorMessage = nil
            return answer
        } catch { errorMessage = store.errorMessage ?? error.localizedDescription; return nil }
    }

    private static func validatedAnswer(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2000 else { throw LearningValidationError.invalidResponse }
        return trimmed
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        isWorking = true
        errorMessage = nil
        let token = UUID()
        generation = token
        task = Task {
            defer {
                if generation == token { isWorking = false; task = nil }
            }
            do { try await work() }
            catch is CancellationError { }
            catch {
                if !Task.isCancelled && generation == token { errorMessage = error.localizedDescription }
            }
        }
    }
}
