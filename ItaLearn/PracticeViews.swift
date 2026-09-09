import SwiftUI

struct LessonPracticeView: View {
    let lesson: PlannedLesson
    @Environment(LearningStore.self) private var store
    @Environment(TutorSettings.self) private var settings
    @Environment(OpenAIAccess.self) private var access
    @State private var sessionID: UUID?
    @State private var generator = LearningChat()
    @State private var errorMessage: String?

    private var progress: PracticeProgress? { store.state.sessions.first { $0.id == sessionID }?.practice }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(lesson.title).font(.title2.bold())
                Text("Öva ord och bygg meningar från din lektion. När övningarna är skapade kan du spela utan internet.").foregroundStyle(.secondary)
                if let progress, let sessionID {
                    NavigationLink {
                        FlashcardPracticeView(sessionID: sessionID, cards: progress.pack.flashcards)
                    } label: {
                        activityCard("Ordkort", subtitle: "Vänd kortet, minns och öva igen", icon: "rectangle.on.rectangle.angled", count: "\(progress.knownCardIDs.count) av \(progress.pack.flashcards.count) markerade som kända")
                    }.buttonStyle(.plain)
                    NavigationLink {
                        SentencePracticeView(sessionID: sessionID, puzzles: progress.pack.puzzles)
                    } label: {
                        activityCard("Bygg meningen", subtitle: "Från svenska till italienska, ord för ord", icon: "square.grid.3x1.below.line.grid.1x2", count: "\(progress.solvedPuzzleIDs.count) av \(progress.pack.puzzles.count) lösta")
                    }.buttonStyle(.plain)
                } else {
                    Button("Skapa mina övningar", systemImage: "sparkles") {
                        guard let sessionID else { return }
                        generator.generatePractice(store: store, sessionID: sessionID, settings: settings)
                    }
                    .buttonStyle(ItaLearnPrimaryButtonStyle())
                    .disabled(generator.isWorking || sessionID == nil)
                    Text("Milo skapar ordkort och meningar utifrån lektionen och dina senaste svar. Detta använder ditt OpenAI API-konto.").font(.footnote).foregroundStyle(.secondary)
                    if generator.isWorking { MiloLoadingView(message: "Milo skapar ordkort och meningar…") }
                }
                if let error = errorMessage ?? generator.errorMessage {
                    Text(error).foregroundStyle(ItaLearn.red)
                    Button("Försök igen") {
                        prepare()
                        if let sessionID { generator.generatePractice(store: store, sessionID: sessionID, settings: settings) }
                    }.disabled(generator.isWorking)
                }
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .italearnCanvas().navigationTitle("Lek och repetera")
        .task { prepare() }
        .onDisappear { generator.cancel() }
        .onChange(of: access.revision) { generator.cancel() }
    }
    private func prepare() {
        do { sessionID = try store.lessonSession(for: lesson); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
    private func activityCard(_ title: String, subtitle: String, icon: String, count: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.title2.bold()).foregroundStyle(ItaLearn.purple)
            Text(subtitle).foregroundStyle(.primary)
            Text(count).font(.caption).foregroundStyle(.secondary)
        }.italearnCard()
    }
}

struct FlashcardPracticeView: View {
    let sessionID: UUID
    let cards: [Flashcard]
    @Environment(LearningStore.self) private var store
    @State private var queue: [Flashcard] = []
    @State private var index = 0
    @State private var revealed = false
    @State private var errorMessage: String?
    @State private var narrator = SpeechNarrator()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if queue.indices.contains(index) {
                    let card = queue[index]
                    Text("Kort \(index + 1) av \(queue.count)").font(.subheadline).foregroundStyle(.secondary)
                    ProgressView(value: Double(index), total: Double(queue.count))
                    Button { revealed.toggle() } label: {
                        VStack(spacing: 20) {
                            Text(revealed ? "ITALIENSKA" : "HUR SÄGER DU?").font(.caption.bold()).foregroundStyle(ItaLearn.magenta)
                            Text(revealed ? card.italian : card.swedish).font(.largeTitle.bold()).foregroundStyle(.primary)
                            if revealed { Text(card.example).font(.title3).foregroundStyle(.secondary) }
                            Label(revealed ? "Visa svenska" : "Vänd kortet", systemImage: "arrow.trianglehead.2.clockwise.rotate.90").font(.callout)
                        }.frame(maxWidth: .infinity, minHeight: 260).padding(24)
                            .background(.white, in: .rect(cornerRadius: 28))
                    }.buttonStyle(.plain)
                    if revealed {
                        Button("Lyssna", systemImage: "speaker.wave.2") { narrator.stop(); narrator.speak(card.italian) }
                        ViewThatFits(in: .horizontal) {
                            HStack { ratingButtons(card) }
                            VStack { ratingButtons(card) }
                        }
                    } else { Text("Försök komma på svaret innan du vänder kortet.").font(.callout).foregroundStyle(.secondary) }
                } else if !queue.isEmpty {
                    Label("Rundan är klar!", systemImage: "checkmark.circle.fill").font(.title.bold()).foregroundStyle(ItaLearn.deepGreen)
                    Text("Dina markeringar är sparade. Repetera gärna de ord du vill befästa.")
                    Button("Spela en gång till") { queue.shuffle(); index = 0; revealed = false }
                        .buttonStyle(ItaLearnPrimaryButtonStyle())
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(ItaLearn.red) }
            }.padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }.italearnCanvas().navigationTitle("Ordkort")
            .onAppear { if queue.isEmpty { queue = cards.shuffled() } }
            .onDisappear { narrator.stop() }
    }
    @ViewBuilder private func ratingButtons(_ card: Flashcard) -> some View {
        Button("Öva igen") { rate(card, known: false) }.buttonStyle(ItaLearnSecondaryButtonStyle())
        Button("Det kunde jag") { rate(card, known: true) }.buttonStyle(ItaLearnPrimaryButtonStyle())
    }
    private func rate(_ card: Flashcard, known: Bool) {
        do {
            try store.update { state in
                guard let position = state.sessions.firstIndex(where: { $0.id == sessionID }) else { throw LearningValidationError.invalidResponse }
                if known { state.sessions[position].practice?.knownCardIDs.insert(card.id) }
                else { state.sessions[position].practice?.knownCardIDs.remove(card.id) }
            }
            narrator.stop()
            if !known { queue.append(card) }
            index += 1; revealed = false; errorMessage = nil
        } catch { errorMessage = "Kunde inte spara kortet. Försök igen." }
    }
}

struct SentencePracticeView: View {
    let sessionID: UUID
    let puzzles: [SentencePuzzle]
    @Environment(LearningStore.self) private var store
    @State private var index = 0
    @State private var assembly = WordAssembly()
    @State private var bankOrder: [Int] = []
    @State private var checked = false
    @State private var correct = false
    @State private var showAnswer = false
    @State private var errorMessage: String?
    @State private var narrator = SpeechNarrator()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if puzzles.indices.contains(index) {
                    let puzzle = puzzles[index]
                    Text("Mening \(index + 1) av \(puzzles.count)").font(.subheadline).foregroundStyle(.secondary)
                    ProgressView(value: Double(index), total: Double(puzzles.count))
                    Text("BYGG PÅ ITALIENSKA").font(.caption.bold()).foregroundStyle(ItaLearn.magenta)
                    Text(puzzle.swedish).font(.title2.bold())
                    Text("Dra orden till meningen eller tryck på dem. Dra till ett annat ord för att placera framför det.").font(.callout).foregroundStyle(.secondary)
                    WordFlowLayout {
                        if assembly.selected.isEmpty { Text("Din italienska mening…").foregroundStyle(.secondary).padding(12) }
                        ForEach(assembly.selected, id: \.self) { tile in
                            wordButton(tile, puzzle: puzzle, selected: true)
                                .dropDestination(for: String.self) { items, _ in drop(items, puzzle: puzzle, before: tile) }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                    .padding(14).background(.white, in: .rect(cornerRadius: 22))
                    .dropDestination(for: String.self) { items, _ in drop(items, puzzle: puzzle) }
                    WordFlowLayout {
                        ForEach(bankOrder.filter { !assembly.selected.contains($0) }, id: \.self) { tile in
                            wordButton(tile, puzzle: puzzle, selected: false)
                        }
                    }.frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
                    .dropDestination(for: String.self) { items, _ in
                        guard !correct, let tile = tileID(items, puzzle: puzzle) else { return false }
                        assembly.remove(tile); checked = false; return true
                    }
                    if checked {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(correct ? "Rätt! Bra jobbat." : "Nästan — prova igen", systemImage: correct ? "checkmark.circle.fill" : "arrow.counterclockwise")
                                .font(.headline).foregroundStyle(correct ? ItaLearn.deepGreen : ItaLearn.purple)
                            Text(puzzle.explanation)
                            if correct {
                                Button("Lyssna", systemImage: "speaker.wave.2") { narrator.stop(); narrator.speak(assembly.words(in: puzzle).joined(separator: " ")) }
                            } else {
                                Button(showAnswer ? "Dölj exempel" : "Visa ett möjligt svar") { showAnswer.toggle() }
                                if showAnswer { Text(puzzle.answers[0].joined(separator: " ")).bold() }
                            }
                        }.italearnCard()
                    }
                    if let errorMessage { Text(errorMessage).foregroundStyle(ItaLearn.red) }
                    if correct {
                        Button(index + 1 == puzzles.count ? "Avsluta rundan" : "Nästa mening") { index += 1; reset() }
                            .buttonStyle(ItaLearnPrimaryButtonStyle())
                    } else {
                        Button("Kontrollera") { check(puzzle) }.buttonStyle(ItaLearnPrimaryButtonStyle()).disabled(assembly.selected.isEmpty)
                        Button("Börja om meningen") { reset() }.frame(maxWidth: .infinity)
                    }
                } else {
                    Label("Alla meningar är klara!", systemImage: "checkmark.seal.fill").font(.title.bold())
                    Text("Dina framsteg är sparade. Du kan spela igen när du vill.")
                    Button("Spela igen") { index = 0; reset() }.buttonStyle(ItaLearnPrimaryButtonStyle())
                }
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.italearnCanvas().navigationTitle("Bygg meningen")
            .onAppear { if bankOrder.isEmpty { reset() } }
            .onDisappear { narrator.stop() }
    }
    private func wordButton(_ tile: Int, puzzle: SentencePuzzle, selected: Bool) -> some View {
        Button {
            if selected { assembly.remove(tile) }
            else { assembly.place(tile, wordCount: puzzle.words.count) }
            checked = false
        } label: {
            Text(puzzle.words[tile]).font(.body.weight(.semibold)).padding(.horizontal, 15).padding(.vertical, 12)
                .foregroundStyle(selected ? .white : ItaLearn.purple)
                .background(selected ? ItaLearn.purple : .white, in: .rect(cornerRadius: 14))
        }.buttonStyle(.plain).disabled(correct)
            .draggable("\(puzzle.id):\(tile)")
            .accessibilityLabel("\(puzzle.words[tile]), \(selected ? "ta bort ord" : "lägg till ord")")
            .accessibilityAction(named: "Flytta först") {
                guard !correct else { return }
                assembly.place(tile, before: assembly.selected.first, wordCount: puzzle.words.count); checked = false
            }
    }
    private func tileID(_ items: [String], puzzle: SentencePuzzle) -> Int? {
        guard items.count == 1, let value = items.first, value.hasPrefix(puzzle.id + ":"),
              let tile = Int(value.dropFirst(puzzle.id.count + 1)), puzzle.words.indices.contains(tile) else { return nil }
        return tile
    }
    private func drop(_ items: [String], puzzle: SentencePuzzle, before: Int? = nil) -> Bool {
        guard !correct, let tile = tileID(items, puzzle: puzzle) else { return false }
        assembly.place(tile, before: before, wordCount: puzzle.words.count); checked = false; return true
    }
    private func check(_ puzzle: SentencePuzzle) {
        checked = true; showAnswer = false
        guard puzzle.matches(assembly.words(in: puzzle)) else { correct = false; return }
        do {
            try store.update { state in
                guard let position = state.sessions.firstIndex(where: { $0.id == sessionID }) else { throw LearningValidationError.invalidResponse }
                state.sessions[position].practice?.solvedPuzzleIDs.insert(puzzle.id)
            }
            correct = true; errorMessage = nil
        } catch { correct = false; errorMessage = "Kunde inte spara svaret. Tryck på Kontrollera igen." }
    }
    private func reset() {
        assembly.reset(); checked = false; correct = false; showAnswer = false; errorMessage = nil; narrator.stop()
        bankOrder = puzzles.indices.contains(index) ? Array(puzzles[index].words.indices).shuffled() : []
    }
}

/// Wrap tiles using the available width, including accessibility text sizes.
struct WordFlowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? 320).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews, width: bounds.width)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: ProposedViewSize(width: result.widths[index], height: nil))
        }
    }
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, origins: [CGPoint], widths: [CGFloat]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var origins: [CGPoint] = [], widths: [CGFloat] = []
        for view in subviews {
            let itemWidth = min(width, view.sizeThatFits(.unspecified).width)
            let size = view.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil))
            if x > 0 && x + itemWidth > width { y += rowHeight + 8; x = 0; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y)); widths.append(itemWidth)
            x += itemWidth + 8; rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), origins, widths)
    }
}

struct LessonSummaryCard: View {
    let summary: LessonWrapUp
    let mastered: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MiloView(mood: mastered ? .celebrating : .greeting, size: 92).frame(maxWidth: .infinity)
            Label(mastered ? "Lektion klar!" : "Bra övat — här är din sammanfattning", systemImage: mastered ? "checkmark.seal.fill" : "book.closed")
                .font(.title2.bold()).foregroundStyle(ItaLearn.purple)
            LearningMarkdownText(summary.summary)
            if !summary.strengths.isEmpty {
                Text("Det här har du tränat").font(.headline)
                ForEach(Array(summary.strengths.enumerated()), id: \.offset) { _, text in LearningMarkdownText("• " + text) }
            }
            Text("Ditt nästa steg").font(.headline)
            ForEach(Array(summary.nextSteps.enumerated()), id: \.offset) { _, text in LearningMarkdownText("• " + text) }
            Text(mastered ? "Dina framsteg är sparade. Du kan gå vidare." : "Passet är sparat. Öva vidare innan du går till nästa lektion.")
                .font(.footnote).foregroundStyle(.secondary)
        }.italearnCard()
    }
}

#if DEBUG
#Preview("Sammanfattning") {
    ScrollView {
        LessonSummaryCard(summary: LessonWrapUp(
            summary: "Du kan läsa **öppettider** och skilja på stängning och sista insläpp.",
            strengths: ["Du hittar rätt klockslag på skylten.", "Du använder **alle** framför klockslag."],
            nextSteps: ["Fortsätt med korta och artiga resemeningar."], demonstratedObjectives: [0, 1], readyToAdvance: true
        ), mastered: true).padding(20)
    }.italearnCanvas().preferredColorScheme(.light)
}

#Preview("Bygg en italiensk mening") {
    NavigationStack {
        SentencePracticeView(sessionID: UUID(), puzzles: [SentencePuzzle(
            id: "cafe", swedish: "Jag skulle vilja ha en kaffe, tack.",
            answers: [["Vorrei", "un", "caffè,", "per", "favore."]],
            words: ["Vorrei", "un", "caffè,", "per", "favore.", "una"],
            explanation: "Vorrei är ett artigt sätt att beställa. Caffè är maskulint: un caffè."
        )])
    }.environment(LearningStore()).preferredColorScheme(.light).tint(ItaLearn.purple)
}

#Preview("Ordkort") {
    NavigationStack {
        FlashcardPracticeView(sessionID: UUID(), cards: [Flashcard(
            id: "entrance", swedish: "Sista insläpp", italian: "L’ultimo ingresso", example: "L’ultimo ingresso è alle 17:30."
        )])
    }.environment(LearningStore()).preferredColorScheme(.light).tint(ItaLearn.purple)
}
#endif
