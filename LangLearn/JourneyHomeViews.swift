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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var coach: JourneyCoach
    @State private var topic: String
    @State private var minutes = 5
    @State private var showConnection = false
    @State private var showsCustomTopic = false
    @State private var milo = MiloController()
    let track: JourneyTrack

    init(track: JourneyTrack, topic: String = "", service: any JourneyService = OpenAIJourneyService()) {
        self.track = track
        _topic = State(initialValue: topic)
        _coach = State(initialValue: JourneyCoach(service: service))
    }

    private var canStartGreeting: Bool {
        track == .foundations && store.journey.profile?.startingExperience == .new && store.journey.sessions.isEmpty && FoundationContent.welcome(course: settings.course) != nil
    }
    private var connected: Bool { access.hasKey || !coach.requiresAPIKey }
    private var trimmedTopic: String { topic.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var focusTitle: String {
        if !trimmedTopic.isEmpty { return trimmedTopic }
        if track == .foundations {
            return store.journey.profile?.startingExperience.isExperienced == true
                ? "Koppla skriften till det du redan kan"
                : "Ljud och tecken du får användning för"
        }
        let goal = store.journey.profile?.goal.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return goal.isEmpty ? "En vardagssituation som passar dig" : goal
    }
    private var startTitle: String {
        if !connected, canStartGreeting { return "Börja med en första hälsning" }
        if !connected { return "Anslut och starta" }
        return "Börja med Milo · \(minutes) min"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if coach.isWorking {
                    JourneyGenerationLoadingView(focus: focusTitle) { coach.cancel() }
                } else {
                    JourneyStartHero(track: track, milo: milo)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("MILOS FÖRSLAG").font(.caption.bold()).tracking(1.4).foregroundStyle(LanguLearn.magenta)
                        Text(focusTitle).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                        Text(track == .foundations
                             ? "Lyssna, välj och upptäck i din takt."
                             : "En kort situation som bygger vidare på din plan.")
                            .font(.body).foregroundStyle(.secondary)
                    }
                    .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: .rect(cornerRadius: 26))

                    JourneyDurationPicker(minutes: $minutes)

                    if let error = coach.errorMessage {
                        Label(error, systemImage: "exclamationmark.bubble.fill")
                            .font(.subheadline).foregroundStyle(LanguLearn.red)
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(LanguLearn.red.opacity(0.08), in: .rect(cornerRadius: 18))
                    }

                    Button(startTitle) {
                        if connected { start(greeting: false) }
                        else if canStartGreeting { start(greeting: true) }
                        else { showConnection = true }
                    }
                    .buttonStyle(LanguLearnPrimaryButtonStyle(background: AnyShapeStyle(LanguLearn.brandGradient)))
                    .disabled(topic.count > 400)

                    if canStartGreeting, connected {
                        Button("Börja direkt med en kort hälsning") { start(greeting: true) }
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    }

                    JourneyCustomTopicEditor(topic: $topic, isExpanded: $showsCustomTopic)
                }
            }
            .padding(dynamicTypeSize.isAccessibilitySize ? 16 : 22)
            .padding(.bottom, 36)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .id(coach.isWorking)
        .langulearnCanvas().navigationTitle("Din nästa stund").navigationBarTitleDisplayMode(.inline)
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

private struct JourneyStartHero: View {
    let track: JourneyTrack
    let milo: MiloController
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        layout {
            VStack(alignment: .leading, spacing: 8) {
                Text(track == .foundations ? "LÄR KÄNNA SPRÅKET" : "DIN NÄSTA SCEN")
                    .font(.caption.bold()).tracking(1.4).foregroundStyle(LanguLearn.purple)
                Text("Redo när du är.").font(.largeTitle.bold())
                Text("Milo har valt en bra start. Du behöver inte fylla i något.")
                    .font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { milo.enthusiastic() } label: {
                MiloAvatarView(controller: milo, size: 156, zoom: 2.6)
            }
            .buttonStyle(.plain).accessibilityLabel("Milo är redo")
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
        }
        .padding(22)
        .background(
            LinearGradient(colors: [LanguLearn.cyan.opacity(0.16), LanguLearn.purple.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 30)
        )
    }
}

private struct JourneyDurationPicker: View {
    @Binding var minutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hur länge har du?").font(.subheadline.bold())
            HStack(spacing: 10) {
                ForEach([3, 5, 10], id: \.self) { choice in
                    Button { minutes = choice } label: {
                        Text("\(choice) min").font(.subheadline.bold())
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(minutes == choice ? .white : LanguLearn.purple)
                            .background(minutes == choice ? LanguLearn.purple : LanguLearn.purple.opacity(0.09), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(minutes == choice ? .isSelected : [])
                }
            }
        }
    }
}

private struct JourneyCustomTopicEditor: View {
    @Binding var topic: String
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(LanguLearnMotion.move) { isExpanded.toggle() }
            } label: {
                HStack {
                    Label("Jag vill välja något annat", systemImage: "slider.horizontal.3")
                    Spacer()
                    Image(systemName: "chevron.down").rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(LanguLearn.purple)
                .frame(minHeight: 44).contentShape(.rect)
            }.buttonStyle(.plain)

            if isExpanded {
                Text("Skriv en situation eller något du vill kunna göra.")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextField("Till exempel: beställa på ett kafé", text: $topic, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(2...4)
                Text("Valfritt · \(topic.count) / 400").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18).background(.white.opacity(0.72), in: .rect(cornerRadius: 22))
    }
}

private struct JourneyGenerationLoadingView: View {
    let focus: String
    let cancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0
    private let messages: [LocalizedStringResource] = [
        "Milo väljer en situation som passar dig",
        "Milo bygger små steg och tydliga exempel",
        "Milo ser till att du kan få hjälp längs vägen"
    ]

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().fill(LanguLearn.purple.opacity(0.08)).frame(width: 226, height: 226)
                Circle().stroke(LanguLearn.cyan.opacity(0.22), lineWidth: 2).frame(width: 252, height: 252)
                    .scaleEffect(reduceMotion ? 1 : (phase.isMultiple(of: 2) ? 0.96 : 1.04))
                Image("MiloThinking").resizable().scaledToFit().frame(width: 218, height: 218)
                    .scaleEffect(reduceMotion ? 1 : (phase.isMultiple(of: 2) ? 0.985 : 1.015))
                    .rotationEffect(.degrees(reduceMotion ? 0 : (phase.isMultiple(of: 2) ? -0.7 : 0.7)))
                    .offset(y: reduceMotion ? 0 : (phase.isMultiple(of: 2) ? 2 : -2))
                    .accessibilityHidden(true)
            }
            VStack(spacing: 11) {
                Text("Milo tänker").font(.largeTitle.bold())
                MiloThinkingDots()
                Text(messages[phase % messages.count]).font(.title3.weight(.medium)).multilineTextAlignment(.center)
                Text(focus).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(3)
            }
            .contentTransition(.numericText())
            Button("Pausa här", action: cancel).frame(minHeight: 44)
            Text("Din plan och dina val finns kvar.").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.top, 20).frame(maxWidth: .infinity)
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1200))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.45)) { phase = (phase + 1) % messages.count }
            }
        }
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
