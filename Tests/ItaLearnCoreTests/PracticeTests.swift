import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import ItaLearnCore

private func pack() -> PracticePack {
    PracticePack(flashcards: (0..<4).map { Flashcard(id: "card-\($0)", swedish: "En kaffe", italian: "Un caffè", example: "Vorrei un caffè.") },
                 puzzles: (0..<3).map { SentencePuzzle(id: "puzzle-\($0)", swedish: "Jag vill ha en kaffe", answers: [["Vorrei", "un", "caffè."]], words: ["caffè.", "Vorrei", "un", "una"], explanation: "Caffè är maskulint: un caffè.") })
}

@Suite("Practice contracts and Markdown")
struct PracticeContractTests {
    @Test func oldSessionJSONDecodesWithoutNewFields() throws {
        let session = LessonSession(planID: UUID(), lessonID: "legacy")
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
        for key in ["wrapUp", "wrapUpRequested", "practice"] { json.removeValue(forKey: key) }
        let restored = try JSONDecoder().decode(LessonSession.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.wrapUp == nil)
        #expect(restored.practice == nil)
        #expect(restored.id == session.id)
    }

    @Test func wrapUpHasAnAnswerBudgetAndDoesNotImplyMastery() throws {
        var session = LessonSession(planID: UUID(), lessonID: "lesson")
        session.messages = (0..<8).map { _ in ChatMessage(role: .user, text: "Ciao") }
        #expect(session.shouldWrapUp(objectiveCount: 2))
        let review = LessonWrapUp(summary: "Bra övat", strengths: [], nextSteps: ["Öva verb"], demonstratedObjectives: [0], readyToAdvance: false)
        try session.finish(review, objectiveCount: 2)
        #expect(!session.isComplete)
        #expect(session.wrapUp != nil)
        #expect(!session.shouldWrapUp(objectiveCount: 2))
    }

    @Test func unresolvedRetryAndMissingEvidenceCannotUnlockNextLesson() throws {
        var session = LessonSession(planID: UUID(), lessonID: "lesson")
        session.messages = [ChatMessage(role: .user, text: "Uno"), ChatMessage(role: .user, text: "Due")]
        let ready = LessonWrapUp(summary: "Bra", strengths: [], nextSteps: ["Fortsätt"], demonstratedObjectives: [0, 1], readyToAdvance: true)
        session.requiresRetry = true
        try session.finish(ready, objectiveCount: 2)
        #expect(!session.isComplete)
        var invalid = ready
        invalid.demonstratedObjectives = [0]
        #expect(throws: LearningValidationError.self) { try invalid.validate(objectiveCount: 2) }
    }

    @Test func validatesAllAnswersAgainstAvailableTileMultiplicity() throws {
        try pack().validate()
        var invalid = pack()
        invalid.puzzles[0].answers = [["un", "un", "caffè."]]
        #expect(throws: LearningValidationError.self) { try invalid.validate() }
        invalid.puzzles[0].words.append("un")
        try invalid.validate()
        invalid.puzzles[0].words = ["un caffè", "Vorrei", "un"]
        #expect(throws: LearningValidationError.self) { try invalid.validate() }
    }

    @Test func duplicateTilesCanMoveWithoutDuplicationOrLoss() {
        var assembly = WordAssembly()
        assembly.place(0, wordCount: 4)
        assembly.place(1, wordCount: 4)
        assembly.place(2, wordCount: 4)
        assembly.place(2, before: 0, wordCount: 4)
        #expect(assembly.selected == [2, 0, 1])
        assembly.place(2, wordCount: 4)
        #expect(assembly.selected == [0, 1, 2])
        assembly.place(9, wordCount: 4)
        #expect(assembly.selected.count == 3)
        assembly.remove(1)
        #expect(assembly.selected == [0, 2])
    }

    @Test func sentenceCheckingHandlesAlternativesAndItalianAccents() {
        var puzzle = pack().puzzles[0]
        #expect(puzzle.matches(["vorrei", "un", "caffè"]))
        #expect(!puzzle.matches(["Vorrei", "un", "caffe"]))
        #expect(!puzzle.matches(["un", "Vorrei", "caffè."]))
        puzzle.answers.append(["un", "caffè.", "Vorrei"])
        #expect(puzzle.matches(["Un", "caffè", "vorrei"]))
    }

    @Test func markdownRendersEmphasisAndCorrectionsPreserveUnchangedWords() throws {
        let text = LearningMarkdown.attributed("**Alle** betyder ~~från~~ vid.\nProva igen.")
        #expect(String(text.characters) == "Alle betyder från vid.\nProva igen.")
        #expect(text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        let changes = LearningMarkdown.changes(original: "Il museo chiude dal 18:00", corrected: "Il museo chiude alle 18:00")
        #expect(changes.filter { $0.kind == .removed }.map(\.text) == ["dal"])
        #expect(changes.filter { $0.kind == .added }.map(\.text) == ["alle"])
        #expect(changes.filter { $0.kind == .unchanged }.count == 4)
        #expect(LearningMarkdown.changes(original: "caffe", corrected: "caffè").count == 2)
        let rendered = LearningMarkdown.correction(original: "Sono bene", corrected: "Sto bene")
        #expect(rendered.runs.contains { $0.strikethroughStyle != nil })
        #expect(rendered.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    }
}

private actor ActivityService: LearningService {
    var summaries = 0
    var teaching = 0
    var generations = 0
    var failSummary = false
    func setFailure() { failSummary = true }
    func question(_ context: AssessmentContext) async throws -> AssessmentQuestion { throw OpenAIError.server }
    func assess(_ context: AssessmentContext) async throws -> StructuredResponse<AssessmentResult> { throw OpenAIError.server }
    func teach(_ context: LessonContext) async throws -> LessonReply {
        teaching += 1
        return LessonReply(italian: "Bene.", swedish: "Bra.", correction: nil, requiresRetry: false, retryPrompt: "", objectiveIDsAchieved: [], lessonComplete: false, memory: "Övade verb")
    }
    func wrapUp(_ context: LessonContext) async throws -> LessonWrapUp {
        summaries += 1
        if failSummary { failSummary = false; throw OpenAIError.connection }
        return LessonWrapUp(summary: "Du har övat hälsningar och frågor.", strengths: ["Du svarar rätt"], nextSteps: ["Fortsätt till nästa lektion"], demonstratedObjectives: Array(context.lesson.objectives.indices), readyToAdvance: true)
    }
    func practice(_ context: LessonContext) async throws -> PracticePack { generations += 1; return pack() }
}

@MainActor @Suite("Saved wrap-up and practice")
struct ActivityStoreTests {
    private func fixture(answers: Int) throws -> (ModelContainer, LearningStore, UUID, TutorSettings) {
        let container = try ModelContainer(for: LearningSnapshot.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let store = LearningStore()
        store.load(container: container)
        let lesson = PlannedLesson(id: "test", title: "Test", summary: "Öva", objectives: ["Hälsa", "Fråga"], prerequisites: [], vocabulary: [], scenario: "Al bar", successCriteria: ["Svara"])
        let plan = LearningPlan(profile: LearnerProfile(nativeLanguage: "sv", targetLanguage: "it", cefr: "A1", goal: "Resa", strengths: [], focusAreas: []), lessons: [lesson])
        var session = LessonSession(planID: plan.id, lessonID: lesson.id)
        session.messages = (0..<answers).map { _ in ChatMessage(role: .user, text: "Ciao") }
        try store.update { $0.activePlan = plan; $0.sessions = [session] }
        let settings = TutorSettings(store: UserDefaults(suiteName: UUID().uuidString)!)
        return (container, store, session.id, settings)
    }

    @Test func restoredLongChatWrapsUpWithoutRequestingAnotherTeachingTurn() async throws {
        let (container, store, id, settings) = try fixture(answers: 10)
        let service = ActivityService()
        let chat = LearningChat(service: service)
        chat.lesson(store: store, sessionID: id, settings: settings)
        await chat.waitForCurrentRequest()
        #expect(await service.teaching == 0)
        #expect(await service.summaries == 1)
        #expect(store.state.activePlan?.completedLessonIDs.contains("test") == true)
        let reopened = LearningStore(); reopened.load(container: container)
        #expect(reopened.state.sessions[0].wrapUp?.summary == "Du har övat hälsningar och frågor.")
    }

    @Test func eighthAnswerAutomaticallySummarizes() async throws {
        let (_, store, id, settings) = try fixture(answers: 7)
        let service = ActivityService(); let chat = LearningChat(service: service)
        chat.lesson(store: store, sessionID: id, settings: settings, answer: "Come stai?")
        await chat.waitForCurrentRequest()
        #expect(await service.teaching == 1)
        #expect(await service.summaries == 1)
        #expect(store.state.sessions[0].answerCount == 8)
        #expect(store.state.sessions[0].wrapUp != nil)
    }

    @Test func failedSummaryResumesAfterReloadWithoutDuplicateAnswers() async throws {
        let (container, store, id, settings) = try fixture(answers: 3)
        let service = ActivityService(); await service.setFailure()
        let chat = LearningChat(service: service)
        chat.finishLesson(store: store, sessionID: id, settings: settings)
        await chat.waitForCurrentRequest()
        #expect(store.state.sessions[0].wrapUpRequested == true)
        #expect(store.state.activePlan?.completedLessonIDs.isEmpty == true)
        let reopened = LearningStore(); reopened.load(container: container)
        chat.lesson(store: reopened, sessionID: id, settings: settings)
        await chat.waitForCurrentRequest()
        #expect(await service.teaching == 0)
        #expect(reopened.state.sessions[0].answerCount == 3)
        #expect(reopened.state.sessions[0].wrapUp != nil)
    }

    @Test func generatedPackAndPracticeProgressSurviveReopenWithoutRegeneration() async throws {
        let (container, store, id, settings) = try fixture(answers: 3)
        let service = ActivityService(); let chat = LearningChat(service: service)
        chat.generatePractice(store: store, sessionID: id, settings: settings)
        await chat.waitForCurrentRequest()
        try store.update { $0.sessions[0].practice?.knownCardIDs.insert("card-0"); $0.sessions[0].practice?.solvedPuzzleIDs.insert("puzzle-0") }
        let reopened = LearningStore(); reopened.load(container: container)
        chat.generatePractice(store: reopened, sessionID: id, settings: settings)
        await chat.waitForCurrentRequest()
        #expect(await service.generations == 1)
        #expect(reopened.state.sessions[0].practice?.knownCardIDs == ["card-0"])
        #expect(reopened.state.sessions[0].practice?.solvedPuzzleIDs == ["puzzle-0"])
    }

    @Test func continueCreatesFreshRoundAndPreservesOldSummary() async throws {
        let (_, store, id, settings) = try fixture(answers: 3)
        let chat = LearningChat(service: ActivityService())
        chat.finishLesson(store: store, sessionID: id, settings: settings)
        await chat.waitForCurrentRequest()
        let next = try store.continueLesson(sessionID: id)
        #expect(next != id)
        #expect(store.state.sessions.count == 2)
        #expect(store.state.sessions[0].wrapUp != nil)
        #expect(store.state.sessions[1].wrapUp == nil)
        #expect(store.state.sessions[1].answerCount == 0)
    }
}
