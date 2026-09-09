import Foundation
import SwiftData
import Testing
@testable import LangLearnCore

private func plan(target: String) -> LearningPlan {
    LearningPlan(
        profile: LearnerProfile(nativeLanguage: "sv", targetLanguage: target, cefr: "A1",
                                goal: "Resa", strengths: [], focusAreas: []),
        lessons: []
    )
}

private func result(target: String) -> AssessmentResult {
    AssessmentResult(
        schemaVersion: 1, recommendation: .newPlan, rationale: "Vi börjar med enkla vardagssamtal.",
        profile: LearnerProfile(nativeLanguage: "sv", targetLanguage: target, cefr: "A1",
                                goal: "Prata på resan", strengths: [], focusAreas: []),
        lessons: (0..<3).map { index in
            PlannedLesson(id: "lesson-\(index)", title: "Lektion \(index)", summary: "Öva vardagsspråk",
                          objectives: ["Presentera dig"], prerequisites: index == 0 ? [] : ["lesson-\(index - 1)"],
                          vocabulary: [], scenario: "På kaféet", successCriteria: ["Svara självständigt"])
        }
    )
}

private func memoryContainer() throws -> ModelContainer {
    try ModelContainer(for: LessonRecord.self, LearningSnapshot.self,
                       configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
}

@Suite("Language selection")
struct LanguageSelectionTests {
    @Test func instructionsNameTheChosenPairAndNothingElse() {
        let course = LanguageCourse(target: .spanish, native: .english)
        let instructions = TeacherIdentity.instruction(for: course) + course.promptPreamble
        #expect(instructions.contains("Spanish teacher"))
        #expect(instructions.contains("English-speaking learner"))
        #expect(!instructions.contains("Italian"))
        #expect(!instructions.contains("Swedish"))
        // Habits worth correcting travel with the target language.
        #expect(course.promptPreamble.contains("ser and estar"))
        #expect(LanguageCourse.default.promptPreamble.contains("Sto bene"))
    }

    @Test func courseReachesTheModelAsDataToo() throws {
        let context = LessonContext(
            course: LanguageCourse(target: .japanese, native: .english),
            profile: plan(target: "ja").profile,
            lesson: PlannedLesson(id: "l", title: "T", summary: "S", objectives: [], prerequisites: [],
                                  vocabulary: [], scenario: "", successCriteria: []),
            recentMessages: [], learnerAnswer: nil, memory: "", achievedObjectives: [],
            awaitingRetry: false, tone: "", correctsSpelling: true
        )
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(context)) as? [String: Any]
        let course = json?["course"] as? [String: Any]
        #expect(course?["targetLanguage"] as? String == "Japanese")
        #expect(course?["explanationLanguage"] as? String == "English")
    }

    @Test func assessmentResultMustMatchTheChosenCourse() throws {
        let spanish = LanguageCourse(target: .spanish, native: .swedish)
        try result(target: "es").validate(hasCurrentPlan: false, course: spanish)
        #expect(throws: LearningValidationError.self) {
            try result(target: "es").validate(hasCurrentPlan: false, course: .default)
        }
        #expect(throws: LearningValidationError.self) {
            try result(target: "it").validate(hasCurrentPlan: false, course: spanish)
        }
    }

    @Test func assessmentSchemaPinsTheProfileToTheChosenCourse() throws {
        let schema = LearningSchema.assessment(for: LanguageCourse(target: .korean, native: .english))
        let properties = try #require(schema["properties"] as? [String: Any])
        let profile = try #require((properties["profile"] as? [String: Any])?["properties"] as? [String: Any])
        #expect((profile["targetLanguage"] as? [String: Any])?["enum"] as? [String] == ["ko"])
        #expect((profile["nativeLanguage"] as? [String: Any])?["enum"] as? [String] == ["en"])
    }

    @Test func practicePacksSavedBeforeMultilingualSupportStillDecode() throws {
        let legacy = """
        {"flashcards":[{"id":"c1","swedish":"En kaffe","italian":"Un caffè","example":"Vorrei un caffè."}],
         "puzzles":[{"id":"p1","swedish":"Jag vill ha en kaffe","answers":[["Vorrei","un","caffè."]],
                     "words":["Vorrei","un","caffè."],"explanation":"Caffè är maskulint."}]}
        """
        let pack = try JSONDecoder().decode(PracticePack.self, from: Data(legacy.utf8))
        #expect(pack.flashcards.first?.cue == "En kaffe")
        #expect(pack.flashcards.first?.answer == "Un caffè")
        #expect(pack.puzzles.first?.cue == "Jag vill ha en kaffe")

        // Saving again writes the language-neutral keys.
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(pack)) as? [String: Any]
        let card = try #require((encoded?["flashcards"] as? [[String: Any]])?.first)
        #expect(card["cue"] as? String == "En kaffe")
        #expect(card["answer"] as? String == "Un caffè")
        #expect(card["swedish"] == nil)
        #expect(card["italian"] == nil)
    }

    @Test func theOpeningQuestionNamesTheLanguageBeingLearned() {
        let opening = AssessmentSession(course: LanguageCourse(target: .french, native: .swedish))
            .messages.first?.text ?? ""
        // The name is spelled in the app's own UI language, whatever that is.
        #expect(opening.contains(LearningLanguage.french.displayName.lowercased()))
        #expect(!opening.contains(LearningLanguage.italian.displayName.lowercased()))
    }
}

@MainActor
@Suite("Studies are kept per language")
struct PerLanguageStudyTests {
    @Test func switchingLanguageSwapsPlansWithoutLosingEither() throws {
        let container = try memoryContainer()
        let store = LearningStore()
        store.load(container: container, language: .italian)
        let italian = plan(target: "it")
        try store.update { $0.activePlan = italian }

        store.switchLanguage(to: .spanish)
        #expect(store.state.activePlan == nil, "A newly chosen language starts from scratch")
        let spanish = plan(target: "es")
        try store.update { $0.activePlan = spanish }

        store.switchLanguage(to: .italian)
        #expect(store.state.activePlan?.id == italian.id)
        store.switchLanguage(to: .spanish)
        #expect(store.state.activePlan?.id == spanish.id)

        let reopened = LearningStore()
        reopened.load(container: container, language: .italian)
        #expect(reopened.state.activePlan?.id == italian.id)
    }

    @Test func studiesSavedBeforeLanguageSelectionLoadAsItalian() throws {
        let container = try memoryContainer()
        let context = ModelContext(container)
        var state = LearningState()
        state.activePlan = plan(target: "it")
        // A row written before LearningSnapshot carried a language code.
        context.insert(LearningSnapshot(payload: try JSONEncoder().encode(state)))
        try context.save()

        let store = LearningStore()
        store.load(container: container, language: .italian)
        #expect(store.state.activePlan?.id == state.activePlan?.id)

        store.switchLanguage(to: .german)
        #expect(store.state.activePlan == nil)
    }

    @Test func wipingStudiesClearsEveryLanguage() throws {
        let container = try memoryContainer()
        let store = LearningStore()
        store.load(container: container, language: .italian)
        try store.update { $0.activePlan = plan(target: "it") }
        store.switchLanguage(to: .spanish)
        try store.update { $0.activePlan = plan(target: "es") }

        try store.wipeAllStudies()
        #expect(store.state.activePlan == nil)
        store.switchLanguage(to: .italian)
        #expect(store.state.activePlan == nil, "The Italian studies go with the wipe")

        // Studies can be built again on the emptied store.
        try store.update { $0.activePlan = plan(target: "it") }
        #expect(store.state.activePlan != nil)
    }
}
