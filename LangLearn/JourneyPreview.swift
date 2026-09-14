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
                if arguments.contains("--journey-setup") { JourneySetupView() }
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
#endif
