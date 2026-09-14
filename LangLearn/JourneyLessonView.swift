import SwiftUI

struct JourneyLessonView: View {
    @Environment(LearningStore.self) private var store
    @Environment(TutorSettings.self) private var settings
    @Environment(OpenAIAccess.self) private var access
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var coach = JourneyCoach()
    @State private var milo = MiloController()
    let sessionID: UUID

    private var session: JourneySession? { store.journey.sessions.first { $0.id == sessionID } }
    private var course: LanguageCourse {
        LanguageCourse(target: settings.targetLanguage, native: session.flatMap { LearningLanguage.named($0.pack.explanationLanguage) } ?? settings.nativeLanguage)
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            if let session {
                VStack(alignment: .leading, spacing: 24) {
                    if let step = session.step {
                        JourneyLessonProgress(cursor: session.cursor, total: session.pack.steps.count, track: session.pack.track).id("step-top")
                        JourneyTeachingCard(step: step, session: session, milo: milo, course: course,
                            speak: speak, reveal: { edit { $0.revealedText = true } },
                            save: { save(step) }, saved: store.journey.phrases.contains { $0.text == step.target })
                        JourneyAnswerControls(session: session, course: course, busy: coach.isWorking,
                            draft: Binding(get: { self.session?.draft ?? "" }, set: { value in edit { $0.draft = String(value.prefix(500)) } }),
                            selectToken: { index in edit { session in
                                if let selected = session.selectedTokens.firstIndex(of: index) { session.selectedTokens.remove(at: selected) }
                                else { session.selectedTokens.append(index) }
                            } },
                            answer: { coach.answer(store: store, sessionID: sessionID, course: course, answer: $0) },
                            speakChoice: { milo.speak($0, in: course.native) },
                            skip: { coach.skipSpeech(store: store, sessionID: sessionID) })
                        if step.kind != .example {
                            JourneyHelpPanel(step: step, count: session.hintCount) {
                                edit { $0.hintCount = min(step.hints.count, $0.hintCount + 1) }
                                milo.leanIn()
                            } speak: { milo.speak($0, in: course.native) }
                            .id("help")
                        }
                        if let evaluation = session.evaluation {
                            JourneyFeedback(evaluation: evaluation, selfReported: step.kind == .say, speak: { milo.speak(evaluation.feedback, in: course.native) }).id("feedback")
                        }
                        if coach.isWorking { MiloLoadingView(message: "Milo läser ditt svar…", showsMascot: false) }
                        if let error = coach.errorMessage {
                            Text(error).foregroundStyle(.red)
                            if let pending = session.pendingAnswer {
                                Button("Försök skicka samma svar igen") { coach.answer(store: store, sessionID: sessionID, course: course, answer: pending) }.disabled(coach.isWorking)
                                Button("Ändra mitt svar") { coach.cancel(); edit { $0.pendingAnswer = nil; $0.pendingAttemptID = nil } }
                            }
                        }
                        if let error = milo.narrator.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
                        if milo.narrator.isSpeaking || milo.narrator.isPreparing { Button("Stoppa ljudet", systemImage: "stop.fill") { milo.stop() } }
                        if step.kind == .example || session.canAdvance {
                            Button(session.cursor == session.pack.steps.count - 1 ? "Se vad jag har övat" : "Nästa lilla steg", systemImage: "arrow.right") {
                                milo.stop()
                                edit { try $0.advance() }
                            }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
                        }
                    } else {
                        JourneyCompletion(session: session, observations: store.journey.observations.filter { $0.sessionID == session.id }, milo: milo) { difficulty in
                            edit { $0.difficultyFeedback = difficulty }
                            if difficulty == .tooHard { milo.encourage() } else { milo.enthusiastic() }
                        }.id("step-top")
                        if let error = coach.errorMessage { Text(error).foregroundStyle(.red) }
                        Button("Tillbaka", systemImage: "arrow.left") { dismiss() }.buttonStyle(.borderedProminent)
                    }
                }.padding(24).frame(maxWidth: 720).frame(maxWidth: .infinity)
            } else {
                ContentUnavailableView("Stunden finns inte här", systemImage: "book.closed", description: Text("Öppna den från språket där du började."))
            }
        }
        .scrollDismissesKeyboard(.interactively).langulearnCanvas()
        .navigationTitle(session?.pack.title ?? "Min stund").navigationBarTitleDisplayMode(.inline)
        .miloLifetime(milo)
        .onDisappear { coach.cancel() }
        .onChange(of: scenePhase) { if scenePhase != .active { coach.cancel() } }
        .onChange(of: access.revision) { coach.cancel() }
        .onChange(of: session?.hintCount) { _, count in
            if (count ?? 0) > 0 { proxy.scrollTo("help", anchor: .bottom) }
        }
        .onChange(of: session?.attempts) { _, count in
            if (count ?? 0) > 0 { proxy.scrollTo("feedback", anchor: .center) }
        }
        .onChange(of: session?.cursor) { _, _ in
            proxy.scrollTo("step-top", anchor: .top)
            if session?.completedAt != nil { milo.applaud() }
            else if session?.step?.kind == .say { milo.listen() }
            else { milo.present() }
        }
        .onChange(of: session?.evaluation) { _, result in
            guard let result else { return }
            if result.accepted { milo.joyful() } else { milo.encourage() }
        }
        .sensoryFeedback(trigger: session?.attempts ?? 0) { oldAttempts, newAttempts in
            guard newAttempts > oldAttempts, let accepted = self.session?.evaluation?.accepted else { return nil }
            return accepted ? .success : .error
        }
        .sensoryFeedback(.success, trigger: session?.completedAt != nil) { wasComplete, isComplete in
            !wasComplete && isComplete
        }
        .task { if session?.completedAt != nil { milo.joyful() } else { milo.present() } }
        }
    }

    private func edit(_ change: (inout JourneySession) throws -> Void) {
        coach.perform { try store.editJourneySession(sessionID, change) }
    }
    private func speak(_ text: String, target: Bool) {
        guard let stepID = session?.step?.id else { return }
        // Even a partially played phrase can help a reading answer. Mark that support
        // before playback; listening tasks still require the completion callback below.
        if target && session?.step?.kind == .meaningChoice {
            coach.perform { try store.editJourneySession(sessionID, stepID: stepID) { $0.heardAudio = true } }
        }
        milo.narrator.speak(text, in: target ? course.target : course.native) {
            if target {
                coach.perform { try store.editJourneySession(sessionID, stepID: stepID) { $0.heardAudio = true } }
            }
        }
    }
    private func save(_ step: JourneyStep) {
        coach.perform {
            try store.updateJourney { progress in
                guard !progress.phrases.contains(where: { $0.text == step.target }) else { return }
                progress.phrases.append(JourneyPhrase(text: step.target, translation: step.translation, explanationLanguage: course.native.code))
            }
        }
    }
}

private struct JourneyLessonProgress: View {
    let cursor: Int
    let total: Int
    let track: JourneyTrack
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(track.title).font(.subheadline.weight(.semibold)); Spacer(); Text("\(cursor + 1) / \(total)").monospacedDigit() }
            ProgressView(value: Double(cursor), total: Double(total)).tint(LanguLearn.purple)
                .accessibilityLabel("Steg \(cursor + 1) av \(total)")
        }
    }
}

private struct JourneyTeachingCard: View {
    let step: JourneyStep
    let session: JourneySession
    let milo: MiloController
    let course: LanguageCourse
    let speak: (String, Bool) -> Void
    let reveal: () -> Void
    let save: () -> Void
    let saved: Bool
    private var showsTarget: Bool { ![.write, .build, .listeningChoice].contains(step.kind) || session.revealedText || session.canAdvance }
    private var showsMeaning: Bool { step.kind == .example || step.kind == .say || session.canAdvance || ([.write, .build].contains(step.kind) && session.revealedText) }
    private var instruction: String {
        step.instruction
            .replacingOccurrences(of: "Läs modellen", with: "Läs exemplet", options: .caseInsensitive)
            .replacingOccurrences(of: "modellmeningen", with: "exempelmeningen", options: .caseInsensitive)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                Text(step.kind == .example ? "Så här kan det låta" : step.skillTitle).font(.subheadline.bold()).foregroundStyle(LanguLearn.purple).padding(.bottom, 20)
                Spacer()
                Button { milo.curious() } label: {
                    MiloAvatarView(controller: milo, size: step.kind == .example ? 152 : 106, zoom: 2.6)
                        .frame(height: step.kind == .example ? 125 : 88, alignment: .bottom).clipped()
                }.buttonStyle(.plain).accessibilityLabel("Fånga Milos uppmärksamhet").accessibilityHint("Milo lutar sig nyfiket mot dig")
            }.padding(.horizontal, 18)
            VStack(alignment: .leading, spacing: 20) {
                Text(instruction).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Button("Lyssna på uppgiften", systemImage: "speaker.wave.2") { speak(instruction, false) }
                    .font(.subheadline).disabled(!course.native.hasVoice)
                if showsTarget {
                    Text(step.target).font(step.kind == .scriptChoice ? .system(.largeTitle, design: .rounded).bold() : .title.bold())
                        .frame(maxWidth: .infinity, alignment: .center).padding(22)
                        .background(LanguLearn.purple.opacity(0.08), in: .rect(cornerRadius: 24))
                        .environment(\.layoutDirection, ["ar", "he"].contains(course.target.code) ? .rightToLeft : .leftToRight)
                }
                if showsMeaning { Text(step.translation).font(.title3).foregroundStyle(.secondary) }
                if !step.audioText.isEmpty && (showsTarget || step.kind == .listeningChoice) {
                    Button("Lyssna på Milo", systemImage: "play.circle.fill") { speak(step.audioText, true) }
                        .buttonStyle(.bordered).controlSize(.large).disabled(!course.target.hasVoice)
                    if !course.target.hasVoice { Text("Ingen röst för språket finns på enheten. Du kan använda textstödet.").font(.footnote) }
                }
                if !showsTarget {
                    Button(step.kind == .listeningChoice ? "Visa textstöd" : "Visa ett exempel att ta hjälp av") { reveal() }.font(.subheadline)
                }
                if session.revealedText { Label("Du använder textstöd", systemImage: "text.bubble").font(.footnote).foregroundStyle(.secondary) }
                if showsMeaning {
                    Button(saved ? "Sparat i mina ord" : "Behåll det här uttrycket", systemImage: saved ? "bookmark.fill" : "bookmark") { save() }.disabled(saved).font(.subheadline)
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: .rect(cornerRadius: 28))
        }
    }
}

private struct JourneyAnswerControls: View {
    let session: JourneySession
    let course: LanguageCourse
    let busy: Bool
    @Binding var draft: String
    let selectToken: (Int) -> Void
    let answer: (String) -> Void
    let speakChoice: (String) -> Void
    let skip: () -> Void

    var body: some View {
        if let step = session.step, !session.canAdvance {
            VStack(alignment: .leading, spacing: 14) {
                switch step.kind {
                case .example: EmptyView()
                case .meaningChoice, .listeningChoice, .scriptChoice:
                    ForEach(step.choices) { choice in
                        HStack(alignment: .center, spacing: 12) {
                            Button { answer(choice.id) } label: {
                                Text(choice.text).font(.title3.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(14)
                            }.buttonStyle(.plain).background(.white, in: .rect(cornerRadius: 20))
                                .disabled(step.kind == .listeningChoice && !session.heardAudio && !session.revealedText)
                            if step.kind != .scriptChoice {
                                Button { speakChoice(choice.text) } label: { Image(systemName: "speaker.wave.2").frame(width: 44, height: 44) }
                                    .accessibilityLabel("Lyssna på alternativ: \(choice.text)").disabled(!course.native.hasVoice)
                            }
                        }
                    }
                case .build:
                    Text(session.selectedTokens.map { step.tokens[$0] }.joined(separator: " ").isEmpty ? "Tryck på orden i ordning" : session.selectedTokens.map { step.tokens[$0] }.joined(separator: " "))
                        .font(.title3).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading).padding(16).background(.white, in: .rect(cornerRadius: 18))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 12) {
                        ForEach(step.tokens.indices, id: \.self) { index in
                            Button { selectToken(index) } label: {
                                Text(step.tokens[index]).frame(maxWidth: .infinity, minHeight: 44)
                            }.buttonStyle(.bordered).tint(session.selectedTokens.contains(index) ? .secondary : LanguLearn.purple)
                                .accessibilityLabel("\(step.tokens[index]), \(session.selectedTokens.contains(index) ? "valt, tryck för att ta bort" : "lägg till")")
                        }
                    }
                    Button("Prova min mening") { answer(session.selectedTokens.map { step.tokens[$0] }.joined(separator: " ")) }.buttonStyle(.borderedProminent).disabled(session.selectedTokens.isEmpty)
                case .write:
                    TextField("Ditt försök", text: $draft, axis: .vertical).lineLimit(3...7).textFieldStyle(.roundedBorder)
                        .disabled(session.pendingAnswer != nil).accessibilityHint("Skriv högst 500 tecken")
                    Text("\(draft.count) / 500").font(.caption).foregroundStyle(.secondary)
                    Button(session.pendingAnswer == nil ? "Prova mitt svar" : "Skicka sparat svar igen") { answer(draft) }.buttonStyle(.borderedProminent).disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                case .say:
                    Text("Du kan säga det högt för dig själv. Mikrofonen används inte.").font(.subheadline).foregroundStyle(.secondary)
                    Button("Jag har provat att säga det") { answer("self-reported practice") }.buttonStyle(.borderedProminent)
                    Button("Jag lyssnar bara idag", action: skip)
                }
            }.disabled(busy)
        }
    }
}

private struct JourneyHelpPanel: View {
    let step: JourneyStep
    let count: Int
    let request: () -> Void
    let speak: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(count == 0 ? "Milo, hjälp mig igång" : "Visa nästa ledtråd", systemImage: "lightbulb") { request() }
                .disabled(count >= step.hints.count)
            if count > 0 {
                Label("Milo gav ett tips", systemImage: "sparkles").font(.subheadline.bold())
                ForEach(Array(step.hints.prefix(count).enumerated()), id: \.offset) { _, hint in
                    Text(hint)
                    Button("Lyssna på tipset", systemImage: "speaker.wave.2") { speak(hint) }.font(.subheadline)
                }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(LanguLearn.purple.opacity(0.07), in: .rect(cornerRadius: 24))
    }
}

private struct JourneyFeedback: View {
    let evaluation: JourneyEvaluation
    let selfReported: Bool
    let speak: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(selfReported ? "Du provade att säga det" : evaluation.accepted ? "Det fungerar här" : "Vi provar en gång till", systemImage: evaluation.accepted ? "checkmark.circle.fill" : "arrow.uturn.backward")
                .font(.headline).foregroundStyle(evaluation.accepted ? LanguLearn.deepGreen : LanguLearn.purple)
            Text(evaluation.feedback)
            if !evaluation.correction.isEmpty { Text(evaluation.correction).font(.title3.weight(.medium)) }
            Button("Lyssna på återkopplingen", systemImage: "speaker.wave.2", action: speak).font(.subheadline)
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: .rect(cornerRadius: 24))
    }
}

private struct JourneyCompletion: View {
    let session: JourneySession
    let observations: [JourneyObservation]
    let milo: MiloController
    let chooseDifficulty: (JourneyDifficulty) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("En liten stund som räknas.").font(.largeTitle.bold())
            Button { milo.dance() } label: {
                MiloStage(controller: milo, size: 260, floorClearance: 0)
            }.buttonStyle(.plain).accessibilityLabel("Fira med Milo").accessibilityHint("Milo gör en liten segerdans")
            Text("\(session.pack.title)").font(.title2.bold())
            Text("Du tog dig igenom \(session.pack.steps.count) steg. Så här gick dina försök:").foregroundStyle(.secondary)
            ForEach(observations) { observation in
                Label(observation.title + " · " + (observation.selfReported ? "du provade att säga det" : !observation.correct ? "behövde ett nytt försök" : observation.independent ? "rätt utan tips" : "rätt med stöd"), systemImage: observation.correct ? "checkmark.circle" : "arrow.counterclockwise")
            }
            JourneyDifficultyPicker(selected: session.difficultyFeedback, choose: chooseDifficulty)
            Text("Vi återkommer till det du övat. Ett rätt svar idag behöver få växa till något du minns imorgon.").font(.body)
            Text("Tryck på Milo för att fira tillsammans.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

private struct JourneyDifficultyPicker: View {
    let selected: JourneyDifficulty?
    let choose: (JourneyDifficulty) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hur kändes nivån?").font(.headline)
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())
            layout {
                ForEach(JourneyDifficulty.allCases, id: \.self) { difficulty in
                    Button { choose(difficulty) } label: {
                        Label(difficulty.title, systemImage: selected == difficulty ? "checkmark.circle.fill" : "circle")
                            .padding(.vertical, 6)
                    }.buttonStyle(.bordered).accessibilityAddTraits(selected == difficulty ? [.isSelected] : [])
                }
            }
            Text(selected == nil ? "Ditt svar hjälper Milo att anpassa nästa stund." : "Sparat. Milo tar hänsyn till det när du skapar nästa stund.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .sensoryFeedback(.selection, trigger: selected)
    }
}
