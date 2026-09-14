import Foundation
import SwiftData
import Testing
@testable import LangLearnCore

@MainActor @Suite("Journey persistence")
struct JourneyStoreTests {
    func fixture() throws -> (ModelContainer, LearningStore, UUID) {
        let container = try ModelContainer(for: LearningSnapshot.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let store = LearningStore(); store.load(container: container, language: .italian)
        var session = JourneySession(pack: journeyExamplePack()); session.cursor = 1
        try store.updateJourney { $0.profile = JourneyProfile(goal: "Resa"); $0.sessions.append(session) }
        return (container, store, session.id)
    }
    @Test func localScoringPersistsSupportAndKeepsLanguagesSeparate() throws {
        let (container, store, id) = try fixture()
        let coach = JourneyCoach()
        try store.editJourneySession(id) { $0.hintCount = 1 }
        coach.answer(store: store, sessionID: id, course: LanguageCourse(target: .italian, native: .swedish), answer: "hello")
        #expect(store.journey.observations.count == 1)
        #expect(store.journey.observations.first?.independent == false)
        #expect(store.journey.activeSession?.canAdvance == true)
        coach.answer(store: store, sessionID: id, course: LanguageCourse(target: .italian, native: .swedish), answer: "hello")
        #expect(store.journey.observations.count == 1)
        let restored = LearningStore(); restored.load(container: container, language: .italian)
        #expect(restored.journey == store.journey)
        restored.switchLanguage(to: .english)
        #expect(restored.journey.profile == nil)
        restored.switchLanguage(to: .italian)
        #expect(restored.journey.observations.count == 1)
    }
    @Test func listeningRequiresPlaybackAndTextSupportChangesEvidence() throws {
        let (_, store, id) = try fixture()
        try store.editJourneySession(id) { $0.pack.steps[1].kind = .listeningChoice; $0.pack.steps[1].skill = .listening }
        let coach = JourneyCoach()
        let course = LanguageCourse(target: .italian, native: .swedish)
        coach.answer(store: store, sessionID: id, course: course, answer: "hello")
        #expect(store.journey.observations.isEmpty)
        try store.editJourneySession(id) { $0.revealedText = true }
        coach.answer(store: store, sessionID: id, course: course, answer: "hello")
        #expect(store.journey.observations.first?.skill == .reading)
        #expect(store.journey.observations.first?.independent == false)
    }
    @Test func staleAndDuplicateAIResultsCannotOverwriteAnAttempt() throws {
        let (_, store, id) = try fixture()
        let attempt = UUID()
        try store.editJourneySession(id) { $0.cursor = 2; $0.pendingAnswer = "Ciao"; $0.pendingAttemptID = attempt }
        let result = JourneyEvaluation(stepID: "final", accepted: true, feedback: "En hälsning", correction: "", evidence: "Ciao")
        #expect(throws: LearningValidationError.self) { try store.recordJourneyAnswer(sessionID: id, attemptID: UUID(), answer: "Ciao", evaluation: result) }
        try store.recordJourneyAnswer(sessionID: id, attemptID: attempt, answer: "Ciao", evaluation: result)
        #expect(throws: LearningValidationError.self) { try store.recordJourneyAnswer(sessionID: id, attemptID: attempt, answer: "Ciao", evaluation: result) }
        #expect(store.journey.observations.count == 1)
        #expect(store.journey.activeSession?.pendingAttemptID == nil)
    }
    @Test func skippingSpeechDoesNotEstablishSpeakingAbility() throws {
        let (_, store, id) = try fixture()
        try store.editJourneySession(id) { $0.pack = FoundationContent.welcome(course: LanguageCourse(target: .italian, native: .swedish))!; $0.cursor = 2 }
        JourneyCoach().skipSpeech(store: store, sessionID: id)
        #expect(store.journey.observations.isEmpty)
        #expect(store.journey.sessions.first?.completedAt != nil)
    }
}
