import Foundation
import SwiftData
import Testing
@testable import LangLearnCore

private func exercise() -> ExerciseHelpContext {
    ExerciseHelpContext(course: LanguageCourse(target: .italian, native: .swedish),
                        activity: .writing, task: "Berätta om din dag", tone: "Patient")
}

private actor HelpServiceStub: LearningService {
    var requests: [ExerciseHelpRequest] = []
    var failOnce: Bool
    var suspend: Bool
    var continuation: CheckedContinuation<ExerciseHelpReply, Never>?

    init(failOnce: Bool = false, suspend: Bool = false) {
        self.failOnce = failOnce
        self.suspend = suspend
    }
    func help(_ request: ExerciseHelpRequest) async throws -> ExerciseHelpReply {
        requests.append(request)
        if failOnce { failOnce = false; throw OpenAIError.connection }
        if suspend {
            return await withCheckedContinuation { continuation = $0 }
        }
        return ExerciseHelpReply(explanation: "Börja med ett ord om din morgon. La mattina betyder morgonen.")
    }
    func release() { continuation?.resume(returning: ExerciseHelpReply(explanation: "Ett sent svar")); continuation = nil }
    func waiting() -> Bool { continuation != nil }
    func question(_ context: AssessmentContext) async throws -> AssessmentQuestion { throw OpenAIError.server }
    func assess(_ context: AssessmentContext) async throws -> StructuredResponse<AssessmentResult> { throw OpenAIError.server }
    func teach(_ context: LessonContext) async throws -> LessonReply { throw OpenAIError.server }
}

@MainActor @Suite("Beginner exercise help")
struct ExerciseHelpTests {
    @Test func emptyDraftAndNativeLanguageFollowUpsUseSeparateHistory() async throws {
        let service = HelpServiceStub()
        let help = ExerciseHelpSession(service: service)
        help.ask(.getStarted, question: "", exercise: exercise())
        await help.waitForCurrentRequest()
        #expect(help.exchanges.count == 1)
        for _ in 0..<8 {
            help.ask(.followUp, question: "Vad betyder morgon?", exercise: exercise())
            await help.waitForCurrentRequest()
        }
        let requests = await service.requests
        #expect(requests.first?.exercise.draft == "")
        #expect(requests.first?.question == "")
        #expect(requests.last?.question == "Vad betyder morgon?")
        #expect(requests.last?.previousHelp.count == 6)
        #expect(help.errorMessage == nil)
    }

    @Test func failedRequestRetriesSameSnapshotWithoutDuplicatingAnExchange() async throws {
        let service = HelpServiceStub(failOnce: true)
        let help = ExerciseHelpSession(service: service)
        var context = exercise()
        context.draft = "Io"
        help.ask(.hint, question: "Hur fortsätter jag?", exercise: context)
        await help.waitForCurrentRequest()
        #expect(help.errorMessage != nil)
        #expect(help.exchanges.isEmpty)
        help.retry()
        await help.waitForCurrentRequest()
        let requests = await service.requests
        #expect(requests.count == 2)
        #expect(requests.map(\.exercise.draft) == ["Io", "Io"])
        #expect(requests.map(\.question) == ["Hur fortsätter jag?", "Hur fortsätter jag?"])
        #expect(help.exchanges.count == 1)
        #expect(help.pendingRequest == nil)
        #expect(help.errorMessage == nil)
    }

    @Test func reopenedHelpKeepsItsTipAndUsesItForFollowUp() async throws {
        let first = ExerciseHelpExchange(kind: .hint, question: "",
                                         answer: "Börja med ordet io.")
        let service = HelpServiceStub()
        let help = ExerciseHelpSession(service: service, exchanges: [first])
        #expect(help.exchanges.map(\.answer) == ["Börja med ordet io."])

        help.ask(.followUp, question: "Kan du förklara enklare?", exercise: exercise())
        await help.waitForCurrentRequest()

        let request = await service.requests.first
        #expect(request?.previousHelp.map(\.answer) == ["Börja med ordet io."])
        #expect(help.exchanges.count == 2)
    }

    @Test func dismissalRejectsLateReplyEvenIfServiceIgnoresCancellation() async throws {
        let service = HelpServiceStub(suspend: true)
        let help = ExerciseHelpSession(service: service)
        help.ask(.explain, question: "", exercise: exercise())
        while !(await service.waiting()) { await Task.yield() }
        let completion = Task { await help.waitForCurrentRequest() }
        await Task.yield()
        help.cancel()
        await service.release()
        await completion.value
        #expect(help.exchanges.isEmpty)
        #expect(!help.isWorking)
        #expect(help.errorMessage == nil)
    }

    @Test func rejectsEmptyRepliesAndInvalidQuestions() async throws {
        #expect(throws: LearningValidationError.self) { try ExerciseHelpReply(explanation: " \n ").validate() }
        #expect(throws: LearningValidationError.self) { try ExerciseHelpReply(explanation: String(repeating: "x", count: 6001)).validate() }
        let service = HelpServiceStub()
        let help = ExerciseHelpSession(service: service)
        help.ask(.followUp, question: " \n ", exercise: exercise())
        help.ask(.meaning, question: String(repeating: "x", count: 2001), exercise: exercise())
        #expect(await service.requests.isEmpty)
    }

    @Test func lessonContextContainsRetryAndDraftWithoutChangingProgress() async throws {
        let container = try ModelContainer(for: LearningSnapshot.self, configurations:
            ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let store = LearningStore()
        store.load(container: container, language: .italian)
        let defaults = UserDefaults(suiteName: "ExerciseHelpTests.\(UUID())")!
        let settings = TutorSettings(store: defaults)
        settings.targetLanguage = .italian
        settings.nativeLanguage = .swedish
        let lesson = PlannedLesson(id: "hello", title: "Hälsa", summary: "Hälsa på en vän",
                                   objectives: ["Hälsa"], prerequisites: [], vocabulary: ["ciao"],
                                   scenario: "En vän", successCriteria: ["Svara själv"])
        let plan = LearningPlan(profile: LearnerProfile(nativeLanguage: "sv", targetLanguage: "it",
                                                       cefr: "pre-A1", goal: "Resa", strengths: [], focusAreas: []), lessons: [lesson])
        let session = LessonSession(planID: plan.id, lessonID: lesson.id, messages: [
            ChatMessage(role: .assistant, text: "Come stai?", translation: "Hur mår du?", needsRetry: true)
        ], requiresRetry: true)
        try store.update { $0.activePlan = plan; $0.sessions = [session] }
        let before = try JSONEncoder().encode(store.state)
        let context = store.helpContext(settings: settings, activity: .lesson, task: lesson.title,
                                        draft: "Jag vet inte hur jag börjar", sessionID: session.id)
        let help = ExerciseHelpSession(service: HelpServiceStub())
        help.ask(.getStarted, question: "", exercise: context)
        await help.waitForCurrentRequest()
        #expect(context.lesson?.awaitingRetry == true)
        #expect(context.profile?.cefr == "pre-A1")
        #expect(context.lesson?.recentMessages.last?.text == "Come stai?")
        #expect(context.draft == "Jag vet inte hur jag börjar")
        // Compare decoded state to avoid depending on JSON object key order.
        let after = try JSONEncoder().encode(store.state)
        #expect(try NSDictionary(dictionary: JSONSerialization.jsonObject(with: before) as! [String: Any])
            .isEqual(to: JSONSerialization.jsonObject(with: after) as! [String: Any]))
    }
}
