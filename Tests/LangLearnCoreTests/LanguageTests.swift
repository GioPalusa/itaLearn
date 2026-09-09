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
        let italian = LanguageCourse(target: .italian, native: .swedish)
        #expect(italian.promptPreamble.contains("Sto bene"))
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
            try result(target: "es").validate(hasCurrentPlan: false,
                                              course: LanguageCourse(target: .italian, native: .swedish))
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
        // Rows written before LearningSnapshot carried a language code read back
        // as "it", which is what those studies actually were.
        context.insert(LearningSnapshot(payload: try JSONEncoder().encode(state), languageCode: "it"))
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

@Suite("Neutral start and several languages at once")
struct MultiLanguageTests {
    private func freshSettings() -> (TutorSettings, UserDefaults) {
        let name = "LangLearn.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (TutorSettings(store: defaults), defaults)
    }

    @Test func firstRunPresumesNoLanguageToLearn() {
        let (settings, _) = freshSettings()
        #expect(settings.chosenTarget == nil, "The app must not pick a language on the learner's behalf")
        #expect(!settings.hasChosenLanguage)
    }

    @Test func choosingALanguageIsWhatUnlocksTheApp() {
        let (settings, _) = freshSettings()
        settings.startLearning(.finnish)
        #expect(settings.chosenTarget == .finnish)
        #expect(settings.hasChosenLanguage)
        #expect(settings.course.target == .finnish)
    }

    @Test func redoingOnboardingKeepsTheLanguageButAsksAgain() {
        let (settings, _) = freshSettings()
        settings.startLearning(.greek)
        settings.restartOnboarding()
        #expect(!settings.hasChosenLanguage, "Onboarding shows again")
        #expect(!settings.hasOnboarded)
        #expect(settings.chosenTarget == .greek, "…but the pickers open on what was already chosen")
    }

    @Test func theChoiceSurvivesRelaunch() {
        let (settings, defaults) = freshSettings()
        settings.startLearning(.polish)
        let reopened = TutorSettings(store: defaults)
        #expect(reopened.chosenTarget == .polish)
        #expect(reopened.hasChosenLanguage)
    }

    @Test func everyNordicLanguageIsOffered() {
        let codes = Set(LearningLanguage.catalog.map(\.code))
        for nordic in ["sv", "da", "nb", "fi", "is"] {
            #expect(codes.contains(nordic), "Missing Nordic language \(nordic)")
        }
    }

    @Test func theCatalogIsUsableAsAList() {
        let codes = LearningLanguage.catalog.map(\.code)
        #expect(Set(codes).count == codes.count, "Language codes are ids, so they must be unique")
        #expect(LearningLanguage.pickerOrder.count == LearningLanguage.catalog.count)
        let names = LearningLanguage.pickerOrder.map(\.displayName)
        #expect(names == names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        for language in LearningLanguage.catalog {
            #expect(LearningLanguage.named(language.code) == language)
        }
    }

    @Test func everyLanguageCarriesItsOwnFixedPhrases() {
        for language in LearningLanguage.catalog {
            #expect(!language.greeting.isEmpty, "\(language.englishName) has no greeting")
            #expect(!language.sampleLine.isEmpty, "\(language.englishName) has no sample line")
            #expect(!language.flag.isEmpty)
        }
        // The phrases must actually differ per language, or the app is still
        // greeting everyone in one language.
        #expect(LearningLanguage.italian.greeting == "Ciao")
        #expect(LearningLanguage.mandarin.greeting == "你好")
        #expect(LearningLanguage.icelandic.greeting != LearningLanguage.italian.greeting)
        let greetings = LearningLanguage.catalog.map(\.greeting)
        #expect(Set(greetings).count >= 20, "Greetings look copy-pasted across languages")
    }

    @Test func icelandicIsOfferedEvenWithoutSpeechSupport() {
        // It has neither a voice nor a recognizer on Apple platforms; the UI says
        // so rather than showing buttons that do nothing.
        #expect(LearningLanguage.named("is") != nil)
    }

    @MainActor
    @Test func eachLanguageKeepsItsOwnPlanAndIsListedSeparately() throws {
        let container = try memoryContainer()
        let store = LearningStore()

        store.load(container: container, language: .italian)
        try store.update { state in
            var italianPlan = plan(target: "it")
            italianPlan.lessons = result(target: "it").lessons
            italianPlan.completedLessonIDs = ["lesson-0"]
            state.activePlan = italianPlan
        }

        store.switchLanguage(to: .japanese)
        #expect(store.state.activePlan == nil, "A new language starts without a plan, so the app runs a kunskapskoll")
        try store.update { $0.activePlan = plan(target: "ja") }

        let listed = store.studies()
        #expect(Set(listed.map(\.language.code)) == ["it", "ja"])
        let italianStudy = try #require(listed.first { $0.language == .italian })
        #expect(italianStudy.lessonsCompleted == 1)
        #expect(italianStudy.lessonTotal == 3)
        #expect(italianStudy.hasPlan)

        // Switching back resumes the other language exactly where it was left.
        store.switchLanguage(to: .italian)
        #expect(store.state.activePlan?.completedLessonIDs == ["lesson-0"])
        #expect(store.state.activePlan?.lessons.count == 3)
    }

    @MainActor
    @Test func progressCountsOnlyLessonsThePlanStillHas() throws {
        let container = try memoryContainer()
        let store = LearningStore()
        store.load(container: container, language: .spanish)
        try store.update { state in
            var spanish = plan(target: "es")
            spanish.lessons = Array(result(target: "es").lessons.prefix(2))
            // A rewritten plan can leave credit behind for lessons it no longer has.
            spanish.completedLessonIDs = ["lesson-0", "lesson-7"]
            state.activePlan = spanish
        }
        let study = try #require(store.studies().first { $0.language == .spanish })
        #expect(study.lessonTotal == 2)
        #expect(study.lessonsCompleted == 1)
    }
}

@Suite("Subject pronoun game")
struct PronounGameTests {
    private func pronoun(_ form: String, _ meaning: String, person: Int, plural: Bool = false) -> SubjectPronoun {
        SubjectPronoun(pronoun: form, meaning: meaning, person: person, plural: plural,
                       note: "", pronunciation: "")
    }

    private func round(_ id: String, answer: String) -> PronounRound {
        PronounRound(id: id, sentence: "\(PronounGame.blank) sono a casa.",
                     translation: "Jag är hemma.", answer: answer,
                     explanation: "Verbet 'sono' hör ihop med io.")
    }

    private func game(rounds: Int = 6, answer: String = "io") -> PronounGame {
        PronounGame(
            overview: "Italienskan utelämnar ofta pronomenet eftersom verbet redan visar personen.",
            pronouns: [pronoun("io", "jag", person: 1), pronoun("tu", "du", person: 2),
                       pronoun("lui", "han", person: 3), pronoun("noi", "vi", person: 1, plural: true)],
            rounds: (0..<rounds).map { self.round("r\($0)", answer: answer) }
        )
    }

    @Test func aWellFormedGameValidates() throws {
        try game().validate()
    }

    @Test func everyRoundNeedsABlankToFill() {
        var broken = game()
        broken.rounds[2].sentence = "Io sono a casa."
        #expect(throws: LearningValidationError.self) { try broken.validate() }
    }

    @Test func theAnswerMustBeOneOfThePronounsOnScreen() {
        // Otherwise the round is unanswerable: the chips come from `pronouns`.
        var broken = game()
        broken.rounds[0].answer = "voi"
        #expect(throws: LearningValidationError.self) { try broken.validate() }
    }

    @Test func aGameNeedsEnoughRoundsToBeWorthPlaying() {
        #expect(throws: LearningValidationError.self) { try game(rounds: 3).validate() }
        #expect(throws: LearningValidationError.self) { try game(rounds: 20).validate() }
    }

    @Test func personMustBeFirstSecondOrThird() {
        var broken = game()
        broken.pronouns[0] = SubjectPronoun(pronoun: "io", meaning: "jag", person: 4,
                                            plural: false, note: "", pronunciation: "")
        #expect(throws: LearningValidationError.self) { try broken.validate() }
    }

    @Test func progressCountsOnlyWhatWasSolvedFirstTry() {
        var progress = PronounGameProgress(game: game())
        progress.solvedRoundIDs = ["r0", "r1", "r2"]
        progress.attemptsByRound = ["r0": 1, "r1": 3, "r2": 1]
        #expect(progress.firstTryCount == 2)
        #expect(!progress.isComplete)
        progress.solvedRoundIDs = Set((0..<6).map { "r\($0)" })
        #expect(progress.isComplete)
    }

    @MainActor
    @Test func theGameIsSavedPerLanguageLikeEverythingElse() throws {
        let container = try memoryContainer()
        let store = LearningStore()
        store.load(container: container, language: .italian)
        try store.update { $0.pronouns = PronounGameProgress(game: game()) }
        try store.updatePronouns { $0.solvedRoundIDs.insert("r0") }
        #expect(store.state.pronouns?.solvedRoundIDs == ["r0"])

        store.switchLanguage(to: .japanese)
        #expect(store.state.pronouns == nil, "A new language starts its own pronoun game")

        store.switchLanguage(to: .italian)
        #expect(store.state.pronouns?.solvedRoundIDs == ["r0"])
    }

    @MainActor
    @Test func snapshotsWrittenBeforeTheGameExistedStillDecode() throws {
        let container = try memoryContainer()
        var state = LearningState()
        state.activePlan = plan(target: "it")
        state.pronouns = nil
        let payload = try JSONEncoder().encode(state)
        container.mainContext.insert(LearningSnapshot(payload: payload, languageCode: "it"))
        try container.mainContext.save()

        let store = LearningStore()
        store.load(container: container, language: .italian)
        #expect(store.isLoaded)
        #expect(store.state.pronouns == nil)
    }
}

@Suite("Free conversation and written feedback")
struct WritingAndChatTests {
    private func feedback(score: Int = 4, nextSteps: [String] = ["Öva verbet essere"]) -> WritingFeedback {
        WritingFeedback(corrected: "Sto bene, grazie.", summary: "Texten gör vad den ska.",
                        strengths: ["Tydlig hälsning"], nextSteps: nextSteps, score: score,
                        ruleTitle: "Stare för mående", ruleExplanation: "Använd stare, inte essere.")
    }

    @Test func wellFormedFeedbackValidates() throws {
        try feedback().validate()
    }

    @Test func theScoreStaysOnItsScale() {
        #expect(throws: LearningValidationError.self) { try feedback(score: 0).validate() }
        #expect(throws: LearningValidationError.self) { try feedback(score: 6).validate() }
    }

    @Test func feedbackAlwaysSaysWhatToDoNext() {
        #expect(throws: LearningValidationError.self) { try feedback(nextSteps: []).validate() }
    }

    @Test func aChatTurnNeedsSomethingToSay() {
        var turn = ChatTurn(reply: "", translation: "Hej", correction: nil, memory: "")
        #expect(throws: LearningValidationError.self) { try turn.validate() }
        turn.reply = "Ciao!"
        #expect(throws: Never.self) { try turn.validate() }
    }

    @Test func aHalfEmptyCorrectionIsRejected() {
        let turn = ChatTurn(reply: "Ciao!", translation: "Hej!",
                            correction: Correction(original: "Sono bene", corrected: "", explanation: "x"),
                            memory: "")
        #expect(throws: LearningValidationError.self) { try turn.validate() }
    }

    @Test func acceptingATurnMovesThePendingAnswerIntoTheTranscript() throws {
        var session = FreeChatSession()
        session.pendingAnswer = "Sono bene"
        try session.accept(ChatTurn(
            reply: "Bene! E tu?", translation: "Bra! Och du?",
            correction: Correction(original: "Sono bene", corrected: "Sto bene", explanation: "Använd stare."),
            memory: "Blandar essere och stare."))
        #expect(session.pendingAnswer == nil)
        #expect(session.messages.count == 2)
        #expect(session.messages.first?.role == .user)
        #expect(session.messages.last?.correction?.corrected == "Sto bene")
        #expect(session.memory == "Blandar essere och stare.")
    }

    @Test func anOpeningTurnCarriesNoCorrection() throws {
        // Nothing has been said yet, so there is nothing to correct.
        var session = FreeChatSession()
        try session.accept(ChatTurn(
            reply: "Ciao! Di cosa parliamo?", translation: "Hej! Vad pratar vi om?",
            correction: Correction(original: "x", corrected: "y", explanation: "z"), memory: ""))
        #expect(session.messages.count == 1)
        #expect(session.messages.first?.correction == nil)
    }

    @MainActor
    @Test func writingsAndChatAreKeptPerLanguage() throws {
        let container = try memoryContainer()
        let store = LearningStore()
        store.load(container: container, language: .italian)
        try store.update { state in
            state.writings = [WritingReview(text: "Sono bene", feedback: self.feedback())]
            state.freeChat = FreeChatSession(messages: [ChatMessage(role: .assistant, text: "Ciao!")])
        }

        store.switchLanguage(to: .german)
        #expect(store.state.writings == nil)
        #expect(store.state.freeChat == nil)

        store.switchLanguage(to: .italian)
        #expect(store.state.writings?.count == 1)
        #expect(store.state.freeChat?.messages.count == 1)
    }
}
