import SwiftUI

struct JourneyTodayView: View {
    @Environment(LearningStore.self) private var store
    @Environment(TutorSettings.self) private var settings
    @State private var showsSettings = false
    @State private var showsLanguages = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                JourneyWelcome(name: settings.greetingName, goal: store.journey.profile?.goal ?? "", language: settings.targetLanguage, experience: store.journey.profile?.startingExperience ?? .new)
                if let session = store.journey.activeSession {
                    NavigationLink { JourneyLessonView(sessionID: session.id) } label: {
                        JourneyCard(title: "Fortsätt: \(session.pack.title)", subtitle: "Steg \(session.cursor + 1) av \(session.pack.steps.count) · allt du gjort finns kvar", symbol: "play.fill", color: LanguLearn.purple)
                    }.buttonStyle(.plain)
                }
                Text("En liten stund. Något du kan använda.").font(.title2.bold())
                Text(store.journey.recommendationReason).font(.body).foregroundStyle(.secondary)
                JourneyTrackLink(track: store.journey.recommendedTrack, recommended: true)
                if !store.journey.dueObservations().isEmpty {
                    NavigationLink { JourneyStartView(track: store.journey.recommendedTrack, topic: "Repetera färdigheterna i review innan nya moment") } label: {
                        JourneyCard(title: "Väck orden igen", subtitle: "\(store.journey.dueObservations().count) färdigheter väntar på återbesök", symbol: "arrow.counterclockwise", color: LanguLearn.deepGreen)
                    }.buttonStyle(.plain)
                }
                JourneyTrackLink(track: store.journey.recommendedTrack == .foundations ? .mission : .foundations)
                Text("Du väljer riktningen. Milo hjälper dig att hitta nästa lilla steg.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .langulearnCanvas().navigationTitle("Idag")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showsLanguages = true } label: { Text(settings.targetLanguage.badge).font(.subheadline.weight(.semibold)) }
                    .accessibilityHint("Byt eller lägg till språk")
            }
            ToolbarItem(placement: .topBarTrailing) { Button("Inställningar", systemImage: "gearshape") { showsSettings = true } }
        }
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .sheet(isPresented: $showsLanguages) { LanguageSwitcherView() }
    }
}

private struct JourneyWelcome: View {
    let name: String?
    let goal: String
    let language: LearningLanguage
    let experience: JourneyProfile.Experience
    @State private var milo = MiloController()
    @State private var greetingTap = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout(alignment: .center))
            layout {
                VStack(alignment: .leading, spacing: 8) {
                    Text(name.map { "Hej, \($0)!" } ?? "Hej, du!").font(.title.bold())
                    Text(experience == .confident ? "Hitta nyanserna. Gör språket till ditt." : experience == .everyday ? "Låt dina samtal ta nya vägar." : "Tänk när orden kommer av sig själva.").font(.title3.weight(.medium))
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    greetingTap += 1
                    if greetingTap.isMultiple(of: 2) { milo.laugh() } else { milo.curious() }
                } label: { MiloAvatarView(controller: milo, size: 132, zoom: 2.6) }
                .buttonStyle(.plain).accessibilityLabel("Hälsa på Milo").accessibilityHint("Tryck för en lekfull reaktion")
            }
            if greetingTap > 0 { Text(greetingTap.isMultiple(of: 2) ? "Okej, en liten paus för ett leende." : "Jag är här. Vi tar det tillsammans.").font(.subheadline.weight(.medium)).foregroundStyle(LanguLearn.purple) }
            Text("Du är på väg mot: \(goal)").font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Button { milo.speak(language.greeting, in: language) } label: { Label("En hälsning från Milo", systemImage: "speaker.wave.2.fill") }
                .font(.subheadline.weight(.semibold)).disabled(!language.hasVoice)
        }
        .padding(24)
        .background(.linearGradient(colors: [Color(red: 0.91, green: 0.87, blue: 0.99), .white], startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 32))
        .miloLifetime(milo)
    }
}

struct JourneyCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: symbol).font(.title2).foregroundStyle(color)
                .padding(14).background(color.opacity(0.12), in: .rect(cornerRadius: 18))
            Text(title).font(.title2.bold()).foregroundStyle(.primary)
            Text(subtitle).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Label("Öppna", systemImage: "arrow.right").font(.subheadline.bold()).foregroundStyle(color)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            .background(.white, in: .rect(cornerRadius: 28))
            .overlay(alignment: .topTrailing) { Circle().fill(color.opacity(0.12)).frame(width: 40, height: 40).padding(24).accessibilityHidden(true) }
    }
}

private struct JourneyTrackLink: View {
    @Environment(LearningStore.self) private var store
    let track: JourneyTrack
    var recommended = false
    var body: some View {
        NavigationLink { JourneyStartView(track: track) } label: {
            JourneyCard(title: track == .foundations ? (store.journey.profile?.startingExperience.isExperienced == true ? "Koppla skriften till det du kan" : "Börja med ljud och tecken") : "Prova i verkliga livet",
                        subtitle: (recommended ? "Mitt förslag till dig · " : "") + (track == .foundations ? "Lyssna, upptäck betydelsen och lär känna skriften. Inga skrivna svar behövs." : "Ett litet vardagsuppdrag utifrån ditt mål, med exempel och hjälp hela vägen."),
                        symbol: track == .foundations ? "ear.badge.waveform" : "sun.horizon.fill",
                        color: track == .foundations ? LanguLearn.purple : LanguLearn.magenta)
        }.buttonStyle(.plain)
    }
}

struct JourneyExploreView: View {
    @Environment(LearningStore.self) private var store
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Vad vill du våga idag?").font(.largeTitle.bold())
                Text("Välj en situation, eller låt ditt eget mål styra.").foregroundStyle(.secondary)
                JourneyTrackLink(track: .foundations)
                ForEach(["Beställa något gott", "Lära känna någon", "Hitta rätt på resan", "Prata om det jag gillar"], id: \.self) { topic in
                    NavigationLink { JourneyStartView(track: .mission, topic: topic) } label: {
                        JourneyCard(title: topic, subtitle: "Ett guidat uppdrag på din startnivå", symbol: "sparkles", color: LanguLearn.magenta)
                    }.buttonStyle(.plain)
                }
                NavigationLink("Skapa ett eget uppdrag") { JourneyStartView(track: .mission) }.buttonStyle(.borderedProminent)
                if store.state.activePlan != nil {
                    NavigationLink("Öppna mina tidigare övningar") { PracticeHubView() }
                    NavigationLink("Öppna min studieplan") { LearningPathView() }
                } else {
                    NavigationLink("Gör en frivillig kunskapskoll") { AdaptiveChatView(mode: .assessment) }
                }
            }.padding(24).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.langulearnCanvas().navigationTitle("Upptäck")
    }
}

struct JourneyStartView: View {
    @Environment(LearningStore.self) private var store
    @Environment(TutorSettings.self) private var settings
    @Environment(OpenAIAccess.self) private var access
    @State private var coach = JourneyCoach()
    @State private var topic: String
    @State private var minutes = 5
    @State private var showConnection = false
    @State private var milo = MiloController()
    let track: JourneyTrack
    init(track: JourneyTrack, topic: String = "") { self.track = track; _topic = State(initialValue: topic) }

    private var canStartGreeting: Bool {
        track == .foundations && store.journey.profile?.startingExperience == .new && store.journey.sessions.isEmpty && FoundationContent.welcome(course: settings.course) != nil
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Button { milo.wave() } label: {
                    MiloStage(controller: milo, size: 230, floorClearance: 0)
                }.buttonStyle(.plain).accessibilityLabel("Hälsa på din guide Milo")
                VStack(alignment: .leading, spacing: 10) {
                    Text(track.title).font(.title.bold())
                    if store.journey.profile?.startingExperience.isExperienced == true {
                        Text(track == .foundations ? "Du kan redan använda språket. Vi kopplar ljud och tecken till situationer du förstår." : "Du får en hel situation att ta dig an, med utrymme för egna svar. Exempel och tips finns när du vill ha dem.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(track == .foundations ? "Vi upptäcker några ljud och tecken i taget, i ord som betyder något för dig." : "Milo visar först. Sedan provar du med stöd, och tar ett litet steg själv när du är redo.")
                            .foregroundStyle(.secondary)
                    }
                }
                if let profile = store.journey.profile {
                    Text("Utifrån ditt mål: \(profile.goal)").font(.headline)
                    Text(profile.startingExperience.title).font(.subheadline).foregroundStyle(.secondary)
                    if track == .foundations || !store.journey.allowsSupportedWriting {
                        Label("Du kan svara genom att välja och lyssna. Inget skrivkrav.", systemImage: "hand.tap").font(.subheadline)
                    }
                }
                TextField("Vad vill du öva på? (valfritt)", text: $topic, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...4)
                Picker("Tid idag", selection: $minutes) {
                    ForEach([3, 5, 10], id: \.self) { Text("\($0) min").tag($0) }
                }.pickerStyle(.segmented)
                if let error = coach.errorMessage { Text(error).foregroundStyle(.red) }
                if coach.isWorking {
                    ProgressView("Milo förbereder ditt nästa steg…")
                    Button("Avbryt") { coach.cancel() }
                } else {
                    if canStartGreeting {
                        Button("Prova min första hälsning") { start(greeting: true) }.buttonStyle(.borderedProminent).controlSize(.large)
                        Text("Ett kort smakprov som fungerar utan anslutning.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Button(access.hasKey ? "Skapa min stund" : "Anslut för personliga lektioner") {
                        if access.hasKey { start(greeting: false) } else { showConnection = true }
                    }.buttonStyle(.borderedProminent).controlSize(.large).disabled(topic.count > 400)
                }
                Text("Ett lektionspaket förbereds åt gången. Du kan sedan lyssna, välja svar och öppna tips utan fler AI-anrop. Fria skrivsvar skickas för återkoppling.").font(.footnote).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }.langulearnCanvas().navigationTitle("Din nästa stund").navigationBarTitleDisplayMode(.inline)
        .task { minutes = store.journey.profile?.minutes ?? 5 }
        .onDisappear { coach.cancel() }
        .miloLifetime(milo)
        .onChange(of: coach.isWorking) { _, working in if working { milo.think() } else { milo.present() } }
        .navigationDestination(isPresented: Binding(get: { coach.openedSession != nil }, set: { if !$0 { coach.openedSession = nil } })) {
            if let id = coach.openedSession { JourneyLessonView(sessionID: id) }
        }
        .sheet(isPresented: $showConnection) { SettingsView() }
    }
    private func start(greeting: Bool) {
        coach.perform { try store.updateJourney { $0.profile?.minutes = minutes } }
        guard coach.errorMessage == nil else { return }
        coach.start(store: store, course: settings.course, track: track, topic: topic, tone: settings.tone.modelInstruction, firstGreeting: greeting)
    }
}

struct JourneyLibraryView: View {
    @Environment(LearningStore.self) private var store
    @State private var editing = false
    var body: some View {
        List {
            Section {
                HStack {
                    Image("MiloThinking").resizable().scaledToFit().frame(width: 100, height: 100).accessibilityHidden(true)
                    Text("Titta vad du har samlat på dig.").font(.title3.bold())
                }
                Text("Små bevis på att du lär dig.").font(.title2.bold())
                Text("Här syns vad du har provat, hur mycket stöd du använde och vad du kan återvända till.").foregroundStyle(.secondary)
                Button("Det Milo vet om mig") { editing = true }
            }
            Section("Färdigheter") {
                ForEach(JourneySkill.allCases, id: \.self) { skill in
                    let observations = store.journey.observations.filter { $0.skill == skill }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(skill.title).font(.headline)
                        Text(skill == .speaking ? "\(observations.filter(\.selfReported).count) egna försök · uttalet är inte bedömt" : "\(observations.filter { $0.correct && $0.independent }.count) rätt utan tips · \(observations.filter { $0.correct && !$0.independent }.count) rätt med stöd")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            }
            Section("Mina stunder") {
                if store.journey.sessions.isEmpty { Text("Din första stund väntar under Idag.").foregroundStyle(.secondary) }
                ForEach(store.journey.sessions.reversed()) { session in
                    NavigationLink { JourneyLessonView(sessionID: session.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.pack.title)
                            Text(session.completedAt == nil ? "Fortsätt där du var" : "Avslutad · se vad du övade").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Ord jag vill behålla") {
                if store.journey.phrases.isEmpty { Text("Spara användbara uttryck inne i lektionen.").foregroundStyle(.secondary) }
                ForEach(store.journey.phrases) { phrase in JourneySavedPhrase(phrase: phrase) }
                .onDelete { offsets in
                    do { try store.updateJourney { $0.phrases.remove(atOffsets: offsets) } }
                    catch { store.errorMessage = error.localizedDescription }
                }
                if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
            }
            if store.state.activePlan != nil {
                Section { NavigationLink("Tidigare lärande och studieplan") { LearningProgressView() } }
            }
        }.navigationTitle("Min resa")
            .sheet(isPresented: $editing) { NavigationStack { JourneySetupView(editing: true) } }
    }
}

private struct JourneySavedPhrase: View {
    @Environment(TutorSettings.self) private var settings
    let phrase: JourneyPhrase
    @State private var narrator = SpeechNarrator()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(phrase.text).font(.headline)
            Text(phrase.translation).foregroundStyle(.secondary)
            Button("Lyssna", systemImage: "speaker.wave.2") { narrator.speak(phrase.text, in: settings.targetLanguage) }.disabled(!settings.targetLanguage.hasVoice)
        }.padding(.vertical, 6).onDisappear { narrator.stop() }
    }
}
