import Foundation
import Testing
@testable import LangLearnCore

nonisolated func journeyExamplePack(track: JourneyTrack = .mission) -> JourneyPack {
    let example = JourneyStep(id: "example", kind: .example, skill: .reading,
        skillID: "greet", skillTitle: "Hälsa", instruction: "Så säger du hej",
        target: "Ciao", translation: "Hej", audioText: "Ciao", choices: [], correctChoiceID: "",
        tokens: [], acceptedAnswers: [], hints: ["En hälsning"], explanation: "Ciao är en hälsning.")
    var choice = example
    choice.id = "choose"; choice.kind = .meaningChoice
    choice.choices = [.init(id: "hello", text: "Hej"), .init(id: "thanks", text: "Tack")]
    choice.correctChoiceID = "hello"
    var final = example
    final.id = "final"
    if track == .mission { final.kind = .write; final.skill = .writing }
    else { final = choice; final.id = "final" }
    return JourneyPack(schemaVersion: 1, targetLanguage: "it", explanationLanguage: "sv",
                       track: track, title: "Hälsa", reason: "En första hälsning", steps: [example, choice, final])
}

@Suite("Guided journeys")
struct JourneyTests {
    let course = LanguageCourse(target: .italian, native: .swedish)

    @Test func previousSnapshotsDecodeWithoutJourney() throws {
        let previous = Data(#"{"schemaVersion":1,"archivedPlans":[],"assessments":[],"sessions":[]}"#.utf8)
        let state = try JSONDecoder().decode(LearningState.self, from: previous)
        #expect(state.journey == nil)
        var updated = state
        updated.journey = JourneyProgress(profile: JourneyProfile(goal: "Resa"))
        let restored = try JSONDecoder().decode(LearningState.self, from: JSONEncoder().encode(updated))
        #expect(restored.journey?.profile?.goal == "Resa")
    }

    @Test func routeRespectsReadingAndSpeakingSeparately() {
        var progress = JourneyProgress(profile: JourneyProfile(hasSpoken: true, reading: .newScript, goal: "Resa"))
        #expect(progress.recommendedTrack == .foundations)
        progress.profile?.reading = .comfortable
        #expect(progress.recommendedTrack == .mission)
        progress.profile?.hasSpoken = false
        #expect(progress.recommendedTrack == .foundations)
    }

    @Test func rejectsWrongCourseMissingAnswersAndDuplicateChoices() throws {
        try journeyExamplePack().validate(course: course, track: .mission)
        var pack = journeyExamplePack()
        pack.targetLanguage = "ja"
        #expect(throws: LearningValidationError.self) { try pack.validate(course: course, track: .mission) }
        pack = journeyExamplePack()
        pack.steps[1].correctChoiceID = "missing"
        #expect(throws: LearningValidationError.self) { try pack.validate(course: course, track: .mission) }
        pack = journeyExamplePack()
        pack.steps[1].choices[1].text = " HEJ "
        #expect(throws: LearningValidationError.self) { try pack.validate(course: course, track: .mission) }
    }

    @Test func foundationsNeverRequireTypingAndListeningRequiresAudio() throws {
        var pack = journeyExamplePack()
        pack.track = .foundations
        #expect(throws: LearningValidationError.self) { try pack.validate(course: course, track: .foundations) }
        pack = journeyExamplePack(track: .foundations)
        pack.steps[1].kind = .listeningChoice; pack.steps[1].skill = .listening
        pack.steps[1].audioText = ""
        #expect(throws: LearningValidationError.self) { try pack.validate(course: course, track: .foundations) }
    }

    @Test func puzzleMustBeBuildableIncludingDuplicateWords() throws {
        var step = journeyExamplePack().steps[2]
        step.kind = .build; step.tokens = ["ciao", "Milo"]; step.acceptedAnswers = ["ciao ciao Milo"]
        #expect(throws: LearningValidationError.self) { try step.validate() }
        step.tokens.append("ciao")
        try step.validate()
    }

    @Test func evaluationMustReferToCurrentStepAndActualAnswer() throws {
        let step = journeyExamplePack().steps[2]
        var evaluation = JourneyEvaluation(stepID: "final", accepted: true, feedback: "En hälsning", correction: "", evidence: "Ciao")
        try evaluation.validate(step: step, answer: "Ciao Milo")
        evaluation.evidence = "Buongiorno"
        #expect(throws: LearningValidationError.self) { try evaluation.validate(step: step, answer: "Ciao") }
        evaluation.accepted = false; evaluation.stepID = "other"
        #expect(throws: LearningValidationError.self) { try evaluation.validate(step: step, answer: "Ciao") }
    }

    @Test func progressCannotSkipUnansweredStepsAndRestoresDraft() throws {
        var session = JourneySession(pack: journeyExamplePack())
        try session.advance()
        #expect(throws: LearningValidationError.self) { try session.advance() }
        session.draft = "mitt utkast"; session.hintCount = 1
        let restored = try JSONDecoder().decode(JourneySession.self, from: JSONEncoder().encode(session))
        #expect(restored.draft == "mitt utkast")
        #expect(restored.hintCount == 1)
        session.evaluation = .init(stepID: "choose", accepted: true, feedback: "Bra", correction: "", evidence: "Hej")
        try session.advance()
        #expect(session.draft.isEmpty && session.hintCount == 0)
    }

    @Test func reviewScheduleDoesNotConfuseHintsWithIndependentRecall() {
        let now = Date(timeIntervalSince1970: 1000000)
        var progress = JourneyProgress()
        let observation = JourneyObservation(id: UUID(), skillID: "greet", title: "Hälsa", skill: .writing,
            correct: true, independent: false, selfReported: false, date: now, phrase: "Ciao", translation: "Hej")
        progress.record(observation); progress.record(observation)
        #expect(progress.observations.count == 1)
        #expect(progress.dueObservations(at: now).isEmpty)
        #expect(progress.dueObservations(at: now.addingTimeInterval(86401)).count == 1)
        var speech = observation
        speech.id = UUID(); speech.skill = .speaking; speech.selfReported = true
        progress.record(speech)
        #expect(progress.dueObservations(at: now.addingTimeInterval(86401)).count == 1)
    }
}

@Suite("Foundation content and generation contract")
struct FoundationTests {
    @Test func starterWorksForEveryTarget() throws {
        for target in LearningLanguage.catalog {
            for native in [LearningLanguage.swedish, .english] {
                let course = LanguageCourse(target: target, native: native)
                let pack = try #require(FoundationContent.welcome(course: course))
                try pack.validate(course: course, track: .foundations)
                #expect(!pack.steps.contains { [.write, .build].contains($0.kind) })
                let inventory = FoundationInventory.forLanguage(target)
                #expect(!inventory.units.isEmpty)
                #expect(Set(inventory.units).count == inventory.units.count)
            }
        }
    }
    @Test func learnerReadinessIsEnforcedBeyondSchema() throws {
        let course = LanguageCourse(target: .italian, native: .swedish)
        var progress = JourneyProgress(profile: JourneyProfile(goal: "Resa"))
        let request = try JourneyRequest(course: course, progress: progress, track: .mission, topic: "Kafé", tone: "Warm")
        #expect(throws: LearningValidationError.self) { try request.validate(journeyExamplePack()) }
        progress.profile?.hasSpoken = true
        try JourneyRequest(course: course, progress: progress, track: .mission, topic: "Kafé", tone: "Warm").validate(journeyExamplePack())
        progress.profile?.reading = .newScript
        let foundation = try JourneyRequest(course: course, progress: progress, track: .foundations, topic: "", tone: "Warm")
        #expect(throws: LearningValidationError.self) { try foundation.validate(journeyExamplePack(track: .foundations)) }
    }
}

@Suite("Journey quality safeguards")
struct JourneyQualityTests {
    @Test func repeatedSameDaySuccessDoesNotDelayReview() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var progress = JourneyProgress()
        for _ in 0..<5 {
            progress.record(JourneyObservation(id: UUID(), skillID: "hello", title: "Hälsa", skill: .reading,
                correct: true, independent: true, selfReported: false, date: now, phrase: "Ciao", translation: "Hej"))
        }
        #expect(progress.dueObservations(at: now.addingTimeInterval(86401)).count == 1)
    }
    @Test func completingGreetingDoesNotClaimScriptReadiness() {
        var progress = JourneyProgress(profile: JourneyProfile(reading: .newScript, goal: "Resa"))
        var session = JourneySession(pack: journeyExamplePack(track: .foundations))
        session.completedAt = .now
        progress.sessions = [session]
        #expect(progress.recommendedTrack == .foundations)
    }
    @Test func emptyLookingContentCannotBecomeALesson() {
        var pack = journeyExamplePack()
        pack.steps[0].instruction = "  \n  "
        #expect(throws: LearningValidationError.self) { try pack.validate(course: LanguageCourse(target: .italian, native: .swedish), track: .mission) }
    }
}

@Suite("Evidence-based activity choices")
struct JourneyAdaptationTests {
    @Test func writingActivitiesGrowFromSeveralSkillsButNeverBypassUnknownScript() {
        var progress = JourneyProgress(profile: JourneyProfile(goal: "Resa"))
        #expect(!progress.allowsSupportedWriting)
        for id in ["hello", "thanks", "coffee"] {
            progress.record(JourneyObservation(id: UUID(), skillID: id, title: id, skill: .reading, correct: true,
                independent: true, selfReported: false, date: .now, phrase: id, translation: id))
        }
        #expect(progress.allowsSupportedWriting)
        progress.profile?.reading = .newScript
        #expect(!progress.allowsSupportedWriting)
        progress.profile?.hasSpoken = true
        #expect(!progress.allowsSupportedWriting)
    }
    @Test func supportedAnswersAndRepeatingOneSkillDoNotUnlockWriting() {
        var progress = JourneyProgress(profile: JourneyProfile(goal: "Resa"))
        for index in 0..<8 {
            progress.record(JourneyObservation(id: UUID(), skillID: "hello", title: "Hälsa", skill: .reading, correct: true,
                independent: index.isMultiple(of: 2), selfReported: false, date: .now, phrase: "Ciao", translation: "Hej"))
        }
        #expect(!progress.allowsSupportedWriting)
    }
}

@Suite("Experienced learners")
struct ExperiencedJourneyTests {
    let course = LanguageCourse(target: .italian, native: .swedish)

    @Test func experienceRequiresMeaningfulApplicationEvenWithNoAppHistory() throws {
        let progress = JourneyProgress(profile: JourneyProfile(experience: .confident, hasSpoken: true, goal: "Förhandla på jobbet"))
        #expect(progress.recommendedTrack == .mission)
        let request = try JourneyRequest(course: course, progress: progress, track: .mission, topic: "Förhandling", tone: "Warm")
        #expect(request.experience == .confident)
        #expect(throws: LearningValidationError.self) { try request.validate(journeyExamplePack()) }
        var substantial = journeyExamplePack()
        substantial.steps[2].target = "Preferirei discutere prima le condizioni del contratto."
        try request.validate(substantial)
    }

    @Test func unfamiliarScriptDoesNotEraseOralExperience() throws {
        let progress = JourneyProgress(profile: JourneyProfile(experience: .everyday, hasSpoken: true, reading: .newScript, goal: "Lära mig läsa det jag redan förstår"))
        let request = try JourneyRequest(course: course, progress: progress, track: .foundations, topic: "Resa", tone: "Warm")
        #expect(request.experience == .everyday)
        #expect(!request.allowsWriting)
        var pack = journeyExamplePack(track: .foundations)
        pack.steps[1].kind = .scriptChoice; pack.steps[1].skill = .script; pack.steps[1].target = "a"
        pack.steps[1].choices = [.init(id: "a", text: "a"), .init(id: "o", text: "o")]; pack.steps[1].correctChoiceID = "a"
        #expect(throws: LearningValidationError.self) { try request.validate(pack) }
        pack.steps[0].audioText = "Vorrei prenotare un tavolo per due persone, per favore."
        try request.validate(pack)
    }

    @Test func earlierAssessmentAndRecentDifficultyTravelInBoundedContext() throws {
        var progress = JourneyProgress(profile: JourneyProfile(experience: .everyday, hasSpoken: true, goal: "Resa"))
        for difficulty in [JourneyDifficulty.tooHard, .justRight, .justRight, .tooEasy] {
            var session = JourneySession(pack: journeyExamplePack()); session.completedAt = .now
            session.difficultyFeedback = difficulty; progress.sessions.append(session)
        }
        let assessment = LearnerProfile(nativeLanguage: "sv", targetLanguage: "it", cefr: "B2", goal: "Arbete", strengths: ["Beskriva problem"], focusAreas: ["Artighet"])
        let request = try JourneyRequest(course: course, progress: progress, track: .mission, topic: "Möte", tone: "Warm", priorAssessment: assessment)
        #expect(request.priorAssessment?.cefr == "B2")
        #expect(request.recentDifficulty == [.justRight, .justRight, .tooEasy])
        let restored = try JSONDecoder().decode(JourneyProgress.self, from: JSONEncoder().encode(progress))
        #expect(restored.sessions.last?.difficultyFeedback == .tooEasy)
        #expect(restored.profile?.startingExperience == .everyday)
        let other = try JourneyRequest(course: LanguageCourse(target: .english, native: .swedish), progress: progress, track: .mission, topic: "Möte", tone: "Warm", priorAssessment: assessment)
        #expect(other.priorAssessment == nil)
    }

    @Test func olderProfilesRemainReadable() throws {
        let old = Data(#"{"hasSpoken":true,"reading":"comfortable","goal":"Resa","interests":"Mat","minutes":5}"#.utf8)
        let restored = try JSONDecoder().decode(JourneyProfile.self, from: old)
        #expect(restored.experience == nil)
        #expect(restored.startingExperience == .someWords)
    }
}
