import SwiftUI

/// Captures the draft and active exercise on tap; nothing is submitted by opening the sheet.
struct ExerciseHelpButton: View {
    var title: LocalizedStringKey = "Be Milo om hjälp"
    var systemImage = "questionmark.bubble"
    var transcript: ExerciseHelpTranscript?
    var onOpen: () -> Void = {}
    var onTranscriptChange: (ExerciseHelpTranscript) -> Void = { _ in }
    let context: () -> ExerciseHelpContext
    @State private var snapshot: ExerciseHelpTranscript?

    var body: some View {
        Button(title, systemImage: systemImage) {
            onOpen()
            snapshot = transcript ?? ExerciseHelpTranscript(exercise: context(), exchanges: [])
        }
        .buttonStyle(ExerciseHelpButtonStyle())
        .accessibilityHint("Få en förklaring eller ett tips utan att skicka ditt svar")
        .sheet(item: $snapshot) { snapshot in
            ExerciseHelpView(transcript: snapshot) { updated in
                self.snapshot = updated
                onTranscriptChange(updated)
            }
        }
    }
}

struct ExerciseHelpView: View {
    let transcriptID: UUID
    let exercise: ExerciseHelpContext
    let onTranscriptChange: (ExerciseHelpTranscript) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(OpenAIAccess.self) private var access
    @Environment(TutorSettings.self) private var settings
    @State private var help: ExerciseHelpSession
    @State private var question = ""
    @State private var showingSettings = false
    @State private var milo = MiloController()
    @FocusState private var questionFocused: Bool

    init(transcript: ExerciseHelpTranscript,
         onTranscriptChange: @escaping (ExerciseHelpTranscript) -> Void = { _ in }) {
        transcriptID = transcript.id
        exercise = transcript.exercise
        self.onTranscriptChange = onTranscriptChange
        _help = State(initialValue: ExerciseHelpSession(exchanges: transcript.exchanges))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        introduction
                        if !access.hasKey {
                            Text("Lägg till din OpenAI API-nyckel i Inställningar för att få hjälp av Milo.")
                                .font(.callout)
                            Button("Öppna inställningar") { showingSettings = true }
                        }
                        ForEach(help.exchanges) { exchange in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(exchange.question.isEmpty ? exchange.kind.title : exchange.question)
                                    .font(.headline)
                                LearningMarkdownText(exchange.answer)
                                    .textSelection(.enabled)
                                Button("Lyssna på förklaringen", systemImage: "speaker.wave.2") {
                                    milo.speak(LearningMarkdown.spoken(exchange.answer), in: exercise.course.native)
                                }
                                .font(.callout)
                            }
                            .langulearnCard()
                        }
                        if help.isWorking {
                            ProgressView("Milo hjälper dig…")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let error = help.errorMessage {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(error).foregroundStyle(LanguLearn.red)
                                Button("Försök igen") { help.retry() }
                                    .disabled(help.isWorking || !access.hasKey)
                                Button("Öppna inställningar") { showingSettings = true }
                            }
                            .langulearnCard()
                        }
                        questionCard
                        Color.clear.frame(height: 1).id("helpBottom")
                    }
                    .padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: help.exchanges.count) {
                    question = ""
                    onTranscriptChange(ExerciseHelpTranscript(
                        id: transcriptID, exercise: exercise, exchanges: help.exchanges
                    ))
                    withAnimation { proxy.scrollTo("helpBottom", anchor: .bottom) }
                }
            }
            .langulearnCanvas()
            .navigationTitle("Hjälp av Milo")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tillbaka till uppgiften") { dismiss() }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
        .miloLifetime(milo)
        .onDisappear { help.cancel() }
        .onChange(of: access.revision) { help.cancel() }
        .onChange(of: settings.course) { help.cancel(); dismiss() }
    }

    private var introduction: some View {
        HStack(alignment: .top, spacing: 14) {
            MiloAvatarView(controller: milo, mood: help.isWorking ? .thinking : nil, size: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Vi tar det steg för steg").font(.title2.bold())
                Text("Du behöver inte kunna formulera dig på \(exercise.course.target.displayName.lowercased()). Välj en knapp eller fråga på \(exercise.course.native.displayName.lowercased()).")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Milo har uppgiften och det du börjat skriva framför sig.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var questionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(help.exchanges.isEmpty ? "Vad vill du ha hjälp med?" : "Vill du att Milo förklarar mer?")
                .font(.headline)
            TextField("Ett ord eller en fråga, om du vill…", text: $question, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.plain)
                .padding(12)
                .background(.background, in: .rect(cornerRadius: 12))
                .focused($questionFocused)
                .disabled(help.isWorking)
                .accessibilityLabel("Din fråga till Milo")
            if question.count > 1800 {
                Text("\(question.count) / 2000 tecken").font(.caption)
                    .foregroundStyle(question.count > 2000 ? LanguLearn.red : LanguLearn.inkSecondary)
            }
            ForEach(ExerciseHelpKind.allCases.filter { $0 != .followUp }, id: \.self) { kind in
                Button { ask(kind) } label: {
                    Text(kind.title).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(ExerciseHelpButtonStyle())
                .disabled(question.count > 2000)
            }
            if !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Fråga Milo", systemImage: "arrow.up.bubble") { ask(.followUp) }
                    .buttonStyle(ExerciseHelpButtonStyle(prominent: true))
                    .disabled(question.count > 2000)
            }
        }
        .disabled(help.isWorking || !access.hasKey)
    }

    private func ask(_ kind: ExerciseHelpKind) {
        questionFocused = false
        milo.stop()
        help.ask(kind, question: question, exercise: exercise)
    }
}

/// Help must remain readable for a new learner at every accessibility text size.
private struct ExerciseHelpButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(prominent ? Color.white : LanguLearn.purple)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .fixedSize(horizontal: false, vertical: true)
            .background(prominent ? LanguLearn.purple : LanguLearn.purple.opacity(0.1),
                        in: .rect(cornerRadius: 16))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.5)
            .sensoryFeedback(.selection, trigger: configuration.isPressed) { wasPressed, isPressed in
                !wasPressed && isPressed
            }
    }
}
