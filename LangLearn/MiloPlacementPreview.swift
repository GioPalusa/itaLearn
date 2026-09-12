#if DEBUG
import SwiftData
import SwiftUI

/// Repeatable device fixtures. All learner state lives in memory and settings use
/// a dedicated suite; no credential loading or model response starts on launch.
/// Use --milo-placement-preview --milo-placement-screen <screen>.
struct MiloPlacementPreview: View {
    private let screen: String
    private let container: ModelContainer
    private let store: LearningStore
    private let settings: TutorSettings
    private let access = OpenAIAccess()
    private let lesson: PlannedLesson
    private let sessionID: UUID
    private let pack: PracticePack
    private let largeText: Bool
    @State private var selection = 0
    @State private var planPath: [String] = []
    @State private var practicePath: [String] = []

    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--milo-placement-screen")
        screen = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "chat"
        largeText = args.contains("--milo-placement-large-text")
        let practiceScreens = ["sentence", "sentence-hint", "flashcards", "practice-empty", "practice-ready", "pronoun-intro", "pronoun-active", "pronoun-completed", "writing"]
        _selection = State(initialValue: screen == "progress" ? 2 : practiceScreens.contains(screen) ? 1 : 0)
        _planPath = State(initialValue: ["chat", "chat-help", "overview"].contains(screen) ? [screen] : [])
        _practicePath = State(initialValue: practiceScreens.contains(screen) ? [screen] : [])
        container = try! ModelContainer(for: LessonRecord.self, LearningSnapshot.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        settings = TutorSettings(store: UserDefaults(suiteName: "LanguLearn.milo-placement-preview")!)
        settings.nativeLanguage = .swedish
        settings.chosenTarget = .italian
        settings.learnerName = "Alex"
        store = LearningStore()
        store.load(container: container, language: .italian)
        lesson = PlannedLesson(id: "cafe", title: "En paus på kaféet",
            summary: "Beställ något gott och fråga vad det kostar.",
            objectives: ["Beställa artigt", "Fråga vad kaffet kostar"], prerequisites: [],
            vocabulary: ["vorrei", "un caffè"], scenario: "Al bar",
            successCriteria: ["Gör en beställning"], estimatedMinutes: 10)
        let plan = LearningPlan(profile: LearnerProfile(nativeLanguage: "sv", targetLanguage: "it", cefr: "A1",
            goal: "Känn dig hemma i vardagsitalienskan", strengths: ["Du kan hälsa och presentera dig", "Du kan beställa något enkelt"],
            focusAreas: ["Verb i vardagen", "Artiga frågor"], skills: SkillEstimate(reading: 28, writing: 24, listening: 10, speaking: 8)),
            lessons: [lesson,
                PlannedLesson(id: "day", title: "Berätta om din dag", summary: "Sätt ord på det du gör i vardagen.",
                    objectives: ["Beskriv din morgon"], prerequisites: ["cafe"], vocabulary: ["la mattina"],
                    scenario: "La mia giornata", successCriteria: ["Använd tre vardagsverb"], estimatedMinutes: 12)])
        pack = PracticePack(flashcards: [Flashcard(id: "coffee", cue: "En kaffe, tack", answer: "Un caffè, per favore.",
            example: "Vorrei un caffè, per favore.")], puzzles: [SentencePuzzle(id: "coffee",
                cue: "Jag skulle vilja ha en kaffe, tack.", answers: [["Vorrei", "un", "caffè,", "per", "favore."]],
                words: ["Vorrei", "un", "caffè,", "per", "favore.", "una"],
                explanation: "Vorrei är ett artigt sätt att beställa. Caffè är maskulint: un caffè.")])
        var session = LessonSession(planID: plan.id, lessonID: lesson.id, messages: [
            ChatMessage(role: .assistant, text: "Ciao! Che cosa vuoi ordinare?", translation: "Hej! Vad vill du beställa?"),
            ChatMessage(role: .user, text: "Vorrei una caffè"),
            ChatMessage(role: .assistant, text: "Quasi! Prova ancora: vorrei un caffè.", translation: "Nästan! Försök igen: jag skulle vilja ha en kaffe.",
                correction: Correction(original: "Vorrei una caffè", corrected: "Vorrei un caffè", explanation: "Caffè är maskulint. Därför säger du un caffè."), needsRetry: true)
        ], requiresRetry: true)
        if screen != "practice-empty" {
            var progress = PracticeProgress(pack: pack)
            progress.cardQueue = ["coffee"]
            progress.puzzleBankOrder = Array(0..<6)
            if screen == "sentence-hint" {
                progress.puzzleHints = ["coffee": PuzzleHint(encouragement: "Du är på rätt väg.", hint: "Börja med det artiga ordet för jag skulle vilja: Vorrei.", nextWord: "Vorrei")]
            }
            session.practice = progress
        }
        sessionID = session.id
        let pronouns = [SubjectPronoun(pronoun: "io", meaning: "jag", person: 1, plural: false, note: "", pronunciation: ""),
                        SubjectPronoun(pronoun: "tu", meaning: "du", person: 2, plural: false, note: "", pronunciation: "")]
        let rounds = [PronounRound(id: "coffee", sentence: "___ bevo un caffè.", translation: "Jag dricker en kaffe.", answer: "io", explanation: "Io betyder jag. Bevo är verbformen för jag dricker.")]
        var pronounProgress = PronounGameProgress(game: PronounGame(overview: "På italienska kan pronomen ofta utelämnas: verbet berättar vem som gör något.", pronouns: pronouns, rounds: rounds))
        if screen == "pronoun-completed" {
            pronounProgress.cursor = 1
            pronounProgress.solvedRoundIDs = ["coffee"]
            pronounProgress.bestStreak = 1
        }
        try! store.update { state in
            state.activePlan = plan
            state.sessions = [session]
            if screen == "pronoun-active" || screen == "pronoun-completed" { state.pronouns = pronounProgress }
            state.writings = [WritingReview(prompt: "Berätta om din dag", text: "Oggi bevo una caffè.", feedback: WritingFeedback(
                corrected: "Oggi bevo un caffè.", summary: "Du berättar tydligt vad du gör i dag.", strengths: ["Du använder oggi för i dag."],
                nextSteps: ["Öva på un och una."], score: 4, ruleTitle: "Un caffè", ruleExplanation: "Caffè är maskulint, så artikeln är un."))]
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Min studieplan", systemImage: "point.topleft.down.to.point.bottomright.curvepath", value: 0) {
                NavigationStack(path: $planPath) {
                    LearningPathView().navigationDestination(for: String.self) { _ in destination }
                }
            }
            Tab("Öva", systemImage: "gamecontroller", value: 1) {
                NavigationStack(path: $practicePath) {
                    PracticeHubView().navigationDestination(for: String.self) { _ in destination }
                }
            }
            Tab("Mitt lärande", systemImage: "books.vertical", value: 2) {
                NavigationStack { LearningProgressView() }
            }
        }
            .environment(store).environment(settings).environment(access)
            .environment(\.dynamicTypeSize, largeText ? .accessibility3 : .large)
            .modelContainer(container)
            .preferredColorScheme(.light).tint(LanguLearn.purple)
    }

    @ViewBuilder private var destination: some View {
        switch screen {
        case "sentence", "sentence-hint": SentencePracticeView(sessionID: sessionID, puzzles: pack.puzzles, lessonTitle: lesson.title)
        case "flashcards": FlashcardPracticeView(sessionID: sessionID, cards: pack.flashcards, lessonTitle: lesson.title)
        case "plan": LearningPathView()
        case "progress": LearningProgressView()
        case "overview": LessonOverviewView(lesson: lesson)
        case "practice-empty", "practice-ready": LessonPracticeView(lesson: lesson)
        case "pronoun-intro", "pronoun-active", "pronoun-completed": PronounGameView()
        case "writing": WritingDeskView()
        case "chat-help": AdaptiveChatView(
            mode: .lesson(lesson),
            previewHelp: ExerciseHelpTranscript(
                exercise: store.helpContext(settings: settings, activity: .lesson,
                                            task: lesson.title, sessionID: sessionID),
                exchanges: [ExerciseHelpExchange(
                    kind: .hint, question: "",
                    answer: "Börja med **sto**, som betyder *jag mår*. Skriv sedan ett kort ord för hur du mår."
                )]
            )
        )
        default: AdaptiveChatView(mode: .lesson(lesson))
        }
    }
}
#endif
