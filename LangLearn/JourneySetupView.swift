import SwiftUI

/// One moment at a time: a story, a real situation, then a starting point to accept.
struct JourneySetupView: View {
    @Environment(LearningStore.self) private var store
    @Environment(TutorSettings.self) private var settings
    @Environment(OpenAIAccess.self) private var access
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var coach: JourneyDiscoveryCoach
    @State private var milo = MiloController()
    @State private var showsConnection = false
    @FocusState private var isTyping: Bool
    var editing: Bool

    init(editing: Bool = false, service: any JourneyDiscoveryService = OpenAIDiscoveryService()) {
        self.editing = editing
        _coach = State(initialValue: JourneyDiscoveryCoach(service: service))
    }
    private var discovery: JourneyDiscovery? { store.journey.discovery }
    private var connected: Bool { access.hasKey || !coach.requiresAPIKey }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Color.clear.frame(height: 1).id("moment")
                    if let discovery {
                        if !coach.isWorking {
                            DiscoveryMiloMoment(milo: milo, title: title(discovery), caption: caption(discovery), compact: isTyping) {
                                milo.speak(discovery.reply?.prompt ?? title(discovery), in: settings.nativeLanguage)
                            }
                        }
                        if discovery.pending == nil, let prompt = discovery.reply?.prompt {
                            Text(prompt).font(.title3.weight(.medium))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                        switch discovery.stage {
                        case .story: story(discovery)
                        case .script: script(discovery)
                        case .conversation: conversation(discovery)
                        case .ready, .finished: recommendation(discovery)
                        }
                    } else { ProgressView() }
                    if let error = coach.errorMessage {
                        Label(error, systemImage: "exclamationmark.bubble").font(.callout).foregroundStyle(LanguLearn.red)
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 32)
                .frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(red: 0.96, green: 0.94, blue: 0.99).ignoresSafeArea())
            .onChange(of: discovery?.stage) {
                isTyping = false; milo.stop()
                if discovery?.stage == .ready { milo.joyful() } else { milo.curious() }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { scroll.scrollTo("moment", anchor: .top) }
            }
            .onChange(of: discovery?.reply) { isTyping = false; scroll.scrollTo("moment", anchor: .top) }
            .task(id: isTyping) {
                guard isTyping else { return }
                // Let the keyboard and compact portrait finish changing the available space.
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                guard isTyping else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    scroll.scrollTo("discovery-input", anchor: .center)
                }
            }
        }
        .navigationTitle(editing ? "Lär känna mig igen" : "Du och Milo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if discovery?.stage != .story {
                    Button("Tillbaka", systemImage: "arrow.left") { coach.restart(store: store) }
                }
            }
            ToolbarItem(placement: .topBarTrailing) { if editing { Button("Stäng") { dismiss() } } }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Klart") { isTyping = false } }
        }
        .sheet(isPresented: $showsConnection) {
            NavigationStack {
                ScrollView { APIKeyForm(showsLearnerName: false).padding() }
                    .navigationTitle("Anslut till Milo")
                    .toolbar { Button("Klart") { showsConnection = false } }
            }
        }
        .task { coach.begin(store: store, course: settings.course); milo.wave() }
        .miloLifetime(milo)
        .onDisappear { coach.cancel() }
        .onChange(of: scenePhase) { if scenePhase != .active { coach.cancel() } }
        .onChange(of: access.revision) { coach.cancel() }
        .onChange(of: settings.course) { coach.cancel() }
        .onChange(of: coach.isWorking) { if coach.isWorking { milo.think() } else { milo.leanIn() } }
    }

    private func title(_ draft: JourneyDiscovery) -> String {
        switch draft.stage {
        case .story: String(localized: "Vad vill du öppna dörren till?")
        case .script: String(localized: "En sak innan vi provar.")
        case .conversation: draft.pending != nil ? String(localized: "Jag tar med mig det du berättar…") : String(localized: "En situation i taget.")
        case .ready, .finished: draft.isLocalStart ? String(localized: "Då tar vi första steget tillsammans.") : String(localized: "Här vill jag börja med dig.")
        }
    }
    private func caption(_ draft: JourneyDiscovery) -> String {
        switch draft.stage {
        case .story: String(localized: "DIN VÄRLD")
        case .script: settings.targetLanguage.displayName
        case .conversation: String(localized: "VI PROVAR OSS FRAM")
        case .ready, .finished: String(localized: "EN START SOM PASSAR DIG")
        }
    }

    private func story(_ draft: JourneyDiscovery) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Berätta om dig och \(settings.targetLanguage.displayName). Vad har du provat — och vad längtar du efter att kunna göra?").font(.title3)
            composer("Jag har… och skulle vilja…", text: binding(\.story, limit: 400))
            if draft.story.isEmpty {
                HStack(alignment: .top, spacing: 10) { inspirationButtons }
            }
            Button {
                coach.edit(store: store) { $0.startsFromZero.toggle() }
                milo.encourage()
            } label: {
                Label(draft.startsFromZero ? "Jag börjar från noll — vi tar det tillsammans" : "Jag börjar från noll", systemImage: draft.startsFromZero ? "checkmark.circle.fill" : "sparkle")
                    .font(.subheadline.weight(.medium)).frame(minHeight: 44, alignment: .leading)
            }.tint(LanguLearn.purple)
            Text(draft.startsFromZero ? "Du behöver inte bevisa något. Skriv bara vad du vill kunna använda språket till." : "Skriv precis som du vill, på ditt språk eller språket du lär dig. Vi hittar en start genom att prova tillsammans.")
                .font(.footnote).foregroundStyle(.secondary)
            Button("Det här är jag", systemImage: "arrow.right") {
                isTyping = false
                coach.edit(store: store) { $0.stage = .script }
            }.buttonStyle(LanguLearnPrimaryButtonStyle()).disabled(draft.story.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    @ViewBuilder private var inspirationButtons: some View {
        inspiration("En resa", symbol: "suitcase", text: "Jag vill känna mig hemma på resan och kunna prata med dem jag möter.")
        inspiration("Människor", symbol: "bubble.left.and.bubble.right", text: "Jag vill kunna prata mer med människor som är viktiga för mig.")
        inspiration("Min vardag", symbol: "sun.max", text: "Jag vill använda språket i min vardag.")
    }
    private func inspiration(_ title: LocalizedStringKey, symbol: String, text: String.LocalizationValue) -> some View {
        Button { coach.edit(store: store) { $0.story = String(localized: text) }; isTyping = true } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.footnote.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity).padding(.vertical, 14).padding(.horizontal, 6)
        }.buttonStyle(.plain).background(.white, in: RoundedRectangle(cornerRadius: 18)).foregroundStyle(LanguLearn.purple)
    }

    private func script(_ draft: JourneyDiscovery) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Känns tecknen bekanta?").font(.title2.bold())
            VStack(alignment: .leading, spacing: 16) {
                Text(settings.targetLanguage.sampleLine).font(.title2.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                Button("Lyssna", systemImage: "speaker.wave.2.fill") { milo.speak(settings.targetLanguage.sampleLine, in: settings.targetLanguage) }
                    .disabled(!settings.targetLanguage.hasVoice).frame(minHeight: 44)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 24))
            Text("Du behöver inte förstå orden. Det här hjälper mig att välja hur vi provar — med text eller med ljud.").foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) { readingButtons }
                VStack(spacing: 12) { readingButtons }
            }
            Button("Jag vill ha extra stöd att läsa") { selectReading(.learningToRead) }.frame(minHeight: 44)
            if !draft.startsFromZero {
                Text("När du väljer fortsätter samtalet med AI. Det du berättat och relevant studiehistorik skickas till OpenAI.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private var readingButtons: some View {
        readingButton("Tecknen känns bekanta", symbol: "textformat.abc", reading: .comfortable)
        readingButton("Tecknen är nya för mig", symbol: "ear.badge.waveform", reading: .newScript)
    }
    private func readingButton(_ title: LocalizedStringKey, symbol: String, reading: JourneyProfile.Reading) -> some View {
        Button { selectReading(reading) } label: {
            VStack(alignment: .leading, spacing: 12) { Image(systemName: symbol).font(.title2); Text(title).font(.headline).fixedSize(horizontal: false, vertical: true) }
                .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        }.buttonStyle(.plain).background(LanguLearn.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 22)).foregroundStyle(LanguLearn.purple)
    }
    private func selectReading(_ reading: JourneyProfile.Reading) {
        coach.chooseReading(reading, store: store)
        if discovery?.stage == .conversation, connected { coach.submit(store: store, course: settings.course) }
    }

    @ViewBuilder private func conversation(_ draft: JourneyDiscovery) -> some View {
        if coach.isWorking {
            VStack(spacing: 24) {
                ZStack {
                    Circle().fill(.white.opacity(0.7)).frame(width: 232, height: 232)
                    Circle().stroke(LanguLearn.purple.opacity(0.12), lineWidth: 1).frame(width: 260, height: 260)
                    MiloView(mood: .thinking, size: 232, zoom: 2.6)
                }.padding(.top, 12)
                VStack(spacing: 12) {
                    Text("Jag funderar på ditt nästa steg").font(.title2.bold())
                    Text("Jag tar med mig det du berättar och hittar en situation som passar dig.")
                        .font(.body).foregroundStyle(.secondary)
                    MiloThinkingDots().padding(.top, 8)
                }.multilineTextAlignment(.center)
                if let answer = draft.pending?.text, !answer.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Det här tar jag med mig", systemImage: "quote.bubble")
                            .font(.caption.weight(.semibold)).foregroundStyle(LanguLearn.purple)
                        Text(answer).font(.callout).lineLimit(4)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20).background(.white.opacity(0.8), in: .rect(cornerRadius: 24))
                }
                Button("Pausa här") { coach.cancel() }.frame(minHeight: 44)
                Text("Ditt svar finns kvar om du pausar.").font(.footnote).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)
        } else if !connected {
            VStack(alignment: .leading, spacing: 16) {
                Text("För att följa upp det du berättar behöver Milo en anslutning till OpenAI. Din text och relevant studiehistorik skickas när du börjar samtalet.")
                Button("Anslut till Milo") { showsConnection = true }.buttonStyle(LanguLearnPrimaryButtonStyle())
                Text("Det du har skrivit finns kvar.").font(.footnote).foregroundStyle(.secondary)
            }
        } else if draft.pending != nil || draft.turns.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ditt svar är sparat. Fortsätt när du vill.")
                Button("Fortsätt med Milo", systemImage: "arrow.right") { coach.submit(store: store, course: settings.course) }.buttonStyle(LanguLearnPrimaryButtonStyle())
            }
        } else if let reply = draft.reply {
            VStack(alignment: .leading, spacing: 18) {
                if reply.kind == .probe { probe(reply, draft: draft) }
                if reply.kind == .question {
                    ForEach(reply.choices, id: \.id) { choice in
                        Button(choice.text) { send(text: choice.text) }.buttonStyle(.bordered).controlSize(.large)
                    }
                }
                Button {
                    coach.edit(store: store) { $0.difficultyFeedback = $0.difficultyFeedback == .tooHard ? nil : .tooHard }
                    milo.encourage()
                } label: {
                    Label("Det här är för svårt", systemImage: draft.difficultyFeedback == .tooHard ? "checkmark.circle.fill" : "hand.raised")
                        .frame(minHeight: 44, alignment: .leading)
                }.tint(LanguLearn.purple)
                    .accessibilityAddTraits(draft.difficultyFeedback == .tooHard ? .isSelected : [])
                if draft.difficultyFeedback == .tooHard {
                    Text("Det tar vi med oss. Skriv gärna det du kan, eller be om en enklare uppgift direkt.").font(.callout).foregroundStyle(LanguLearn.purple)
                }
                Text(reply.mode == .listen ? "Du kan också berätta vad du uppfattade. Några ord eller en förklaring på ditt eget språk räcker." : "Skriv det du kan. Några ord, en del av svaret eller en förklaring på ditt eget språk räcker.")
                    .font(.callout).foregroundStyle(.secondary)
                composer(reply.kind == .question ? "Berätta med egna ord…" : "Det här kan jag säga eller förstå…", text: binding(\.draft, limit: 700))
                Button(draft.difficultyFeedback == .tooHard ? (draft.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Prova något enklare" : "Skicka mitt svar och anpassa nivån") : "Så här tänker jag", systemImage: "arrow.up") { send() }
                    .buttonStyle(LanguLearnPrimaryButtonStyle())
                    .disabled(draft.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.difficultyFeedback != .tooHard)
                Button("Hoppa över just den här") { isTyping = false; milo.stop(); coach.submit(store: store, course: settings.course, skip: true) }
                    .font(.subheadline).frame(minHeight: 44)
                Text("Ditt svar och hur svårt det känns hjälper Milo att hitta en bättre start för dig.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
    private func probe(_ reply: DiscoveryReply, draft: JourneyDiscovery) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if reply.mode == .write || draft.usedHelp {
                Text(reply.target).font(.title3.weight(.medium)).textSelection(.enabled)
            }
            if reply.mode == .listen {
                Button(draft.heardAudio ? "Lyssna igen" : "Lyssna på situationen", systemImage: "speaker.wave.2.fill") {
                    let id = draft.id; let turnID = draft.turns.last?.id
                    milo.stop()
                    milo.narrator.speak(reply.target, in: settings.targetLanguage) {
                        guard discovery?.id == id, discovery?.turns.last?.id == turnID else { return }
                        coach.edit(store: store) { $0.heardAudio = true }
                    }
                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!settings.targetLanguage.hasVoice)
                if !settings.targetLanguage.hasVoice { Text("Ingen röst finns på enheten för det här språket. Du kan visa texten eller hoppa över.").font(.footnote) }
                ForEach(reply.choices, id: \.id) { choice in
                    Button(choice.text) {
                        milo.stop(); coach.submit(store: store, course: settings.course, choiceID: choice.id)
                    }.buttonStyle(.bordered).controlSize(.large).disabled(!draft.heardAudio && !draft.usedHelp)
                }
            }
            if draft.usedHelp {
                Text(reply.translation).font(.callout)
                Label(reply.hint, systemImage: "lightbulb").font(.callout).foregroundStyle(LanguLearn.purple)
                Text("Milo gav ett tips. Vi tar med oss att du provade med stöd.").font(.footnote).foregroundStyle(.secondary)
            } else {
                Button(reply.mode == .listen ? "Visa text och hjälp" : "Ge mig en ledtråd", systemImage: "lightbulb") {
                    coach.edit(store: store) { $0.usedHelp = true }; milo.encourage()
                }.frame(minHeight: 44)
            }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 24))
    }
    private func send(text: String? = nil) {
        isTyping = false; milo.stop(); coach.submit(store: store, course: settings.course, text: text)
    }

    private func recommendation(_ draft: JourneyDiscovery) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: draft.reading == .comfortable ? "door.left.hand.open" : "ear.badge.waveform").font(.largeTitle).foregroundStyle(LanguLearn.purple)
                Text(draft.isLocalStart ? draft.story : draft.reply?.goal ?? "").font(.title2.bold())
                if draft.isLocalStart {
                    Text(draft.reading == .comfortable ? "Vi börjar med att höra och prova en användbar fras. Du får se ett exempel innan du själv försöker." : "Vi börjar med ljud och betydelse. Sedan möter du några tecken i taget, tillsammans med ord du har hört.")
                } else { Text(draft.reply?.reason ?? "") }
                Text("Det här är vår start. Vi justerar efter det du provar och hur det känns.").font(.footnote).foregroundStyle(.secondary)
            }.padding(24).background(.white, in: RoundedRectangle(cornerRadius: 24))
            Text("Hur lång stund vill du börja med?").font(.headline)
            HStack(spacing: 12) {
                ForEach([3, 5, 10], id: \.self) { minutes in
                    Button { coach.edit(store: store) { $0.minutes = minutes } } label: {
                        Text("\(minutes) min").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(draft.minutes == minutes ? LanguLearn.purple : .white, in: Capsule())
                            .foregroundStyle(draft.minutes == minutes ? .white : LanguLearn.purple)
                    }.buttonStyle(.plain).accessibilityAddTraits(draft.minutes == minutes ? .isSelected : [])
                }
            }
            Button(editing ? "Det här passar mig" : "Vi börjar här", systemImage: "arrow.right") { if coach.accept(store: store) { dismiss() } }
                .buttonStyle(LanguLearnPrimaryButtonStyle())
            Button("Ändra det jag berättade") { coach.restart(store: store) }.frame(minHeight: 44)
            Text("Du kan ändra din riktning i Min resa. Dina svar sparas med ditt språk och hjälper Milo att välja kommande uppgifter.").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func composer(_ placeholder: LocalizedStringKey, text: Binding<String>) -> some View {
        TextField(placeholder, text: text, axis: .vertical).lineLimit(3...6).focused($isTyping)
            .padding(20).background(.white, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(LanguLearn.purple.opacity(isTyping ? 0.6 : 0.15), lineWidth: 1.5))
            .id("discovery-input")
    }
    private func binding(_ path: WritableKeyPath<JourneyDiscovery, String>, limit: Int) -> Binding<String> {
        Binding(get: { discovery?[keyPath: path] ?? "" }, set: { value in coach.edit(store: store) { $0[keyPath: path] = String(value.prefix(limit)) } })
    }
}

private struct DiscoveryMiloMoment: View {
    let milo: MiloController
    let title: String
    let caption: String
    let compact: Bool
    let speak: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 12) {
                Text(caption).font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(LanguLearn.purple)
                Text(title).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button(action: speak) {
                MiloAvatarView(controller: milo, size: 156)
                    .background(Circle().fill(LinearGradient(colors: [.white, LanguLearn.purple.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "speaker.wave.2.fill").font(.caption).foregroundStyle(LanguLearn.purple)
                            .padding(10).background(.white, in: Circle()).accessibilityHidden(true)
                    }
            }.buttonStyle(.plain).accessibilityLabel("Låt Milo läsa frågan")
                .frame(width: compact ? 0 : 156, height: compact ? 0 : 156).opacity(compact ? 0 : 1).clipped()
                .accessibilityHidden(compact)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
