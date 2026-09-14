#if DEBUG
import SwiftData
import SwiftUI

/// Isolated simulator fixtures: no learner data, Keychain reads or automatic network calls.
struct JourneyPreview: View {
    @State private var store = LearningStore()
    @State private var settings = TutorSettings(store: UserDefaults(suiteName: "JourneyPreview.\(UUID().uuidString)")!)
    @State private var access = OpenAIAccess()
    @State private var ready = false
    @State private var error: String?
    private let arguments = ProcessInfo.processInfo.arguments
    private let container = try? ModelContainer(for: LearningSnapshot.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))

    var body: some View {
        NavigationStack {
            if let error { Text(error) }
            else if ready {
                if arguments.contains("--journey-setup"), store.journey.discovery?.stage != .finished { JourneySetupView(service: DiscoveryPreviewService()) }
                else if arguments.contains("--journey-lesson"), let session = store.journey.sessions.first { JourneyLessonView(sessionID: session.id) }
                else { JourneyTodayView() }
            } else { ProgressView() }
        }
        .environment(store).environment(settings).environment(access)
        .environment(\.dynamicTypeSize, arguments.contains("--journey-large-text") ? .accessibility3 : .large)
        .task {
            guard !ready else { return }
            guard let container else { error = "Preview storage unavailable"; return }
            settings.startLearning(arguments.contains("--journey-script") ? LearningLanguage.named("ja")! : .italian)
            settings.nativeLanguage = .swedish; settings.learnerName = "Alex"
            store.load(container: container, language: settings.targetLanguage)
            do {
                try store.updateJourney { progress in
                    progress.profile = JourneyProfile(reading: arguments.contains("--journey-script") ? .newScript : .comfortable, goal: "Beställa lunch på resan", interests: "Mat och små kaféer")
                    if arguments.contains("--discovery-fresh") { progress.profile = nil }
                    if arguments.contains("--journey-lesson") {
                        var pack = FoundationContent.welcome(course: settings.course)!
                        if arguments.contains("--journey-script") {
                            pack.title = "Lär känna あ"
                            for index in pack.steps.indices {
                                pack.steps[index].skillID = "kana.a"
                                pack.steps[index].skillTitle = "Känna igen あ"
                            }
                            pack.steps[0].instruction = "Det här är hiragana-tecknet あ. Det finns i början av あさ, som betyder morgon. Lyssna på hela ordet."
                            pack.steps[0].target = "あ · あさ"; pack.steps[0].audioText = "あさ"; pack.steps[0].translation = "morgon"
                            pack.steps[1].kind = .scriptChoice; pack.steps[1].skill = .script
                            pack.steps[1].instruction = "Vilket alternativ är samma tecken som det på kortet?"
                            pack.steps[1].target = "あ"; pack.steps[1].translation = "あ i ordet あさ"; pack.steps[1].audioText = "あさ"
                            pack.steps[1].choices = [.init(id: "a", text: "あ"), .init(id: "o", text: "お")]; pack.steps[1].correctChoiceID = "a"
                            pack.steps[1].hints = ["Jämför formerna i lugn och ro.", "あ har ett streck tvärs över upptill."]
                            pack.steps[1].explanation = "あ är samma tecken. Du mötte det i ordet あさ, morgon."
                            pack.steps[2].instruction = "Lyssna på ordet för morgon och prova att säga det."
                            pack.steps[2].skillID = "words.morning"; pack.steps[2].skillTitle = "Prova ordet för morgon"
                            pack.steps[2].target = "あさ"; pack.steps[2].translation = "morgon"; pack.steps[2].audioText = "あさ"
                        }
                        try pack.validate(course: settings.course, track: .foundations)
                        var session = JourneySession(pack: pack)
                        if arguments.contains("--journey-complete") { session.cursor = pack.steps.count; session.completedAt = .now }
                        progress.sessions = [session]
                    }
                }
                ready = true
            } catch { self.error = error.localizedDescription }
        }
    }
}
/// Deterministic UI fixture only. Production always uses OpenAIDiscoveryService.
private struct DiscoveryPreviewService: JourneyDiscoveryService {
    var requiresAPIKey: Bool { false }
    func reply(to request: DiscoveryRequest) async throws -> DiscoveryReply {
        try await Task.sleep(for: .milliseconds(400))
        let listening = request.reading != .comfortable
        let japanese = request.course.target.code == "ja"
        var reply = DiscoveryReply(targetLanguage: request.course.target.code, explanationLanguage: request.course.native.code,
            kind: .probe, mode: listening ? .listen : .write,
            prompt: listening ? "Lyssna på personen som berättar om resplanerna. Vad uppfattade du? Du kan välja ett svar eller berätta med egna ord, även om du bara förstod en del." : "Svara på italienska till vännen med egna ord. Skriv var eller när ni kan träffas och nämn något du vill göra. Du kan också svara med några ord eller berätta vad du förstår av meddelandet.",
            target: japanese ? "電車が止まっています。明日の朝、バスで行きませんか。" : listening ? "Il treno è stato cancellato. Possiamo prenotare un posto per domani mattina?" : "Ciao! Sabato arrivo a Roma. Dove ci incontriamo? Vorrei anche prendere un caffè prima di visitare il centro. Tu che cosa vuoi fare?",
            translation: japanese ? "Tåget går inte. Ska vi ta bussen i morgon bitti?" : listening ? "Tåget är inställt. Kan vi boka en plats i morgon bitti?" : "Hej! På lördag kommer jag till Rom. Var ska vi träffas? Jag skulle vilja ta en kaffe innan vi besöker centrum. Vad vill du göra?",
            hint: listening ? "Lyssna efter när personen föreslår att ni ska resa." : "Du kan börja med Ciao och föreslå en plats eller något ni kan göra.",
            choices: listening ? [.init(id: "a", text: "Att resa i morgon bitti"), .init(id: "b", text: "Att stanna hela veckan")] : [],
            correctChoiceID: listening ? "a" : "", goal: request.turns[0].text,
            interests: "", experience: .everyday, reason: "Vi börjar med en situation där du får använda språket för att lösa ett problem.", evidence: [])
        if request.turns.count > 1 {
            let last = request.turns.last!
            reply.kind = .recommendation; reply.mode = .none
            reply.prompt = "Vi börjar med att hitta en annan väg."
            reply.target = ""; reply.translation = ""; reply.hint = ""; reply.choices = []; reply.correctChoiceID = ""
            reply.reason = last.difficultyFeedback == .tooHard ? "Du berättade att uppgiften kändes för svår. Vi börjar med kortare fraser, mer stöd och det du redan kunde få fram." : last.source == .skip ? "Du valde att hoppa över exemplet. Vi utgår från det du berättade och justerar när du provar nästa situation." : "Ditt första uppdrag handlar om att föreslå en lösning när resplaner ändras. Du får prova hela svar och kan be om stöd längs vägen."
            if last.difficultyFeedback == .tooHard { reply.experience = .someWords }
            if last.source == .skip, last.difficultyFeedback == nil, request.previousProfile?.startingExperience == .confident { reply.experience = .confident }
            reply.evidence = [.init(turnID: last.id.uuidString, quote: String(last.text.prefix(300)), demonstrated: !last.usedHelp && (last.source == .writing || (last.source == .listening && last.heardAudio && last.correctChoice == true)))]
        }
        return reply
    }
}
#endif
