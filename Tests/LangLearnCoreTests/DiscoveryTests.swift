import Foundation
import SwiftData
import Testing
@testable import LangLearnCore

nonisolated func discoveryProbe() -> DiscoveryReply {
    DiscoveryReply(targetLanguage: "it", explanationLanguage: "sv", kind: .probe, mode: .write,
        prompt: "Du vill resa. Hur skulle du lösa det här?", target: "Il treno è stato cancellato. Vuoi partire domani?",
        translation: "Tåget är inställt. Vill du resa i morgon?", hint: "Berätta när du behöver komma fram.", choices: [], correctChoiceID: "",
        goal: "Klara oväntade situationer på resan", interests: "", experience: .everyday,
        reason: "Vi provar en situation från din resa.", evidence: [])
}
nonisolated func discoveryRequest() throws -> DiscoveryRequest {
    let draft = JourneyDiscovery(targetLanguage: "it", explanationLanguage: "sv", reading: .comfortable,
        turns: [DiscoveryTurn(text: "Jag läste italienska i skolan och vill resa själv.", source: .story)])
    return try DiscoveryRequest(course: LanguageCourse(target: .italian, native: .swedish), discovery: draft, previousProfile: nil, priorAssessment: nil)
}
nonisolated func discoverySummary(_ turns: [DiscoveryTurn]) -> DiscoveryReply {
    var result = discoveryProbe()
    result.kind = .recommendation; result.mode = .none
    result.target = ""; result.translation = ""; result.hint = ""
    let last = turns.last!
    result.evidence = [DiscoveryEvidence(turnID: last.id.uuidString, quote: last.text,
        demonstrated: !last.usedHelp && (last.source == .writing || (last.source == .listening && last.heardAudio && last.correctChoice == true)))]
    return result
}

@Suite("Personal discovery contracts")
struct DiscoveryTests {
    @Test func rejectsUnsupportedClaimsAndInventedQuotes() throws {
        var request = try discoveryRequest()
        request.turns.append(DiscoveryTurn(text: "Domani è troppo tardi.", source: .writing))
        var reply = discoverySummary(request.turns)
        try reply.validate(for: request)
        reply.evidence[0].quote = "Invented evidence"
        #expect(throws: LearningValidationError.self) { try reply.validate(for: request) }
        reply = discoverySummary(request.turns)
        request.turns[1].usedHelp = true
        #expect(throws: LearningValidationError.self) { try reply.validate(for: request) }
        reply.evidence[0] = DiscoveryEvidence(turnID: request.turns[0].id.uuidString, quote: request.turns[0].text, demonstrated: true)
        #expect(throws: LearningValidationError.self) { try reply.validate(for: request) }
    }
    @Test func unfamiliarScriptUsesListeningWithValidDistinctChoices() throws {
        var request = try discoveryRequest(); request.reading = .newScript
        var reply = discoveryProbe()
        #expect(throws: LearningValidationError.self) { try reply.validate(for: request) }
        reply.mode = .listen; reply.choices = [.init(id: "a", text: "I morgon"), .init(id: "b", text: "I dag")]; reply.correctChoiceID = "a"
        try reply.validate(for: request)
        reply.choices[1].text = "i morgon"
        #expect(throws: LearningValidationError.self) { try reply.validate(for: request) }
        reply = discoveryProbe(); reply.explanationLanguage = "en"
        #expect(throws: LearningValidationError.self) { try reply.validate(for: request) }
    }
    @Test func listeningEvidenceNeedsCompletedPlaybackAndIndependentCorrectAnswer() throws {
        var request = try discoveryRequest()
        request.turns.append(DiscoveryTurn(text: "I morgon", source: .listening, heardAudio: true, correctChoice: true))
        let summary = discoverySummary(request.turns)
        try summary.validate(for: request)
        request.turns[1].heardAudio = false
        #expect(throws: LearningValidationError.self) { try summary.validate(for: request) }
        request.turns[1].heardAudio = true; request.turns[1].correctChoice = false
        #expect(throws: LearningValidationError.self) { try summary.validate(for: request) }
    }
    @Test func atMostOneClarificationAndThreeRequests() throws {
        var request = try discoveryRequest()
        var question = discoveryProbe(); question.kind = .question; question.mode = .none; question.target = ""; question.translation = ""; question.hint = ""
        try question.validate(for: request)
        request.turns[0].reply = question
        #expect(throws: LearningValidationError.self) { try question.validate(for: request) }
        var draft = JourneyDiscovery(targetLanguage: "it", explanationLanguage: "sv", reading: .comfortable, turns: request.turns)
        draft.turns.append(DiscoveryTurn(text: "På resan", source: .clarification))
        draft.turns.append(DiscoveryTurn(text: "Vorrei partire oggi.", source: .writing))
        let finalRequest = try DiscoveryRequest(course: request.course, discovery: draft, previousProfile: nil, priorAssessment: nil)
        #expect(finalRequest.mustRecommend)
        #expect(throws: LearningValidationError.self) { try discoveryProbe().validate(for: finalRequest) }
        try discoverySummary(finalRequest.turns).validate(for: finalRequest)
        draft.turns.append(DiscoveryTurn(text: "extra", source: .writing))
        #expect(throws: LearningValidationError.self) { try DiscoveryRequest(course: request.course, discovery: draft, previousProfile: nil, priorAssessment: nil) }
    }
    @Test func cannotRecommendBeforeSampleOrExplicitSkip() throws {
        var request = try discoveryRequest()
        #expect(throws: LearningValidationError.self) { try discoverySummary(request.turns).validate(for: request) }
        request.turns.append(DiscoveryTurn(text: "Hoppa över", source: .skip))
        try discoverySummary(request.turns).validate(for: request)
    }
    @Test func skippingCannotDowngradeExistingExperienceAndPriorWritingSetsProbeFloor() throws {
        var request = try discoveryRequest()
        request.previousProfile = JourneyProfile(experience: .confident, goal: "Resa")
        request.turns.append(DiscoveryTurn(text: "Hoppa över", source: .skip))
        var summary = discoverySummary(request.turns)
        #expect(throws: LearningValidationError.self) { try summary.validate(for: request) }
        summary.experience = .confident
        try summary.validate(for: request)
        // A recent richer proposal also protects somebody with an older beginner profile.
        request.previousProfile?.experience = .new
        request.turns[0].reply = discoveryProbe()
        summary.experience = .everyday
        try summary.validate(for: request)
        summary.experience = .new
        #expect(throws: LearningValidationError.self) { try summary.validate(for: request) }
        request = try discoveryRequest()
        request.priorAssessment = LearnerProfile(nativeLanguage: "sv", targetLanguage: "it", cefr: "B2", goal: "Resa", strengths: [], focusAreas: [])
        var probe = discoveryProbe(); probe.target = "Ciao"; probe.experience = .someWords
        #expect(throws: LearningValidationError.self) { try probe.validate(for: request) }
    }
    @Test func difficultyAndOpenAnswersAreNotScoredListeningAndCanAdjustHistory() throws {
        var request = try discoveryRequest()
        request.previousProfile = JourneyProfile(experience: .confident, goal: "Resa")
        request.turns[0].reply = discoveryProbe()
        request.turns.append(DiscoveryTurn(text: "Det här är för svårt", source: .feedback, difficultyFeedback: .tooHard))
        var easier = discoveryProbe(); easier.target = "Un caffè?"; easier.experience = .someWords
        try easier.validate(for: request)
        var summary = discoverySummary(request.turns); summary.experience = .someWords
        try summary.validate(for: request)
        summary.evidence[0].demonstrated = true
        #expect(throws: LearningValidationError.self) { try summary.validate(for: request) }
        request.turns[1] = DiscoveryTurn(text: "Jag förstod bara att de vill åka", source: .openResponse, heardAudio: true)
        summary = discoverySummary(request.turns)
        try summary.validate(for: request)
        summary.evidence[0].demonstrated = true
        #expect(throws: LearningValidationError.self) { try summary.validate(for: request) }
        request.turns[1] = DiscoveryTurn(text: "Jag vill resa, men vet inte hur jag ska svara", source: .clarification, difficultyFeedback: .tooHard)
        try discoverySummary(request.turns).validate(for: request)
        #expect(request.turns[1].informsStartingActivity)
        // A free-text report can also lead to a simpler probe despite old experience.
        request.turns[1] = DiscoveryTurn(text: "Den här nivån är för hög för mig", source: .writing)
        try easier.validate(for: request)
    }
    @Test func priorAssessmentIsOnlySharedWithMatchingLanguage() throws {
        let draft = JourneyDiscovery(targetLanguage: "it", explanationLanguage: "sv", reading: .comfortable,
            turns: [DiscoveryTurn(text: "Resa", source: .story)])
        let foreign = LearnerProfile(nativeLanguage: "sv", targetLanguage: "ja", cefr: "B2", goal: "Resa", strengths: [], focusAreas: [])
        let request = try DiscoveryRequest(course: LanguageCourse(target: .italian, native: .swedish), discovery: draft, previousProfile: nil, priorAssessment: foreign)
        #expect(request.priorAssessment == nil)
    }
    @Test func legacySnapshotsDecodeAndDraftRoundTrips() throws {
        let old = Data(#"{"sessions":[],"observations":[],"phrases":[]}"#.utf8)
        var progress = try JSONDecoder().decode(JourneyProgress.self, from: old)
        #expect(progress.discovery == nil)
        progress.discovery = JourneyDiscovery(targetLanguage: "it", explanationLanguage: "sv", story: "Resa", draft: "Sparat svar")
        #expect(try JSONDecoder().decode(JourneyProgress.self, from: JSONEncoder().encode(progress)) == progress)
    }
}

private actor DiscoveryStub: JourneyDiscoveryService {
    nonisolated var requiresAPIKey: Bool { false }
    var requests: [DiscoveryRequest] = []
    var failFirst: Bool
    var delayed: Bool
    init(failFirst: Bool = false, delayed: Bool = false) { self.failFirst = failFirst; self.delayed = delayed }
    func reply(to request: DiscoveryRequest) async throws -> DiscoveryReply {
        requests.append(request)
        if delayed { try? await Task.sleep(for: .milliseconds(150)) }
        if failFirst && requests.count == 1 { throw URLError(.notConnectedToInternet) }
        return request.turns.count == 1 ? discoveryProbe() : discoverySummary(request.turns)
    }
}

@MainActor @Suite("Personal discovery persistence")
struct DiscoveryStoreTests {
    let course = LanguageCourse(target: .italian, native: .swedish)
    func fixture() throws -> (ModelContainer, LearningStore) {
        let container = try ModelContainer(for: LearningSnapshot.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let store = LearningStore(); store.load(container: container, language: .italian)
        return (container, store)
    }
    func wait(_ coach: JourneyDiscoveryCoach) async throws {
        for _ in 0..<150 { if !coach.isWorking { return }; try await Task.sleep(for: .milliseconds(10)) }
        Issue.record("Discovery did not finish")
    }
    @Test func explicitBeginnerNeedsNoAIAndAcceptanceKeepsHistory() async throws {
        let (container, store) = try fixture()
        let service = DiscoveryStub(); let coach = JourneyDiscoveryCoach(service: service)
        try store.updateJourney { $0.sessions = [JourneySession(pack: journeyExamplePack())] }
        coach.begin(store: store, course: course)
        coach.edit(store: store) { $0.story = "Prata med min familj"; $0.startsFromZero = true; $0.stage = .script }
        coach.chooseReading(.newScript, store: store)
        #expect(store.journey.profile == nil)
        #expect(store.journey.discovery?.stage == .ready)
        #expect(await service.requests.isEmpty)
        #expect(coach.accept(store: store))
        #expect(store.journey.profile?.experience == .new)
        #expect(store.journey.profile?.reading == .newScript)
        #expect(store.journey.sessions.count == 1)
        let restored = LearningStore(); restored.load(container: container, language: .italian)
        #expect(restored.journey == store.journey)
    }
    @Test func retryReusesPendingAnswerAndExperienceOnlyChangesOnAcceptance() async throws {
        let (_, store) = try fixture()
        let previous = JourneyProfile(experience: .confident, hasSpoken: true, goal: "Resa")
        try store.updateJourney { $0.profile = previous }
        let service = DiscoveryStub(failFirst: true); let coach = JourneyDiscoveryCoach(service: service)
        coach.begin(store: store, course: course)
        coach.edit(store: store) { $0.stage = .script }
        coach.chooseReading(.comfortable, store: store)
        coach.submit(store: store, course: course); try await wait(coach)
        let pending = store.journey.discovery?.pending?.id
        #expect(coach.errorMessage != nil)
        coach.submit(store: store, course: course); try await wait(coach)
        let requests = await service.requests
        #expect(requests.count == 2)
        #expect(requests[0].turns[0].id == pending && requests[1].turns[0].id == pending)
        #expect(requests[0].previousProfile?.experience == .confident)
        coach.submit(store: store, course: course, text: "Vorrei arrivare oggi."); try await wait(coach)
        #expect(store.journey.discovery?.stage == .ready)
        #expect(store.journey.profile == previous)
        #expect(coach.accept(store: store))
        #expect(store.journey.profile?.hasSpoken == true)
        let lesson = try JourneyRequest(course: course, progress: store.journey, track: .mission, topic: "", tone: "warm")
        #expect(lesson.startingSamples.first?.text == "Vorrei arrivare oggi.")
        #expect(lesson.startingSamples.first?.target == discoveryProbe().target)
        #expect(lesson.startingSamples.first?.usedHelp == false)
        let payload = String(decoding: try JSONEncoder().encode(lesson.startingSamples), as: UTF8.self)
        #expect(!payload.contains("evidence")) // Omit follow-up model replies from subsequent lesson calls.
    }
    @Test func difficultyPersistsWithPartialAnswerAcrossRetryAndReachesNextLesson() async throws {
        let (container, store) = try fixture()
        let service = DiscoveryStub(); let coach = JourneyDiscoveryCoach(service: service)
        coach.begin(store: store, course: course)
        coach.edit(store: store) { $0.story = "Resa"; $0.stage = .script }
        coach.chooseReading(.comfortable, store: store)
        coach.submit(store: store, course: course); try await wait(coach)
        coach.edit(store: store) { $0.draft = "Ciao… Jag vet inte hur jag ska fortsätta"; $0.difficultyFeedback = .tooHard; $0.usedHelp = true }
        let restored = LearningStore(); restored.load(container: container, language: .italian)
        #expect(restored.journey.discovery?.difficultyFeedback == .tooHard)
        coach.submit(store: restored, course: course); try await wait(coach)
        let answer = try #require(await service.requests.last?.turns.last)
        #expect(answer.text == "Ciao… Jag vet inte hur jag ska fortsätta")
        #expect(answer.difficultyFeedback == .tooHard && answer.usedHelp)
        #expect(coach.accept(store: restored))
        let lesson = try JourneyRequest(course: course, progress: restored.journey, track: .mission, topic: "", tone: "warm")
        #expect(lesson.startingSamples.first?.difficultyFeedback == .tooHard)
    }
    @Test func listeningAllowsOpenCommentsWithoutPretendingTheyAreCorrectChoices() async throws {
        let (_, store) = try fixture()
        let coach = JourneyDiscoveryCoach(service: DiscoveryStub())
        coach.begin(store: store, course: course)
        var probe = discoveryProbe(); probe.mode = .listen
        coach.edit(store: store) { $0.stage = .conversation; $0.reading = .newScript; $0.turns = [DiscoveryTurn(text: "Resa", source: .story, reply: probe)] }
        coach.submit(store: store, course: course, text: "Jag förstår inte ännu, det här är för svårt")
        try await wait(coach)
        let answer = try #require(store.journey.discovery?.turns.last)
        #expect(answer.source == .openResponse && answer.correctChoice == nil && !answer.heardAudio)
        #expect(answer.reply?.evidence.first?.demonstrated == false)
        coach.restart(store: store)
        coach.edit(store: store) { $0.stage = .conversation; $0.reading = .comfortable; $0.turns = [DiscoveryTurn(text: "Resa", source: .story, reply: discoveryProbe())]; $0.difficultyFeedback = .tooHard; $0.usedHelp = true }
        coach.submit(store: store, course: course); try await wait(coach)
        #expect(store.journey.discovery?.turns.last?.source == .feedback)
        #expect(store.journey.discovery?.turns.last?.difficultyFeedback == .tooHard)
        #expect(store.journey.discovery?.turns.last?.usedHelp == true)
    }
    @Test func lateResponseAfterCancellationOrLanguageSwitchCannotPublish() async throws {
        let (_, store) = try fixture()
        let coach = JourneyDiscoveryCoach(service: DiscoveryStub(delayed: true))
        coach.begin(store: store, course: course)
        coach.edit(store: store) { $0.story = "Resa"; $0.stage = .script }
        coach.chooseReading(.comfortable, store: store)
        coach.submit(store: store, course: course)
        try await Task.sleep(for: .milliseconds(20))
        coach.restart(store: store)
        try await Task.sleep(for: .milliseconds(180))
        #expect(store.journey.discovery?.stage == .story)
        #expect(store.journey.discovery?.turns.isEmpty == true)
        coach.edit(store: store) { $0.stage = .script }
        coach.chooseReading(.comfortable, store: store)
        coach.submit(store: store, course: course)
        store.switchLanguage(to: .english)
        try await wait(coach)
        #expect(store.journey.discovery == nil)
        store.switchLanguage(to: .italian)
        #expect(store.journey.discovery?.pending != nil)
    }
}
