import SwiftData
import SwiftUI

struct LearningPathView: View {
    @Environment(LearningStore.self) private var store
    @State private var showingSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let plan = store.state.activePlan {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DIN ITALIENSKA · \(plan.profile.cefr)")
                            .font(.caption.weight(.semibold)).foregroundStyle(ItaLearn.magenta)
                        Text("Din väg framåt").font(.title.bold())
                        LearningMarkdownText(plan.profile.goal).font(.body)
                        Text("\(plan.completedLessonIDs.count) av \(plan.lessons.count) lektioner klara")
                            .font(.subheadline).foregroundStyle(.secondary)
                        ProgressView(value: Double(plan.completedLessonIDs.count), total: Double(plan.lessons.count))
                        if let assessment = store.state.assessments.last {
                            DisclosureGroup("Om din bedömning") { LearningMarkdownText(assessment.result.rationale).font(.callout) }
                        }
                    }
                    .italearnCard()
                    ForEach(plan.lessons) { lesson in
                        let unlocked = lesson.prerequisites.allSatisfy { plan.completedLessonIDs.contains($0) }
                        NavigationLink {
                            LessonOverviewView(lesson: lesson)
                        } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: plan.completedLessonIDs.contains(lesson.id) ? "checkmark.circle.fill" : unlocked ? "bubble.left.and.bubble.right.fill" : "lock.fill")
                                    .foregroundStyle(ItaLearn.purple)
                                    .font(.title2)
                                    .accessibilityLabel(plan.completedLessonIDs.contains(lesson.id) ? "Klar" : unlocked ? "Tillgänglig" : "Låst")
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(lesson.title).font(.headline)
                                    Text(lesson.summary).font(.subheadline).foregroundStyle(.secondary)
                                    if !unlocked { Text("Gör föregående lektioner först").font(.caption) }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .italearnCard()
                        }
                        .buttonStyle(.plain)
                        .disabled(!unlocked)
                    }
                    NavigationLink {
                        AdaptiveChatView(mode: .assessment)
                    } label: {
                        Label(store.state.assessment == nil ? "Testa mina kunskaper igen" : "Fortsätt min kunskapskoll", systemImage: "arrow.trianglehead.clockwise")
                    }
                    .buttonStyle(ItaLearnSecondaryButtonStyle())
                    Text("En ny kunskapskoll kan ge dig en uppdaterad plan eller rekommendera att du fortsätter på din nuvarande väg. Dina tidigare studier sparas.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .italearnCanvas()
        .navigationTitle("Min studieplan")
        .toolbar {
            Button("Inställningar", systemImage: "gearshape") { showingSettings = true }
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
    }
}

struct LessonOverviewView: View {
    let lesson: PlannedLesson
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LearningMarkdownText(lesson.summary).font(.title3)
                NavigationLink { LessonPracticeView(lesson: lesson) } label: {
                    Label("Ordkort och bygg meningar", systemImage: "rectangle.on.rectangle.angled")
                }.buttonStyle(ItaLearnSecondaryButtonStyle())
                LearningBulletCard(title: "Det här övar du", items: lesson.objectives)
                LearningBulletCard(title: "Du är klar när du kan", items: lesson.successCriteria)
                LearningBulletCard(title: "Ord att använda", items: lesson.vocabulary)
                NavigationLink {
                    AdaptiveChatView(mode: .lesson(lesson))
                } label: {
                    Label("Öppna lektionen", systemImage: "bubble.left.and.bubble.right")
                }
                .buttonStyle(ItaLearnPrimaryButtonStyle())
            }
            .padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .italearnCanvas()
        .navigationTitle(lesson.title)
    }
}

struct CurrentLessonView: View {
    @Environment(LearningStore.self) private var store
    private var nextLesson: PlannedLesson? {
        guard let plan = store.state.activePlan else { return nil }
        return plan.lessons.first {
            !plan.completedLessonIDs.contains($0.id) && $0.prerequisites.allSatisfy { plan.completedLessonIDs.contains($0) }
        }
    }
    var body: some View {
        if let lesson = nextLesson {
            // Keep the completed conversation visible until the learner chooses the next lesson.
            LessonOverviewView(lesson: lesson)
        } else {
            ContentUnavailableView {
                Label("Du har arbetat igenom din plan!", systemImage: "checkmark.seal")
            } description: {
                Text("Gör en ny kunskapskoll för att hitta nästa steg.")
            } actions: {
                NavigationLink("Testa mina kunskaper igen") { AdaptiveChatView(mode: .assessment) }
            }
        }
    }
}

struct LearningProgressView: View {
    @Environment(LearningStore.self) private var store
    var body: some View {
        List {
            if let profile = store.state.activePlan?.profile {
                Section("Din senaste uppskattade nivå: \(profile.cefr)") {
                    Text("Baserad på skriftliga svar, inte ett formellt CEFR-prov.").font(.footnote)
                    ForEach(profile.strengths, id: \.self) { Label($0, systemImage: "checkmark") }
                }
                Section("Fortsätt öva") {
                    ForEach(profile.focusAreas, id: \.self) { Text($0) }
                }
            }
            Section("Kunskapskollar") {
                ForEach(store.state.assessments.reversed()) { assessment in
                    NavigationLink {
                        AssessmentDetailView(assessment: assessment)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(assessment.result.recommendation == .newPlan ? "Ny studieplan" : "Fortsätt på din väg").font(.headline)
                            Text(assessment.createdAt, style: .date).font(.caption)
                            Text(assessment.result.rationale).font(.subheadline).lineLimit(3)
                        }
                    }
                }
            }
            Section("Sparade samtal") {
                ForEach(store.state.sessions.reversed()) { session in
                    NavigationLink {
                        ScrollView {
                            LazyVStack(spacing: 14) {
                                if let summary = session.wrapUp { LessonSummaryCard(summary: summary, mastered: session.isComplete) }
                                ForEach(session.messages) { LearningMessageBubble(message: $0) }
                            }
                            .padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
                        }
                        .italearnCanvas().navigationTitle(lessonTitle(session))
                    } label: {
                        Label(lessonTitle(session), systemImage: session.isComplete ? "checkmark.circle" : "bubble.left")
                    }
                }
            }
            Section {
                NavigationLink("Tidigare skrivövningar") { LessonHistoryView() }
            }
        }
        .navigationTitle("Mitt lärande")
    }

    private func lessonTitle(_ session: LessonSession) -> String {
        let plans = store.state.archivedPlans + [store.state.activePlan].compactMap { $0 }
        return plans.first { $0.id == session.planID }?.lessons.first { $0.id == session.lessonID }?.title ?? "Sparad lektion"
    }
}

struct AssessmentDetailView: View {
    let assessment: SavedAssessment
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(assessment.result.profile.cefr).font(.largeTitle.bold())
                LearningMarkdownText(assessment.result.rationale)
                LearningBulletCard(title: "Styrkor", items: assessment.result.profile.strengths)
                LearningBulletCard(title: "Nästa steg", items: assessment.result.profile.focusAreas)
                ShareLink(item: String(decoding: assessment.resultJSON, as: UTF8.self)) {
                    Label("Dela bedömning som JSON", systemImage: "square.and.arrow.up")
                }
                DisclosureGroup("Visa kunskapskollen") {
                    ForEach(assessment.messages) { LearningMessageBubble(message: $0) }
                }
            }
            .padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .italearnCanvas().navigationTitle("Din kunskapskoll")
    }
}

private struct LearningBulletCard: View {
    let title: String
    let items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top) {
                    Image(systemName: "circle.fill").font(.system(size: 5)).padding(.top, 8)
                    Text(item)
                }
            }
        }
        .italearnCard()
    }
}

struct AdaptiveChatView: View {
    enum Mode { case assessment, lesson(PlannedLesson) }
    let mode: Mode
    @Environment(LearningStore.self) private var store
    @Environment(OpenAIAccess.self) private var access
    @Environment(TutorSettings.self) private var settings
    @State private var chat = LearningChat()
    @State private var sessionID: UUID?
    @State private var draft = ""
    @State private var showingSettings = false
    @State private var setupError: String?
    @State private var hasStartedAssessment = false
    @State private var narrator = SpeechNarrator()
    @State private var speech = LessonSpeechInput()
    @State private var speechTask: Task<Void, Never>?
    @FocusState private var composerFocused: Bool

    private var isAssessment: Bool { if case .assessment = mode { true } else { false } }
    private var session: LessonSession? { store.state.sessions.first { $0.id == sessionID } }
    private var messages: [ChatMessage] { isAssessment ? store.state.assessment?.messages ?? [] : session?.messages ?? [] }
    private var pendingAnswer: String? { isAssessment ? store.state.assessment?.pendingAnswer : session?.pendingAnswer }
    private var assessmentFinished: Bool { isAssessment && hasStartedAssessment && store.state.assessment == nil && !store.state.assessments.isEmpty }
    private var title: String { if case .lesson(let lesson) = mode { lesson.title } else { "Din kunskapskoll" } }

    var body: some View {
        VStack(spacing: 0) {
            statusHeader
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if assessmentFinished, let result = store.state.assessments.last {
                            Text(result.result.recommendation == .newPlan ? "Din nya studieplan är klar" : "Fortsätt på din väg")
                                .font(.title2.bold())
                            LearningMarkdownText(result.result.rationale).italearnCard()
                            NavigationLink("Visa min studieplan") { LearningPathView() }
                                .buttonStyle(ItaLearnPrimaryButtonStyle())
                        }
                        ForEach(messages) { message in
                            LearningMessageBubble(message: message)
                            if !isAssessment && message.role == .assistant && !message.translation.isEmpty {
                                Button("Lyssna", systemImage: "speaker.wave.2") {
                                    narrator.stop(); narrator.speak(LearningMarkdown.spoken(message.text))
                                }
                                .font(.caption)
                                .accessibilityLabel("Lyssna på lärarens italienska")
                            }
                        }
                        if let pendingAnswer {
                            LearningMessageBubble(message: ChatMessage(role: .user, text: pendingAnswer))
                            Text("Väntar på lärarens svar").font(.caption).foregroundStyle(.secondary)
                        }
                        if chat.isWorking { ProgressView(isAssessment ? "Läraren funderar…" : "Luna hjälper dig…") }
                        if let error = setupError ?? chat.errorMessage ?? store.errorMessage {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(error).foregroundStyle(ItaLearn.red)
                                Button("Försök igen") { resume() }
                                if pendingAnswer != nil {
                                    Button("Ändra mitt svar") {
                                        if let recovered = chat.recoverPendingAnswer(store: store, sessionID: sessionID) {
                                            draft = recovered; composerFocused = true
                                        }
                                    }
                                }
                                Button("Öppna inställningar") { showingSettings = true }
                            }
                            .italearnCard().disabled(chat.isWorking)
                        }
                        if let session, let summary = session.wrapUp, case .lesson(let lesson) = mode {
                            LessonSummaryCard(summary: summary, mastered: session.isComplete)
                            if session.isComplete, let next = nextLesson {
                                NavigationLink { AdaptiveChatView(mode: .lesson(next)) } label: {
                                    Label("Nästa lektion: \(next.title)", systemImage: "arrow.right")
                                }.buttonStyle(ItaLearnPrimaryButtonStyle())
                            } else if !session.isComplete {
                                Button("Fortsätt öva med läraren") { continueLesson(session.id) }
                                    .buttonStyle(ItaLearnPrimaryButtonStyle())
                            }
                            NavigationLink { LessonPracticeView(lesson: lesson) } label: {
                                Label("Öva med ordkort och meningar", systemImage: "rectangle.on.rectangle.angled")
                            }.buttonStyle(ItaLearnSecondaryButtonStyle())
                            NavigationLink("Till min studieplan") { LearningPathView() }
                        }
                        Color.clear.frame(height: 1).id("latest")
                    }
                    .padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
                }
                .onChange(of: messages.count) {
                    if messages.last(where: { $0.role == .user })?.text == draft { draft = "" }
                    withAnimation { proxy.scrollTo("latest", anchor: .bottom) }
                }
                .onChange(of: pendingAnswer) { if pendingAnswer != nil { draft = "" } }
                .onChange(of: chat.isWorking) { proxy.scrollTo("latest", anchor: .bottom) }
            }
            if !assessmentFinished && session?.wrapUp == nil && session?.wrapUpRequested != true { composer }
        }
        .italearnCanvas()
        .navigationTitle(title)
        .toolbar {
            Button("Inställningar", systemImage: "gearshape") { showingSettings = true }
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .task { resume() }
        .onDisappear {
            chat.cancel(); narrator.stop(); speechTask?.cancel()
            Task { await speech.cancel() }
        }
        .onChange(of: access.revision) {
            chat.errorMessage = "API-nyckeln har ändrats. Tryck på Försök igen för att fortsätta."
            chat.cancel(); narrator.stop(); speechTask?.cancel()
            Task { await speech.cancel() }
        }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isAssessment && !assessmentFinished {
                let count = store.state.assessment?.answeredCount ?? 0
                Text("FRÅGA \(min(count + 1, 6)) AV 6 · TA DET I DIN TAKT")
                    .font(.caption.weight(.semibold)).foregroundStyle(ItaLearn.magenta)
                ProgressView(value: Double(count), total: 6)
            } else if case .lesson(let lesson) = mode {
                Text(session?.requiresRetry == true ? "FÖRSÖK IGEN · DU FÅR HJÄLP PÅ VÄGEN" : "ÖVA ITALIENSKA · ETT STEG I TAGET")
                    .font(.caption.weight(.semibold)).foregroundStyle(ItaLearn.purple)
                ProgressView(value: Double(session?.achievedObjectives.count ?? 0), total: Double(lesson.objectives.count))
                Text(session?.wrapUp != nil ? "Sammanfattningen är sparad" : "\(min(session?.answerCount ?? 0, LessonSession.answerBudget)) av \(LessonSession.answerBudget) svar · sedan sammanfattar vi")
                    .font(.caption).foregroundStyle(.secondary)
                if let sessionID, session?.wrapUp == nil, (session?.answerCount ?? 0) >= 2 {
                    Button("Avsluta och sammanfatta", systemImage: "checkmark.circle") {
                        narrator.stop(); speechTask?.cancel()
                        Task { await speech.cancel() }
                        chat.finishLesson(store: store, sessionID: sessionID, settings: settings)
                    }.font(.callout).disabled(chat.isWorking || pendingAnswer != nil || speech.isListening || speech.isPreparing)
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .frame(maxWidth: 760).frame(maxWidth: .infinity)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !isAssessment {
                HStack {
                    Button {
                        narrator.stop()
                        speechTask = Task {
                            if speech.isListening {
                                let heard = await speech.finish()
                                guard !Task.isCancelled else { return }
                                draft = [draft, heard].filter { !$0.isEmpty }.joined(separator: " ")
                            } else { await speech.begin() }
                        }
                    } label: {
                        Label(speech.isListening ? "Avsluta inspelning" : "Tala italienska", systemImage: speech.isListening ? "stop.circle.fill" : "mic")
                    }
                    .disabled(chat.isWorking || pendingAnswer != nil || speech.isPreparing)
                    if speech.isPreparing { ProgressView() }
                }
                .font(.subheadline)
                if speech.isListening {
                    Text(speech.partialTranscript.isEmpty ? "Lyssnar…" : speech.partialTranscript).font(.callout)
                    Text("Granska texten innan du skickar den.").font(.caption).foregroundStyle(.secondary)
                }
                if let error = speech.errorMessage { Text(error).font(.caption).foregroundStyle(ItaLearn.red) }
            }
            if isAssessment {
                Button("Jag vet inte ännu") { submit("Jag vet inte ännu.") }
                    .font(.caption).disabled(chat.isWorking || pendingAnswer != nil)
            }
            HStack(alignment: .bottom, spacing: 12) {
                TextField(isAssessment ? "Skriv ditt svar…" : "Skriv på italienska…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(.white, in: .rect(cornerRadius: 20))
                    .focused($composerFocused)
                    .autocorrectionDisabled()
                    .writingToolsBehavior(.disabled)
                    .disabled(chat.isWorking || pendingAnswer != nil)
                Button { submit(draft) } label: {
                    Image(systemName: "arrow.up").font(.title3.bold())
                        .foregroundStyle(.white).frame(width: 48, height: 48)
                        .background(ItaLearn.purple, in: .circle)
                }
                .accessibilityLabel("Skicka svar")
                .disabled(chat.isWorking || speech.isListening || speech.isPreparing || pendingAnswer != nil || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 2000)
            }
            if draft.count > 1800 {
                Text("\(draft.count) / 2000 tecken").font(.caption)
                    .foregroundStyle(draft.count > 2000 ? ItaLearn.red : ItaLearn.inkSecondary)
            }
        }
        .padding(16).frame(maxWidth: 760).frame(maxWidth: .infinity)
        .background(ItaLearn.field)
    }

    private var nextLesson: PlannedLesson? {
        guard let plan = store.state.activePlan else { return nil }
        return plan.lessons.first {
            !plan.completedLessonIDs.contains($0.id) && $0.prerequisites.allSatisfy { plan.completedLessonIDs.contains($0) }
        }
    }

    private func continueLesson(_ id: UUID) {
        do {
            sessionID = try store.continueLesson(sessionID: id)
            if let sessionID { chat.lesson(store: store, sessionID: sessionID, settings: settings) }
        } catch { setupError = error.localizedDescription }
    }

    private func resume() {
        setupError = nil
        do {
            if isAssessment {
                if !hasStartedAssessment {
                    try store.beginAssessment()
                    hasStartedAssessment = true
                }
                if !assessmentFinished { chat.assessment(store: store) }
            } else if case .lesson(let lesson) = mode {
                sessionID = try store.lessonSession(for: lesson)
                if let sessionID { chat.lesson(store: store, sessionID: sessionID, settings: settings) }
            }
        } catch { setupError = store.errorMessage ?? error.localizedDescription }
    }

    private func submit(_ text: String) {
        guard !chat.isWorking, pendingAnswer == nil else { return }
        narrator.stop()
        if isAssessment { chat.assessment(store: store, answer: text) }
        else if let sessionID { chat.lesson(store: store, sessionID: sessionID, settings: settings, answer: text) }
        else { return }
        composerFocused = false
    }
}

struct LearningMessageBubble: View {
    let message: ChatMessage
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LearningMarkdownText(message.text).font(.body)
            if !message.translation.isEmpty {
                LearningMarkdownText(message.translation).font(.callout).foregroundStyle(.secondary)
            }
            if let correction = message.correction {
                VStack(alignment: .leading, spacing: 8) {
                    Label("En liten rättning", systemImage: "sparkles").font(.subheadline.bold())
                    Text(LearningMarkdown.correction(original: correction.original, corrected: correction.corrected))
                        .textSelection(.enabled)
                        .accessibilityLabel("Rättad mening: \(LearningMarkdown.spoken(correction.corrected))")
                    LearningMarkdownText(correction.explanation).font(.callout)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ItaLearn.purple.opacity(0.08), in: .rect(cornerRadius: 16))
            }
            if message.needsRetry { Label("Prova en gång till", systemImage: "arrow.counterclockwise").font(.subheadline.bold()) }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(message.role == .user ? Color.white : ItaLearn.ink)
        .background(message.role == .user ? ItaLearn.purple : .white, in: .rect(cornerRadius: 24))
        .padding(.leading, message.role == .user ? 36 : 0)
        .padding(.trailing, message.role == .assistant ? 12 : 0)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
/// Local fixtures for visual review. These previews never request a model response.
private struct LearningFlowPreview: View {
    var showsChat = false
    private let container: ModelContainer
    private let store: LearningStore

    init(showsChat: Bool = false) {
        self.showsChat = showsChat
        container = try! ModelContainer(for: LearningSnapshot.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        store = LearningStore()
        store.load(container: container)
        let lessons = [
            PlannedLesson(id: "greetings", title: "Berätta hur du mår", summary: "Hälsa, presentera dig och fråga hur någon mår.", objectives: ["Berätta hur du mår", "Fråga hur någon annan mår"], prerequisites: [], vocabulary: ["ciao", "sto bene"], scenario: "Un nuovo amico", successCriteria: ["Svara och ställ en egen fråga"]),
            PlannedLesson(id: "cafe", title: "En paus på kaféet", summary: "Beställ något gott och fråga vad det kostar.", objectives: ["Beställa artigt"], prerequisites: ["greetings"], vocabulary: ["vorrei"], scenario: "Al bar", successCriteria: ["Gör en beställning"]),
            PlannedLesson(id: "day", title: "Berätta om din dag", summary: "Sätt ord på det du gör i vardagen.", objectives: ["Beskriv din morgon"], prerequisites: ["cafe"], vocabulary: ["la mattina"], scenario: "La mia giornata", successCriteria: ["Använd tre vardagsverb"])
        ]
        let plan = LearningPlan(profile: LearnerProfile(nativeLanguage: "sv", targetLanguage: "it", cefr: "A1", goal: "Känn dig hemma i vardagsitalienskan", strengths: ["Du kan hälsa"], focusAreas: ["Verb i vardagen"]), lessons: lessons)
        try! store.update { state in
            state.activePlan = plan
            state.sessions = [LessonSession(planID: plan.id, lessonID: "greetings", messages: [
                ChatMessage(role: .assistant, text: "Ciao! Come stai oggi?", translation: "Hej! Hur mår du i dag?"),
                ChatMessage(role: .user, text: "Sono bene"),
                ChatMessage(role: .assistant, text: "Prova ancora: come stai?", translation: "Försök igen: hur mår du?", correction: Correction(original: "Sono bene", corrected: "Sto bene", explanation: "När du berättar hur du mår använder du stare: sto bene."), needsRetry: true),
                ChatMessage(role: .assistant, text: "Prova att svara igen med sto.")
            ], requiresRetry: true)]
        }
    }
    var body: some View {
        NavigationStack {
            if showsChat { AdaptiveChatView(mode: .lesson(store.state.activePlan!.lessons[0])) }
            else { LearningPathView() }
        }
        .environment(store).environment(OpenAIAccess())
        .environment(TutorSettings(store: UserDefaults(suiteName: "ItaLearn.preview")!))
        .modelContainer(container)
        .preferredColorScheme(.light)
    }
}

#Preview("Personlig studieplan") { LearningFlowPreview() }
#Preview("Luna med rättning och nytt försök") { LearningFlowPreview(showsChat: true) }
#endif
