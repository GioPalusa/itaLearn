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

    /// Clears every study: plans, lessons, sessions, practice and assessments.
    ///
    /// The API key is deliberately left alone; removing it is a separate action.
    func wipeAllStudies() throws {
        guard let context, isLoaded else { throw LearningValidationError.invalidResponse }
        try update { $0 = LearningState() }
        // Writing exercises predate the plan and live in their own model.
        try? context.delete(model: LessonRecord.self)
        try? context.save()
    }

    /// The newest saved assessment that actually carried a plan, if any.
    var restorableAssessment: SavedAssessment? {
        state.assessments.last { !$0.result.lessons.isEmpty }
    }

    /// Rebuilds the active plan from the last assessment that produced one.
    ///
    /// Saved assessments keep the full lesson list, so a plan that was replaced or
    /// lost can be reconstructed without asking the learner to redo a kunskapskoll.
    /// Completion is recovered from finished sessions rather than the replaced plan.
    func restorePlanFromLatestAssessment() throws {
        guard let assessment = restorableAssessment else { throw LearningValidationError.invalidResponse }
        try update { state in
            var plan = LearningPlan(
                createdAt: assessment.createdAt,
                profile: assessment.result.profile,
                lessons: assessment.result.lessons
            )
            let lessonIDs = Set(plan.lessons.map(\.id))
            let finished = state.sessions.filter { $0.isComplete }.map(\.lessonID)
            plan.completedLessonIDs = Set(finished).intersection(lessonIDs)
                .union(state.activePlan?.completedLessonIDs.intersection(lessonIDs) ?? [])

            if let current = state.activePlan, current.id != plan.id {
                state.archivedPlans.append(current)
            }
            // Sessions point at a plan id, so re-home them onto the restored plan.
            for index in state.sessions.indices where lessonIDs.contains(state.sessions[index].lessonID) {
                state.sessions[index].planID = plan.id
            }
            state.activePlan = plan
        }
    }

    /// Makes an archived plan active again, archiving whatever is active now.
    ///
    /// Sessions keep pointing at their own plan, so returning to an older path
    /// restores its lessons and its finished work together.
    func activateArchivedPlan(id: UUID) throws {
        try update { state in
            guard let position = state.archivedPlans.firstIndex(where: { $0.id == id }) else {
                throw LearningValidationError.invalidResponse
            }
            var restored = state.archivedPlans.remove(at: position)
            restored.archivedAt = nil
            if var current = state.activePlan {
                current.archivedAt = .now
                state.archivedPlans.append(current)
            }
            state.activePlan = restored
        }
    }

    /// Mutates one session's saved practice, so a round can resume exactly where it stopped.
    func updatePractice(sessionID: UUID, _ change: (inout PracticeProgress) -> Void) throws {
        try update { state in
            guard let index = state.sessions.firstIndex(where: { $0.id == sessionID }),
                  state.sessions[index].practice != nil else { throw LearningValidationError.invalidResponse }
            change(&state.sessions[index].practice!)
        }
    }

    /// Rolls every past sitting up into one entry per lesson.
    ///
    /// Sessions are already kept forever; this turns them into the compact record the
    /// teacher and practice prompts can actually use, newest lessons last and bounded
    /// so the request stays small.
    func learningHistory(excluding sessionID: UUID? = nil, limit: Int = 8) -> [LessonHistoryEntry] {
        let plans = ([state.activePlan].compactMap { $0 } + state.archivedPlans)
        let titles = Dictionary(
            plans.flatMap(\.lessons).map { ($0.id, $0.title) },
            uniquingKeysWith: { first, _ in first }
        )

        var order: [String] = []
        var grouped: [String: [LessonSession]] = [:]
        for session in state.sessions where session.id != sessionID {
            if grouped[session.lessonID] == nil { order.append(session.lessonID) }
            grouped[session.lessonID, default: []].append(session)
        }

        let entries = order.compactMap { lessonID -> LessonHistoryEntry? in
            guard let sessions = grouped[lessonID], let newest = sessions.last else { return nil }
            let practice = sessions.compactMap(\.practice).last
            let stumbled = practice.map { progress in
                progress.pack.puzzles
                    .filter { (progress.puzzleAttempts?[$0.id] ?? 0) > 1 }
                    .map(\.swedish)
                    .prefix(3)
                    .map { String($0.prefix(120)) }
            } ?? []

            return LessonHistoryEntry(
                lessonID: lessonID,
                lessonTitle: titles[lessonID] ?? lessonID,
                attempts: sessions.count,
                retries: sessions.reduce(0) { $0 + ($1.retryCount ?? 0) },
                completed: sessions.contains(where: \.isComplete),
                lastSummary: String((newest.wrapUp?.summary ?? newest.memory).prefix(600)),
                strengths: (newest.wrapUp?.strengths ?? []).prefix(3).map { String($0.prefix(200)) },
                nextSteps: (newest.wrapUp?.nextSteps ?? []).prefix(3).map { String($0.prefix(200)) },
                practiceSolved: practice?.solvedPuzzleIDs.count ?? 0,
                practiceTotal: practice?.pack.puzzles.count ?? 0,
                stumbledOn: Array(stumbled)
            )
        }
        return Array(entries.suffix(limit))
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
                             turnsRemaining: max(0, LessonSession.answerBudget - session.answerCount),
                             history: learningHistory(excluding: sessionID))
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
                recentLearningMemory: store.state.sessions.suffix(6).map(\.memory),
                lessonHistory: store.learningHistory()
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
                turnsRemaining: max(0, LessonSession.answerBudget - session.answerCount - (session.pendingAnswer == nil ? 0 : 1)),
                history: store.learningHistory(excluding: sessionID)
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

    /// Asks Milo for help on the sentence the learner is stuck on, and saves it with the puzzle.
    func requestHint(store: LearningStore, sessionID: UUID, settings: TutorSettings,
                     puzzle: SentencePuzzle, attempt: [String]) {
        guard !isWorking else { return }
        run {
            guard let session = store.state.sessions.first(where: { $0.id == sessionID }),
                  let practice = session.practice,
                  let plan = ([store.state.activePlan].compactMap { $0 } + store.state.archivedPlans)
                      .first(where: { $0.id == session.planID }) else {
                throw LearningValidationError.invalidResponse
            }
            let context = PuzzleHintContext(
                swedish: puzzle.swedish, words: puzzle.words, answers: puzzle.answers,
                attempt: attempt, attemptCount: practice.attempts(for: puzzle.id),
                explanation: puzzle.explanation, cefr: plan.profile.cefr,
                tone: settings.tone.modelInstruction
            )
            let hint = try await self.service.hint(context)
            try Task.checkCancellation()
            try hint.validate(words: puzzle.words)
            try store.updatePractice(sessionID: sessionID) { progress in
                progress.puzzleHints = (progress.puzzleHints ?? [:]).merging([puzzle.id: hint]) { _, new in new }
            }
        }
    }

    /// Generates another round of practice for the same lesson and appends what is new.
    func extendPractice(store: LearningStore, sessionID: UUID, settings: TutorSettings) {
        guard !isWorking, let practice = store.state.sessions.first(where: { $0.id == sessionID })?.practice else { return }
        run {
            let lessonContext = try store.lessonContext(sessionID: sessionID, settings: settings)
            let solved = practice.pack.puzzles.filter { practice.solvedPuzzleIDs.contains($0.id) }
            let unsolved = practice.pack.puzzles.filter { !practice.solvedPuzzleIDs.contains($0.id) }
            let context = PracticeExtensionContext(
                lesson: lessonContext,
                existingPuzzlePrompts: practice.pack.puzzles.map(\.swedish),
                existingFlashcardCues: practice.pack.flashcards.map(\.swedish),
                solvedPuzzlePrompts: solved.map(\.swedish),
                unsolvedPuzzlePrompts: unsolved.map(\.swedish)
            )
            let pack = try await self.service.morePractice(context)
            try Task.checkCancellation()
            try pack.validate()
            try store.updatePractice(sessionID: sessionID) { progress in
                progress.pack.append(pack)
            }
        }
    }

    /// Milo's suggested ways forward, once the learner has finished the plan.
    private(set) var directions: PlanDirections?

    func clearDirections() { directions = nil }

    /// Asks Milo which areas to practise next, based on how the plan actually went.
    func suggestDirections(store: LearningStore, settings: TutorSettings) {
        guard !isWorking, let plan = store.state.activePlan else { return }
        run {
            let open = plan.lessons.filter { !plan.completedLessonIDs.contains($0.id) }
            let context = PlanExtensionContext(
                profile: plan.profile,
                existingLessons: plan.lessons,
                history: store.learningHistory(),
                unfinishedLessonTitles: open.map(\.title),
                direction: nil
            )
            let suggested = try await self.service.planDirections(context)
            try Task.checkCancellation()
            try suggested.validate()
            self.directions = suggested
        }
    }

    /// Appends the next lessons to the current plan, built from the finished ones.
    ///
    /// The plan grows rather than being replaced, so completed lessons stay in place
    /// and remain open for revisiting.
    func extendPlan(store: LearningStore, settings: TutorSettings, direction: PlanDirection? = nil) {
        guard !isWorking, let plan = store.state.activePlan else { return }
        run {
            let done = plan.lessons.filter { plan.completedLessonIDs.contains($0.id) }
            let open = plan.lessons.filter { !plan.completedLessonIDs.contains($0.id) }
            let context = PlanExtensionContext(
                profile: plan.profile,
                existingLessons: plan.lessons,
                history: store.learningHistory(),
                unfinishedLessonTitles: open.map(\.title),
                direction: direction
            )
            guard !done.isEmpty else { throw LearningValidationError.invalidResponse }

            let extension_ = try await self.service.nextLessons(context)
            try Task.checkCancellation()
            try store.update { state in
                guard var current = state.activePlan, current.id == plan.id else {
                    throw LearningValidationError.invalidResponse
                }
                try extension_.validate(existingIDs: Set(current.lessons.map(\.id)))
                current.lessons.append(contentsOf: extension_.lessons)
                state.activePlan = current
            }
            self.directions = nil
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
