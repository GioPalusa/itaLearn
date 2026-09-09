import Foundation
import SwiftData
import Testing
@testable import ItaLearnCore

private func sampleResult() -> AssessmentResult {
    AssessmentResult(
        schemaVersion: 1, recommendation: .newPlan, rationale: "Vi börjar med enkla vardagssamtal.",
        profile: LearnerProfile(nativeLanguage: "sv", targetLanguage: "it", cefr: "A1", goal: "Prata på resan", strengths: ["Hälsningar"], focusAreas: ["Verb"]),
        lessons: (0..<3).map { index in
            PlannedLesson(id: "lesson-\(index)", title: "Lektion \(index)", summary: "Öva vardagsspråk",
                          objectives: ["Presentera dig", "Ställ en fråga"], prerequisites: index == 0 ? [] : ["lesson-\(index-1)"],
                          vocabulary: ["ciao"], scenario: "Al bar", successCriteria: ["Svara självständigt"])
        }
    )
}

private func completedAssessment() -> AssessmentSession {
    var session = AssessmentSession()
    for _ in 0..<6 { session.messages.append(ChatMessage(role: .user, text: "Ciao")) }
    return session
}

private func reply(retry: Bool = false, objectives: [Int] = [], complete: Bool = false) -> LessonReply {
    LessonReply(italian: "Come stai?", swedish: "Hur mår du?", correction: nil, requiresRetry: retry,
                retryPrompt: retry ? "Prova med sto." : "", objectiveIDsAchieved: objectives,
                lessonComplete: complete, memory: "Övar hälsningar")
}

@Suite("Learning contract and progression")
struct LearningContractTests {
    @Test func assessmentJSONRoundTripsAndRejectsIncompatibleVersions() throws {
        let result = sampleResult()
        let data = try JSONEncoder().encode(result)
        #expect(try JSONDecoder().decode(AssessmentResult.self, from: data) == result)
        try result.validate(hasCurrentPlan: false)
        var incompatible = result
        incompatible.schemaVersion = 2
        #expect(throws: LearningValidationError.self) { try incompatible.validate(hasCurrentPlan: false) }
    }

    @Test func rejectsDuplicateIDsForwardPrerequisitesAndEmptyObjectives() throws {
        var result = sampleResult()
        result.lessons[1].id = result.lessons[0].id
        #expect(throws: LearningValidationError.self) { try result.validate(hasCurrentPlan: false) }
        result = sampleResult()
        result.lessons[0].prerequisites = ["lesson-2"]
        #expect(throws: LearningValidationError.self) { try result.validate(hasCurrentPlan: false) }
        result = sampleResult()
        result.lessons[0].objectives = []
        #expect(throws: LearningValidationError.self) { try result.validate(hasCurrentPlan: false) }
    }

    @Test func cannotContinueWithoutAnExistingPlanOrFinishEarly() throws {
        var result = sampleResult()
        result.recommendation = .continueCurrent
        result.lessons = []
        #expect(throws: LearningValidationError.self) { try result.validate(hasCurrentPlan: false) }
        var state = LearningState()
        state.assessment = AssessmentSession()
        #expect(throws: LearningValidationError.self) { try state.apply(sampleResult(), rawJSON: Data()) }
        #expect(state.activePlan == nil)
        #expect(state.assessments.isEmpty)
    }

    @Test func continueCurrentPreservesPlanIdentityProgressAndConversations() throws {
        var state = LearningState()
        state.assessment = completedAssessment()
        try state.apply(sampleResult(), rawJSON: JSONEncoder().encode(sampleResult()))
        let id = try #require(state.activePlan?.id)
        state.activePlan?.completedLessonIDs.insert("lesson-0")
        let session = LessonSession(planID: id, lessonID: "lesson-0")
        state.sessions = [session]
        state.assessment = completedAssessment()
        var updated = sampleResult()
        updated.recommendation = .continueCurrent
        updated.lessons = []
        updated.profile.cefr = "A2"
        try state.apply(updated, rawJSON: JSONEncoder().encode(updated))
        #expect(state.activePlan?.id == id)
        #expect(state.activePlan?.completedLessonIDs == ["lesson-0"])
        #expect(state.activePlan?.profile.cefr == "A2")
        #expect(state.sessions.first?.id == session.id)
        #expect(state.assessments.count == 2)
        #expect(state.archivedPlans.isEmpty)
        #expect(state.assessment == nil)
    }

    @Test func replacementArchivesOldPlanAndKeepsItsProgress() throws {
        var state = LearningState()
        state.assessment = completedAssessment()
        try state.apply(sampleResult(), rawJSON: Data())
        let oldID = state.activePlan?.id
        state.activePlan?.completedLessonIDs.insert("lesson-0")
        state.assessment = completedAssessment()
        try state.apply(sampleResult(), rawJSON: Data())
        #expect(state.activePlan?.id != oldID)
        #expect(state.activePlan?.completedLessonIDs.isEmpty == true)
        #expect(state.archivedPlans.first?.id == oldID)
        #expect(state.archivedPlans.first?.completedLessonIDs == ["lesson-0"])
    }

    @Test func retryCannotAwardObjectivesOrCompleteLesson() throws {
        var invalid = reply(retry: true, complete: true)
        #expect(throws: LearningValidationError.self) { try invalid.validate(objectiveCount: 2) }
        invalid = reply(retry: true, objectives: [0])
        #expect(throws: LearningValidationError.self) { try invalid.validate(objectiveCount: 2) }
        invalid = reply(objectives: [2])
        #expect(throws: LearningValidationError.self) { try invalid.validate(objectiveCount: 2) }
    }

    @Test func learnerMustDemonstrateEveryObjectiveAcrossMultipleAnswers() throws {
        var session = LessonSession(planID: UUID(), lessonID: "lesson-0")
        try session.accept(reply(objectives: [0, 1], complete: true), objectiveCount: 2)
        #expect(session.achievedObjectives.isEmpty)
        #expect(!session.isComplete)
        session.pendingAnswer = "Ciao"
        try session.accept(reply(objectives: [0, 1], complete: true), objectiveCount: 2)
        #expect(!session.isComplete, "One answer must not complete the lesson")
        session.pendingAnswer = "Sono bene"
        try session.accept(reply(retry: true), objectiveCount: 2)
        #expect(session.requiresRetry)
        #expect(!session.isComplete)
        session.pendingAnswer = "Sto bene"
        try session.accept(reply(complete: true), objectiveCount: 2)
        #expect(session.isComplete)
        #expect(!session.requiresRetry)
        #expect(session.pendingAnswer == nil)
    }
}

private actor ScriptedService: LearningService {
    var questionCalls = 0
    var assessmentCalls = 0
    var lessonCalls = 0
    var failNextQuestion = false
    var failNextLesson = false
    var nextLessonReply = reply()
    var capturedLessonContext: LessonContext?
    func failQuestionOnce() { failNextQuestion = true }
    func failLessonOnce() { failNextLesson = true }
    func setReply(_ value: LessonReply) { nextLessonReply = value }
    func question(_ context: AssessmentContext) async throws -> AssessmentQuestion {
        questionCalls += 1
        if failNextQuestion { failNextQuestion = false; throw OpenAIError.connection }
        return AssessmentQuestion(question: "Fråga \(context.questionNumber)", translation: "", skill: "grammar")
    }
    func assess(_ context: AssessmentContext) async throws -> StructuredResponse<AssessmentResult> {
        assessmentCalls += 1
        return StructuredResponse(value: sampleResult(), json: try JSONEncoder().encode(sampleResult()))
    }
    func teach(_ context: LessonContext) async throws -> LessonReply {
        lessonCalls += 1
        capturedLessonContext = context
        if failNextLesson { failNextLesson = false; throw OpenAIError.connection }
        return nextLessonReply
    }
}

@MainActor
@Suite("Local persistence and resumable chats")
struct LearningStoreTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: LessonRecord.self, LearningSnapshot.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    @Test func sixAnswersGenerateExactlyFiveFollowupsAndOnePlan() async throws {
        let container = try container()
        let store = LearningStore()
        store.load(container: container)
        let service = ScriptedService()
        let chat = LearningChat(service: service)
        chat.assessment(store: store)
        await chat.waitForCurrentRequest()
        for _ in 0..<6 {
            chat.assessment(store: store, answer: "Ciao")
            await chat.waitForCurrentRequest()
            #expect(chat.errorMessage == nil)
        }
        #expect(await service.questionCalls == 5)
        #expect(await service.assessmentCalls == 1)
        #expect(store.state.activePlan?.lessons.count == 3)
        #expect(store.state.assessments.first?.messages.filter { $0.role == .user }.count == 6)
        let reopened = LearningStore()
        reopened.load(container: container)
        #expect(reopened.state.activePlan?.id == store.state.activePlan?.id)
        #expect(reopened.state.assessments.first?.resultJSON == store.state.assessments.first?.resultJSON)
        try reopened.beginAssessment()
        #expect(reopened.state.assessment?.answeredCount == 0, "A second assessment must start after the first one")
    }

    @Test func failedAnswerSurvivesReloadAndRetryDoesNotDuplicateIt() async throws {
        let container = try container()
        let store = LearningStore()
        store.load(container: container)
        let service = ScriptedService()
        await service.failQuestionOnce()
        let chat = LearningChat(service: service)
        chat.assessment(store: store, answer: "Mi chiamo Ada")
        await chat.waitForCurrentRequest()
        #expect(chat.errorMessage != nil)
        #expect(store.state.assessment?.answeredCount == 0)
        #expect(store.state.assessment?.pendingAnswer == "Mi chiamo Ada")
        let reopened = LearningStore()
        reopened.load(container: container)
        chat.assessment(store: reopened)
        await chat.waitForCurrentRequest()
        #expect(reopened.state.assessment?.answeredCount == 1)
        #expect(reopened.state.assessment?.pendingAnswer == nil)
        #expect(await service.questionCalls == 2)
    }

    @Test func lessonUsesBoundedContextAndKeepsRetryStateAcrossReload() async throws {
        let container = try container()
        let store = LearningStore()
        store.load(container: container)
        try store.update { state in
            state.assessment = completedAssessment()
            try state.apply(sampleResult(), rawJSON: Data())
        }
        let lesson = try #require(store.state.activePlan?.lessons.first)
        let sessionID = try store.lessonSession(for: lesson)
        try store.update { state in
            state.sessions[0].messages = (0..<50).map { _ in ChatMessage(role: .assistant, text: "Ciao") }
            state.sessions[0].memory = "Preserve the pending verb exercise"
        }
        let service = ScriptedService()
        await service.setReply(reply(retry: true))
        let chat = LearningChat(service: service)
        let settings = TutorSettings(store: UserDefaults(suiteName: UUID().uuidString)!)
        chat.lesson(store: store, sessionID: sessionID, settings: settings, answer: "Sono bene")
        await chat.waitForCurrentRequest()
        #expect(chat.errorMessage == nil)
        let captured = try #require(await service.capturedLessonContext)
        #expect(captured.recentMessages.count == 16)
        #expect(captured.memory == "Preserve the pending verb exercise")
        #expect(captured.lesson.id == lesson.id)
        let reopened = LearningStore()
        reopened.load(container: container)
        #expect(reopened.state.sessions[0].requiresRetry)
        #expect(reopened.state.activePlan?.completedLessonIDs.isEmpty == true)
        #expect(throws: LearningValidationError.self) {
            try reopened.lessonSession(for: sampleResult().lessons[1])
        }
    }

    @Test func corruptSnapshotIsNotOverwritten() throws {
        let container = try container()
        container.mainContext.insert(LearningSnapshot(payload: Data("broken JSON".utf8)))
        try container.mainContext.save()
        let store = LearningStore()
        store.load(container: container)
        #expect(!store.isLoaded)
        #expect(store.errorMessage != nil)
        #expect(throws: LearningValidationError.self) { try store.beginAssessment() }
        let snapshot = try #require(container.mainContext.fetch(FetchDescriptor<LearningSnapshot>()).first)
        #expect(snapshot.payload == Data("broken JSON".utf8))
    }

    @Test func existingWritingHistoryMigratesIntoExpandedDiskStore() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "learning.store")
        try autoreleasepool {
            let old = try ModelContainer(for: LessonRecord.self,
                                         configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            old.mainContext.insert(LessonRecord(lessonID: "old-lesson", lessonNumber: 1, lessonTitle: "Old lesson",
                                               prompt: "Ciao", attempt: "Ciao", correctedItalian: "Ciao", summary: "Saved before migration",
                                               strengths: [], nextSteps: [], score: 3))
            try old.mainContext.save()
        }
        let expanded = try ModelContainer(for: LessonRecord.self, LearningSnapshot.self,
                                          configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        #expect(try expanded.mainContext.fetch(FetchDescriptor<LessonRecord>()).first?.summary == "Saved before migration")
        let store = LearningStore()
        store.load(container: expanded)
        try store.beginAssessment()
        let reopened = LearningStore()
        reopened.load(container: expanded)
        #expect(reopened.state.assessment?.messages.count == 1)
    }
}

private actor DelayedQuestionService: LearningService {
    private var completion: CheckedContinuation<AssessmentQuestion, Error>?
    private var observer: CheckedContinuation<Void, Never>?
    private var started = false
    func question(_ context: AssessmentContext) async throws -> AssessmentQuestion {
        try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            started = true
            observer?.resume()
            observer = nil
        }
    }
    func waitUntilRequested() async {
        if started { return }
        await withCheckedContinuation { observer = $0 }
    }
    func release() {
        completion?.resume(returning: AssessmentQuestion(question: "Late reply", translation: "", skill: "grammar"))
        completion = nil
    }
    func assess(_ context: AssessmentContext) async throws -> StructuredResponse<AssessmentResult> {
        throw OpenAIError.server
    }
    func teach(_ context: LessonContext) async throws -> LessonReply { throw OpenAIError.server }
}

@MainActor
@Suite("Cancellation and answer recovery")
struct LearningRecoveryTests {
    @Test func cancelledRequestCannotSaveALateModelReply() async throws {
        let container = try ModelContainer(for: LearningSnapshot.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let store = LearningStore()
        store.load(container: container)
        let service = DelayedQuestionService()
        let chat = LearningChat(service: service)
        chat.assessment(store: store, answer: "Ciao")
        async let finished: Void = chat.waitForCurrentRequest()
        await service.waitUntilRequested()
        chat.cancel()
        await service.release()
        await finished
        #expect(store.state.assessment?.answeredCount == 0)
        #expect(store.state.assessment?.pendingAnswer == "Ciao")
        #expect(store.state.assessment?.messages.count == 1)
        #expect(!chat.isWorking)
        #expect(chat.errorMessage == nil)
    }

    @Test func learnerCanEditAFailedAnswerWithoutDuplicatingIt() async throws {
        let container = try ModelContainer(for: LearningSnapshot.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let store = LearningStore()
        store.load(container: container)
        let service = ScriptedService()
        await service.failQuestionOnce()
        let chat = LearningChat(service: service)
        chat.assessment(store: store, answer: "First attempt")
        await chat.waitForCurrentRequest()
        #expect(chat.recoverPendingAnswer(store: store, sessionID: nil) == "First attempt")
        #expect(store.state.assessment?.pendingAnswer == nil)
        chat.assessment(store: store, answer: "Revised attempt")
        await chat.waitForCurrentRequest()
        #expect(store.state.assessment?.answeredCount == 1)
        #expect(store.state.assessment?.messages.filter { $0.role == .user }.first?.text == "Revised attempt")
    }
}
