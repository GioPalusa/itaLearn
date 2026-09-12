import SwiftUI

struct LessonPracticeView: View {
    let lesson: PlannedLesson
    @Environment(LearningStore.self) private var store
    @Environment(TutorSettings.self) private var settings
    @Environment(OpenAIAccess.self) private var access
    @State private var sessionID: UUID?
    @State private var generator = LearningChat()
    @State private var errorMessage: String?
    @State private var milo = MiloController()

    private var progress: PracticeProgress? { store.state.sessions.first { $0.id == sessionID }?.practice }
    var body: some View {
        MiloPracticeCanvas(controller: milo, thinking: generator.isWorking) {
            VStack(alignment: .leading, spacing: 20) {
                Text(lesson.title).font(.title2.bold())
                Text("Öva ord och bygg meningar från din lektion. När övningarna är skapade kan du spela utan internet.").foregroundStyle(.secondary)
                if let progress, let sessionID {
                    NavigationLink {
                        FlashcardPracticeView(sessionID: sessionID, cards: progress.pack.flashcards, lessonTitle: lesson.title)
                    } label: {
                        activityCard("Ordkort", subtitle: cardSubtitle(progress), icon: "rectangle.on.rectangle.angled", count: "\(progress.knownCardIDs.count) av \(progress.pack.flashcards.count) markerade som kända")
                    }.buttonStyle(.plain)
                    NavigationLink {
                        SentencePracticeView(sessionID: sessionID, puzzles: progress.pack.puzzles, lessonTitle: lesson.title)
                    } label: {
                        activityCard("Bygg meningen", subtitle: sentenceSubtitle(progress), icon: "square.grid.3x1.below.line.grid.1x2", count: "\(progress.solvedPuzzleIDs.count) av \(progress.pack.puzzles.count) lösta")
                    }.buttonStyle(.plain)
                    if generator.isWorking {
                        MiloLoadingView(message: "Milo skapar fler övningar…", showsMascot: false)
                    } else {
                        Button("Skapa fler övningar", systemImage: "sparkles") {
                            generator.extendPractice(store: store, sessionID: sessionID, settings: settings)
                        }
                        .buttonStyle(LanguLearnSecondaryButtonStyle())
                        .disabled(!access.hasKey)
                        Text(access.hasKey
                             ? "Milo skriver nya ordkort och meningar på samma lektion och undviker dem du redan har."
                             : "Lägg till din OpenAI API-nyckel i Inställningar för att skapa fler övningar.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Button("Skapa mina övningar", systemImage: "sparkles") {
                        guard let sessionID else { return }
                        generator.generatePractice(store: store, sessionID: sessionID, settings: settings)
                    }
                    .buttonStyle(LanguLearnPrimaryButtonStyle())
                    .disabled(generator.isWorking || sessionID == nil)
                    Text("Milo skapar ordkort och meningar utifrån lektionen och dina senaste svar. Detta använder ditt OpenAI API-konto.").font(.footnote).foregroundStyle(.secondary)
                    if generator.isWorking { MiloLoadingView(message: "Milo skapar ordkort och meningar…", showsMascot: false) }
                    // Only in this state. Every line here is written in Milo's
                    // voice with no Milo present, and the empty half-screen under
                    // it is the one pocket on this screen tall enough to hold a
                    // legible figure — once the two activity cards arrive it is
                    // not, and the tab bar would crop him at the thigh.
                    MiloStage(mood: generator.isWorking ? .thinking : .presenting, size: 240)
                        .padding(.top, 8)
                }
                if let error = errorMessage ?? generator.errorMessage {
                    Text(error).foregroundStyle(LanguLearn.red)
                    Button("Försök igen") {
                        prepare()
                        if let sessionID { generator.generatePractice(store: store, sessionID: sessionID, settings: settings) }
                    }.disabled(generator.isWorking)
                }
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .langulearnCanvas().navigationTitle("Lek och repetera")
        .inlineNavigationTitle()
        .miloLifetime(milo)
        .task { prepare(); milo.present() }
        .onDisappear { generator.cancel() }
        .onChange(of: access.revision) { generator.cancel() }
    }
    private func prepare() {
        do { sessionID = try store.lessonSession(for: lesson); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
    private func cardSubtitle(_ progress: PracticeProgress) -> String {
        guard let cursor = progress.cardCursor, cursor > 0, cursor < (progress.cardQueue?.count ?? 0) else {
            return "Vänd kortet, minns och öva igen"
        }
        return "Fortsätt på kort \(cursor + 1) av \(progress.cardQueue?.count ?? 0)"
    }
    private func sentenceSubtitle(_ progress: PracticeProgress) -> String {
        guard progress.hasUnfinishedSentence, let cursor = progress.puzzleCursor else {
            return "Ord för ord, från \(settings.nativeLanguage.displayName.lowercased()) till \(settings.targetLanguage.displayName.lowercased())"
        }
        return "Fortsätt på mening \(cursor + 1) av \(progress.pack.puzzles.count)"
    }
    private func activityCard(_ title: String, subtitle: String, icon: String, count: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.title2.bold()).foregroundStyle(LanguLearn.purple)
            Text(subtitle).foregroundStyle(.primary)
            Text(count).font(.caption).foregroundStyle(.secondary)
        }.langulearnCard()
    }
}

/// Screen 3c — a card stack that fills the screen, with known/practise counts.
struct FlashcardPracticeView: View {
    let sessionID: UUID
    /// Fallback for previews; the live pack is read from the store.
    let cards: [Flashcard]
    var lessonTitle: String = ""
    @Environment(LearningStore.self) private var store
    @Environment(TutorSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var queue: [Flashcard] = []
    @State private var index = 0
    @State private var revealed = false
    @State private var errorMessage: String?
    @State private var milo = MiloController()
    @State private var dragOffset: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Milo speaks the words on this screen, so his controller owns the narrator.
    private var narrator: SpeechNarrator { milo.narrator }

    private var progress: PracticeProgress? { store.state.sessions.first { $0.id == sessionID }?.practice }
    private var liveCards: [Flashcard] { progress?.pack.flashcards ?? cards }
    private var knownCount: Int { progress?.knownCardIDs.count ?? 0 }
    private var toPracticeCount: Int {
        max(queue.count - index - remainingUnseen, 0)
    }
    private var remainingUnseen: Int { max(liveCards.count - index, 0) }

    var body: some View {
        ViewThatFits(in: .vertical) {
            practiceContent
            ScrollView { practiceContent }
        }
        .frame(maxWidth: 760).frame(maxWidth: .infinity)
        .langulearnCanvas()
        .hideNavigationBar()
        .onAppear(perform: restoreIfNeeded)
        .onDisappear { persist() }
        .miloLifetime(milo)
    }

    private var practiceContent: some View {
        VStack(spacing: 0) {
            PracticeHeader(title: "Ordkort", subtitle: lessonTitle,
                           current: index, total: queue.count) { dismiss() }
                .padding(.horizontal, 16).padding(.top, 6)

            SegmentedProgress(current: index, total: queue.count)
                .padding(.horizontal, 16).padding(.top, 14)

            if narrator.needsStage {
                MiloNarrationBar(narrator: narrator).padding(.horizontal, 16).padding(.top, 12)
            }
            if queue.indices.contains(index) {
                cardArea(queue[index])
                actions(queue[index])
                ExerciseHelpButton(onOpen: { milo.stop() }) {
                    let card = queue[index]
                    return store.helpContext(settings: settings, activity: .flashcard,
                                             task: card.cue, material: [card.answer, card.example],
                                             sessionID: sessionID)
                }
                .padding(.horizontal, 16).padding(.top, 12)
            } else if !queue.isEmpty {
                finished
            }

            if let errorMessage {
                Text(errorMessage).font(.il(13)).foregroundStyle(LanguLearn.red).padding(.horizontal, 16)
            }
        }
    }

    // MARK: - The stack

    private func cardArea(_ card: Flashcard) -> some View {
        VStack(spacing: 6) {
            // He stands behind the stack, answers every card the learner rates, and
            // is also the one reading the word aloud — the screen never needs a
            // second portrait, or a second rig.
            MiloPeek(controller: milo, size: 144, edge: .center) {
                ZStack {
                    // Two shoulders behind the top card hint at how many are left.
                    ForEach(1...2, id: \.self) { depth in
                        if queue.count > index + depth {
                            RoundedRectangle(cornerRadius: 22)
                                .fill(.white.opacity(depth == 1 ? 0.66 : 0.4))
                                .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(Color.black.opacity(0.05), lineWidth: 1) }
                                .padding(.horizontal, CGFloat(depth) * 8)
                                .offset(y: CGFloat(depth) * 8)
                        }
                    }
                    faceCard(card)
                        .id(card.id)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.94)),
                            removal: .opacity
                        ))
                        .offset(x: dragOffset.width, y: 0)
                        .rotationEffect(.degrees(dragOffset.width / 26))
                        .overlay(alignment: dragOffset.width < 0 ? .topLeading : .topTrailing) { swipeBadge }
                        .gesture(swipe(card))
                        .animation(.spring(duration: 0.25), value: dragOffset)
                }
                // Room for the two shoulders peeking below the top card.
                .padding(.bottom, 18)
                .frame(maxHeight: 460)
                .frame(maxHeight: .infinity)
            }

            HStack(spacing: 6) {
                countLabel("\(knownCount) kända")
                dot
                countLabel("\(toPracticeCount) att öva")
                dot
                countLabel("\(remainingUnseen) kvar")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 18)
    }

    private var dot: some View {
        Circle().fill(Color.black.opacity(0.25)).frame(width: 3, height: 3)
    }

    private func countLabel(_ text: String) -> some View {
        Text(text).font(.il(12)).foregroundStyle(Color.black.opacity(0.42))
    }

    @ViewBuilder private var swipeBadge: some View {
        let magnitude = min(abs(dragOffset.width) / 90, 1)
        if magnitude > 0.15 {
            Text(dragOffset.width < 0 ? "ÖVA IGEN" : "KUNDE")
                .font(.il(12, .bold)).tracking(0.6)
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(dragOffset.width < 0 ? LanguLearn.magenta : LanguLearn.green, in: .capsule)
                .padding(18)
                .opacity(magnitude)
        }
    }

    private func faceCard(_ card: Flashcard) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : LanguLearnMotion.move) { revealed.toggle() }
        } label: {
            VStack(spacing: 0) {
                HStack {
                    Group {
                        if revealed { Text(settings.targetLanguage.displayName.uppercased()) }
                        else { Text("HUR SÄGER DU?") }
                    }
                    .font(.il(11, .semibold)).tracking(0.88)
                    .foregroundStyle(LanguLearn.magenta)
                    Spacer(minLength: 0)
                    if revealed {
                        Button { milo.speak(card.answer, in: settings.targetLanguage) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "speaker.wave.2").font(.system(size: 12, weight: .semibold))
                                Text("Lyssna").font(.il(13, .semibold))
                            }
                            .foregroundStyle(LanguLearn.purple)
                            .padding(.horizontal, 11).frame(height: 30)
                            .background(LanguLearn.purple.opacity(0.1), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(spacing: 12) {
                    Text(revealed ? card.answer : card.cue)
                        .font(.il(revealed ? 44 : 34, .bold))
                        .foregroundStyle(LanguLearn.ink)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                    if revealed {
                        Text(card.example)
                            .font(.il(17)).foregroundStyle(Color.black.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.vertical, 14)

                Rectangle().fill(LanguLearn.hairline).frame(height: 1)

                HStack(spacing: 8) {
                    Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                        .font(.system(size: 13, weight: .semibold))
                    Text(revealed ? "Visa svenska" : "Vänd kortet").font(.il(15, .semibold))
                }
                .foregroundStyle(Color.black.opacity(0.6))
                .padding(.top, 14)
            }
            // Counter-rotated so the text reads the right way round on the back face.
            .rotation3DEffect(.degrees(revealed ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            .padding(.horizontal, 22).padding(.vertical, 26)
            .frame(maxWidth: .infinity, minHeight: 284)
            .background(LanguLearn.card, in: .rect(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(LanguLearn.cardBorder, lineWidth: 1) }
            .shadow(color: .black.opacity(0.08), radius: 6, y: 6)
            // The card turns; the content above turns back.
            .rotation3DEffect(.degrees(revealed ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        }
        .buttonStyle(.plain)
    }

    private func swipe(_ card: Flashcard) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { dragOffset = $0.translation }
            .onEnded { value in
                guard abs(value.translation.width) > 90 else { dragOffset = .zero; return }
                let known = value.translation.width > 0
                dragOffset = .zero
                rate(card, known: known)
            }
    }

    // MARK: - Actions

    private func actions(_ card: Flashcard) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { rate(card, known: false) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.trianglehead.clockwise").font(.system(size: 14, weight: .semibold))
                        Text("Öva igen").font(.il(16, .semibold))
                    }
                    .foregroundStyle(LanguLearn.purple)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(LanguLearn.card, in: .capsule)
                    .overlay { Capsule().strokeBorder(LanguLearn.purple.opacity(0.24), lineWidth: 1) }
                }
                .buttonStyle(.plain)

                Button { rate(card, known: true) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark").font(.system(size: 15, weight: .bold))
                        Text("Det kunde jag").font(.il(16, .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(LanguLearn.purple, in: .capsule)
                    .shadow(color: LanguLearn.purple.opacity(0.28), radius: 4, y: 4)
                }
                .buttonStyle(.plain)
            }
            Text("Svep vänster för att öva igen, höger för känt.")
                .font(.il(12)).foregroundStyle(Color.black.opacity(0.42))
        }
        .padding(.horizontal, 16).padding(.bottom, 24)
    }

    @ViewBuilder private var finished: some View {
        VStack(spacing: 16) {
            MiloView(mood: milo.mood, size: 240, trigger: milo.trigger, zoom: 1.15,
                     onAnimationCompleted: { milo.animationCompleted(trigger: $0) })
            Label("Rundan är klar!", systemImage: "checkmark.circle.fill")
                .font(.il(28, .bold)).foregroundStyle(LanguLearn.deepGreen)
            Text("Dina markeringar är sparade. Repetera gärna de ord du vill befästa.")
                .multilineTextAlignment(.center).foregroundStyle(LanguLearn.inkSecondary)
            Button("Spela en gång till") {
                queue = liveCards.shuffled(); index = 0; revealed = false; persist()
            }
            .buttonStyle(LanguLearnPrimaryButtonStyle())
        }
        .padding(20).frame(maxHeight: .infinity)
    }

    private func rate(_ card: Flashcard, known: Bool) {
        do {
            try store.update { state in
                guard let position = state.sessions.firstIndex(where: { $0.id == sessionID }) else { throw LearningValidationError.invalidResponse }
                if known { state.sessions[position].practice?.knownCardIDs.insert(card.id) }
                else { state.sessions[position].practice?.knownCardIDs.remove(card.id) }
            }
            // The rating is the moment worth answering: a word kept, or a word
            // the learner is coming back to. Either way he replies in place.
            if known { milo.joyful() } else { milo.encourage() }
            if !known { queue.append(card) }
            withAnimation(reduceMotion ? nil : LanguLearnMotion.move) {
                index += 1; revealed = false
            }
            if index >= queue.count { milo.applaud() }
            errorMessage = nil
            persist()
        } catch { errorMessage = "Kunde inte spara kortet. Försök igen." }
    }

    /// Rebuilds the exact queue the learner left, including cards sent to the back.
    private func restoreIfNeeded() {
        guard queue.isEmpty else { return }
        let byID = Dictionary(liveCards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let restored = (progress?.cardQueue ?? []).compactMap { byID[$0] }
        if !restored.isEmpty {
            queue = restored
            index = min(max(progress?.cardCursor ?? 0, 0), queue.count)
        } else {
            queue = liveCards.shuffled()
            index = 0
            persist()
        }
    }

    /// Best effort: losing a resume point is not worth interrupting the learner.
    private func persist() {
        try? store.updatePractice(sessionID: sessionID) { progress in
            progress.cardQueue = queue.map(\.id)
            progress.cardCursor = index
        }
    }
}

/// Screen 3d — the sentence has a place for every word, and the bank keeps used
/// words visible so the learner can see what they have spent.
struct SentencePracticeView: View {
    let sessionID: UUID
    /// Fallback for previews; the live pack is read from the store so newly
    /// generated sentences appear without leaving the screen.
    let puzzles: [SentencePuzzle]
    var lessonTitle: String = ""
    @Environment(LearningStore.self) private var store
    @Environment(TutorSettings.self) private var settings
    @Environment(OpenAIAccess.self) private var access
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var assembly = WordAssembly()
    @State private var bankOrder: [Int] = []
    @State private var checked = false
    @State private var correct = false
    @State private var showAnswer = false
    @State private var errorMessage: String?
    @State private var milo = MiloController()
    @State private var chat = LearningChat()
    @State private var targetedSlot: Int?
    @State private var restored = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Lets a word fly between the bank and its place instead of blinking across.
    @Namespace private var tileMotion

    /// Milo reads the finished sentence aloud, so his controller owns the narrator.
    private var narrator: SpeechNarrator { milo.narrator }
    private var progress: PracticeProgress? { store.state.sessions.first { $0.id == sessionID }?.practice }
    private var livePuzzles: [SentencePuzzle] { progress?.pack.puzzles ?? puzzles }
    private var currentPuzzle: SentencePuzzle? {
        livePuzzles.indices.contains(index) ? livePuzzles[index] : nil
    }
    private var currentPuzzleID: String { currentPuzzle?.id ?? "" }

    var body: some View {
        MiloPracticeCanvas(controller: milo, thinking: chat.isWorking, extendsBodyBelowSafeArea: true) {
            VStack(alignment: .leading, spacing: 0) {
                PracticeHeader(title: "Bygg meningen", subtitle: lessonTitle,
                               current: index, total: livePuzzles.count) { dismiss() }
                    .padding(.top, 6)
                SegmentedProgress(current: index, total: livePuzzles.count)
                    .padding(.top, 14)

                if narrator.needsStage {
                    MiloNarrationBar(narrator: narrator).padding(.top, 12)
                }
                if livePuzzles.indices.contains(index) {
                    round(livePuzzles[index])
                } else {
                    finished.padding(.top, 24)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 40)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .langulearnCanvas()
        .hideNavigationBar()
        .motion(LanguLearnMotion.settle, checked)
        .motion(LanguLearnMotion.settle, correct)
        .onAppear(perform: restoreIfNeeded)
        .onChange(of: currentPuzzleID) {
            if let puzzle = currentPuzzle { resyncIfPuzzleChanged(puzzle) }
        }
        .onChange(of: livePuzzles.count) {
            // A new pack arrived while the round was finished: carry straight on.
            if bankOrder.isEmpty, livePuzzles.indices.contains(index) { reset() }
        }
        .onDisappear { chat.cancel(); persistPosition() }
        .miloLifetime(milo)
        .onChange(of: access.revision) { chat.cancel() }
    }

    @ViewBuilder private func round(_ puzzle: SentencePuzzle) -> some View {
        Group {
            VStack(alignment: .leading, spacing: 0) {
                Text("SÄG DET PÅ \(settings.targetLanguage.displayName.uppercased())")
                    .font(.il(11, .semibold)).tracking(0.88).foregroundStyle(LanguLearn.magenta)
                Text(puzzle.cue)
                    .font(.il(24, .bold)).foregroundStyle(LanguLearn.ink)
                    .padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .langulearnCard()
        }
        .padding(.top, 16)

        slotArea(puzzle).padding(.top, 18)
        bankArea(puzzle).padding(.top, 20)

        ExerciseHelpButton(onOpen: { milo.stop() }) {
            store.helpContext(settings: settings, activity: .sentencePuzzle,
                              task: "Build the translation using the word bank: " + puzzle.cue,
                              material: puzzle.words,
                              draft: assembly.selected.compactMap { puzzle.words.indices.contains($0) ? puzzle.words[$0] : nil }.joined(separator: " "),
                              sessionID: sessionID)
        }
        .disabled(chat.isWorking)
        .padding(.top, 16)

        if checked {
            verdict(puzzle).padding(.top, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        if let hint = progress?.hint(for: puzzle.id), !correct {
            hintCard(hint).padding(.top, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        if chat.isWorking { MiloLoadingView(message: "Milo tittar på din mening…", showsMascot: false).padding(.top, 12) }
        if let error = errorMessage ?? chat.errorMessage {
            Text(error).font(.il(13)).foregroundStyle(LanguLearn.red).padding(.top, 12)
        }

        VStack(spacing: 12) {
            if correct {
                Button(index + 1 == livePuzzles.count ? "Avsluta rundan" : "Nästa mening") { advance() }
                    .buttonStyle(LanguLearnPrimaryButtonStyle())
            } else {
                Button("Kontrollera") { check(puzzle) }
                    .buttonStyle(LanguLearnPrimaryButtonStyle())
                    .disabled(assembly.selected.isEmpty || chat.isWorking)
                Button("Börja om meningen") { move { assembly.reset() } }
                    .font(.il(16, .semibold)).foregroundStyle(LanguLearn.purple)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 18)
        // No standing Milo mid-round: measured, this screen leaves about 150pt
        // under "Börja om meningen", and a figure legible at this framing needs
        // 220. Anything that fits here is a figurine, so he waits for the
        // finished state, which has the room.
    }

    // MARK: - Slots

    /// One place per word in the primary answer, so the sentence shows its own shape.
    private func slotCount(_ puzzle: SentencePuzzle) -> Int {
        max(puzzle.answers.first?.count ?? 0, placedTiles(puzzle).count)
    }

    /// Placed tiles that actually exist in this puzzle's bank. The pack can change
    /// underneath the view, so nothing indexes `words` without checking first.
    private func placedTiles(_ puzzle: SentencePuzzle) -> [Int] {
        assembly.selected.filter { puzzle.words.indices.contains($0) }
    }

    private func bankTiles(_ puzzle: SentencePuzzle) -> [Int] {
        let known = bankOrder.filter { puzzle.words.indices.contains($0) }
        return Set(known) == Set(puzzle.words.indices) ? known : Array(puzzle.words.indices)
    }

    /// Drops stale tiles when the sentence on screen is not the one they came from.
    private func resyncIfPuzzleChanged(_ puzzle: SentencePuzzle) {
        let valid = placedTiles(puzzle)
        if valid.count != assembly.selected.count { assembly = WordAssembly(selected: valid) }
        if Set(bankOrder) != Set(puzzle.words.indices) {
            bankOrder = Array(puzzle.words.indices).shuffled()
        }
    }

    private func slotArea(_ puzzle: SentencePuzzle) -> some View {
        let placed = placedTiles(puzzle)
        let total = slotCount(puzzle)
        return VStack(alignment: .leading, spacing: 0) {
            WordFlowLayout(spacing: 6) {
                ForEach(0..<total, id: \.self) { position in
                    if position < placed.count {
                        filledSlot(placed[position], at: position, puzzle: puzzle)
                    } else {
                        emptySlot(at: position, puzzle: puzzle, isNext: position == placed.count)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
            .dropDestination(for: String.self) { items, _ in
                return drop(items, puzzle: puzzle, at: placed.count)
            }

            Rectangle().fill(Color.black.opacity(0.12)).frame(height: 1).padding(.top, 12)
            Text("Dra ett ord till en plats, eller tryck för att lägga sist.")
                .font(.il(13)).foregroundStyle(LanguLearn.inkTertiary)
                .padding(.top, 10)
        }
    }

    private func filledSlot(_ tile: Int, at position: Int, puzzle: SentencePuzzle) -> some View {
        Button {
            move { assembly.remove(tile) }
        } label: {
            placedTile(puzzle.words[tile])
                .matchedGeometryEffect(id: tile, in: tileMotion)
        }
        .buttonStyle(.plain)
        .disabled(correct)
        .draggable("\(puzzle.id):\(tile)") { placedTile(puzzle.words[tile]).shadow(radius: 8) }
        .dropDestination(for: String.self) { items, _ in
            drop(items, puzzle: puzzle, at: position)
        } isTargeted: { targeted in
            if targeted { targetedSlot = position } else if targetedSlot == position { targetedSlot = nil }
        }
        .overlay(alignment: .leading) {
            if targetedSlot == position {
                Capsule().fill(LanguLearn.magenta).frame(width: 4, height: 40).offset(x: -5)
            }
        }
        .accessibilityLabel("\(puzzle.words[tile]), plats \(position + 1), ta bort ord")
    }

    private func emptySlot(at position: Int, puzzle: SentencePuzzle, isNext: Bool) -> some View {
        let targeted = targetedSlot == position
        let highlighted = isNext || targeted
        return RoundedRectangle(cornerRadius: 12)
            .strokeBorder(
                highlighted ? LanguLearn.purple.opacity(targeted ? 0.9 : 0.4) : Color.black.opacity(0.16),
                style: StrokeStyle(lineWidth: 2, dash: [6, 4])
            )
            .background(
                highlighted ? LanguLearn.purple.opacity(targeted ? 0.14 : 0.06) : .clear,
                in: .rect(cornerRadius: 12)
            )
            .frame(width: slotWidth(at: position, puzzle: puzzle), height: 44)
            .animation(.spring(duration: 0.2), value: targeted)
            .dropDestination(for: String.self) { items, _ in
                drop(items, puzzle: puzzle, at: position)
            } isTargeted: { isTargeted in
                if isTargeted { targetedSlot = position } else if targetedSlot == position { targetedSlot = nil }
            }
            .accessibilityLabel("Tom plats \(position + 1)")
    }

    /// Empty places are sized from the word the primary answer expects there, which
    /// is the scaffolding the design intends — the shape of the sentence is a clue.
    private func slotWidth(at position: Int, puzzle: SentencePuzzle) -> CGFloat {
        guard let answer = puzzle.answers.first, answer.indices.contains(position) else { return 56 }
        return min(max(28 + CGFloat(answer[position].count) * 7, 44), 130)
    }

    private func placedTile(_ word: String) -> some View {
        Text(word)
            .font(.il(19, .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 14).frame(height: 44)
            .background(LanguLearn.purple, in: .rect(cornerRadius: 12))
            .shadow(color: LanguLearn.purple.opacity(0.22), radius: 4, y: 4)
    }

    // MARK: - Bank

    private func bankArea(_ puzzle: SentencePuzzle) -> some View {
        let hintWord = progress?.hint(for: puzzle.id)?.nextWord ?? ""
        return WordFlowLayout(spacing: 9) {
            ForEach(bankTiles(puzzle), id: \.self) { tile in
                bankTile(tile, puzzle: puzzle, used: assembly.selected.contains(tile),
                         highlighted: isHintWord(tile, puzzle: puzzle, hint: hintWord))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .dropDestination(for: String.self) { items, _ in
            guard !correct, let tile = tileID(items, puzzle: puzzle) else { return false }
            move { assembly.remove(tile) }
            return true
        }
    }

    @ViewBuilder
    private func bankTile(_ tile: Int, puzzle: SentencePuzzle, used: Bool, highlighted: Bool) -> some View {
        if used {
            // Spent words stay in place, struck through, so the bank never reflows.
            Text(puzzle.words[tile])
                .font(.il(18, .semibold))
                .foregroundStyle(Color.black.opacity(0.28))
                .strikethrough(true, color: Color.black.opacity(0.28))
                .padding(.horizontal, 15).frame(height: 44)
                .background(Color.black.opacity(0.05), in: .rect(cornerRadius: 12))
                .accessibilityLabel("\(puzzle.words[tile]), redan använt")
        } else {
            Button {
                move { assembly.place(tile, wordCount: puzzle.words.count) }
            } label: {
                Text(puzzle.words[tile])
                    .font(.il(18, .semibold)).foregroundStyle(LanguLearn.purple)
                    .padding(.horizontal, 15).frame(height: 44)
                    .background(LanguLearn.card, in: .rect(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(highlighted ? LanguLearn.magenta : LanguLearn.cardBorder,
                                          lineWidth: highlighted ? 2 : 1)
                    }
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 4)
                    .matchedGeometryEffect(id: tile, in: tileMotion)
            }
            .buttonStyle(.plain)
            .disabled(correct)
            .draggable("\(puzzle.id):\(tile)") {
                placedTile(puzzle.words[tile]).shadow(radius: 8)
            }
            .accessibilityLabel("\(puzzle.words[tile]), lägg till ord")
            .accessibilityAction(named: "Lägg först") {
                guard !correct else { return }
                assembly.insert(tile, at: 0, wordCount: puzzle.words.count); checked = false; persistPosition()
            }
        }
    }

    private func isHintWord(_ tile: Int, puzzle: SentencePuzzle, hint: String) -> Bool {
        guard !hint.isEmpty, puzzle.words.indices.contains(tile) else { return false }
        return SentencePuzzle.normalized(puzzle.words[tile]) == SentencePuzzle.normalized(hint)
    }

    // MARK: - Feedback

    @ViewBuilder private func verdict(_ puzzle: SentencePuzzle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(correct ? "Rätt! Bra jobbat." : "Nästan — prova igen",
                  systemImage: correct ? "checkmark.circle.fill" : "arrow.counterclockwise")
                .font(.headline).foregroundStyle(correct ? LanguLearn.deepGreen : LanguLearn.purple)
            Text(puzzle.explanation)
            if correct {
                Button("Lyssna", systemImage: "speaker.wave.2") {
                    milo.speak(assembly.words(in: puzzle).joined(separator: " "), in: settings.targetLanguage)
                }
            } else {
                Button(showAnswer ? "Dölj exempel" : "Visa ett möjligt svar") { showAnswer.toggle() }
                if showAnswer { Text(puzzle.answers[0].joined(separator: " ")).bold() }
            }
        }.langulearnCard()
    }

    /// Milo's tip, styled as the quiet inline note the design asks for.
    private func hintCard(_ hint: PuzzleHint) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(TeacherIdentity.name) tipsar: \(hint.hint)")
                        .font(.il(13)).foregroundStyle(Color.black.opacity(0.66))
                    Text(hint.encouragement)
                        .font(.il(13)).foregroundStyle(LanguLearn.inkTertiary)
                    if !hint.nextWord.isEmpty {
                        Text("Prova \(hint.nextWord) härnäst — ordet är markerat nedan.")
                            .font(.il(13, .semibold)).foregroundStyle(LanguLearn.magenta)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.6), in: .rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(LanguLearn.cardBorder, lineWidth: 1) }
    }

    // MARK: - Round completion

    @ViewBuilder private var finished: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Alla meningar är klara!", systemImage: "checkmark.seal.fill").font(.title.bold())
            Text("Dina framsteg är sparade. Vill du ha nya meningar på samma lektion kan \(TeacherIdentity.name) skapa fler.")
            if chat.isWorking {
                MiloLoadingView(message: "Milo skriver nya meningar…", showsMascot: false)
            } else {
                Button("Skapa fler meningar", systemImage: "sparkles") {
                    chat.extendPractice(store: store, sessionID: sessionID, settings: settings)
                }
                .buttonStyle(LanguLearnPrimaryButtonStyle())
                .disabled(!access.hasKey || progress == nil)
                Text(access.hasKey
                     ? "Milo utgår från den här lektionen och undviker meningar du redan har. Detta använder ditt OpenAI API-konto."
                     : "Lägg till din OpenAI API-nyckel i Inställningar för att skapa fler meningar.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button("Spela igen från början") { index = 0; reset() }.buttonStyle(LanguLearnSecondaryButtonStyle())
            if let error = chat.errorMessage { Text(error).foregroundStyle(LanguLearn.red) }
            MiloStage(controller: milo, size: 240).padding(.top, 4)
        }
        .task { milo.applaud() }
    }

    // MARK: - Actions

    private func tileID(_ items: [String], puzzle: SentencePuzzle) -> Int? {
        guard items.count == 1, let value = items.first, value.hasPrefix(puzzle.id + ":"),
              let tile = Int(value.dropFirst(puzzle.id.count + 1)), puzzle.words.indices.contains(tile) else { return nil }
        return tile
    }

    private func drop(_ items: [String], puzzle: SentencePuzzle, at position: Int) -> Bool {
        targetedSlot = nil
        guard !correct, let tile = tileID(items, puzzle: puzzle) else { return false }
        move { assembly.insert(tile, at: position, wordCount: puzzle.words.count) }
        return true
    }

    /// Every change to the sentence animates and persists the same way.
    private func move(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : LanguLearnMotion.move) { change() }
        checked = false
        persistPosition()
    }

    private func check(_ puzzle: SentencePuzzle) {
        checked = true; showAnswer = false
        guard puzzle.matches(assembly.words(in: puzzle)) else {
            correct = false
            milo.encourage()
            recordFailedAttempt(puzzle)
            return
        }
        do {
            try store.update { state in
                guard let position = state.sessions.firstIndex(where: { $0.id == sessionID }) else { throw LearningValidationError.invalidResponse }
                state.sessions[position].practice?.solvedPuzzleIDs.insert(puzzle.id)
                state.sessions[position].practice?.puzzleDraft = assembly.selected
            }
            correct = true; errorMessage = nil
            milo.applaud()
        } catch { correct = false; errorMessage = "Kunde inte spara svaret. Tryck på Kontrollera igen." }
    }

    /// Counts the miss and, once the learner is properly stuck, fetches help without
    /// making them hunt for a button.
    private func recordFailedAttempt(_ puzzle: SentencePuzzle) {
        try? store.updatePractice(sessionID: sessionID) { progress in
            progress.puzzleAttempts = (progress.puzzleAttempts ?? [:])
                .merging([puzzle.id: (progress.puzzleAttempts?[puzzle.id] ?? 0) + 1]) { _, new in new }
            progress.puzzleDraft = assembly.selected
        }
        guard access.hasKey, !chat.isWorking,
              progress?.hint(for: puzzle.id) == nil,
              (progress?.attempts(for: puzzle.id) ?? 0) >= 2 else { return }
        askForHint(puzzle)
    }

    private func askForHint(_ puzzle: SentencePuzzle) {
        milo.leanIn()
        chat.requestHint(store: store, sessionID: sessionID, settings: settings,
                         puzzle: puzzle, attempt: assembly.words(in: puzzle))
    }

    /// Clears the sentence before moving on: incrementing `index` first would
    /// re-render the next puzzle while the old puzzle's tiles were still placed.
    private func advance() {
        milo.stop()
        assembly.reset()
        checked = false; correct = false; showAnswer = false
        errorMessage = nil; targetedSlot = nil
        withAnimation(reduceMotion ? nil : LanguLearnMotion.move) { index += 1 }
        bankOrder = livePuzzles.indices.contains(index)
            ? Array(livePuzzles[index].words.indices).shuffled()
            : []
        persistPosition()
    }

    private func reset() {
        assembly.reset(); checked = false; correct = false; showAnswer = false
        errorMessage = nil; targetedSlot = nil; milo.stop()
        bankOrder = livePuzzles.indices.contains(index) ? Array(livePuzzles[index].words.indices).shuffled() : []
        persistPosition()
    }

    /// Restores the exact spot the learner stopped at, including a half-built sentence.
    private func restoreIfNeeded() {
        guard !restored else { return }
        restored = true
        guard let progress, !livePuzzles.isEmpty else { reset(); return }

        let cursor = progress.puzzleCursor ?? 0
        index = (0...livePuzzles.count).contains(cursor) ? cursor : 0
        guard livePuzzles.indices.contains(index) else { bankOrder = []; return }

        let puzzle = livePuzzles[index]
        let savedOrder = progress.puzzleBankOrder ?? []
        bankOrder = Set(savedOrder) == Set(puzzle.words.indices) ? savedOrder : Array(puzzle.words.indices).shuffled()
        assembly = WordAssembly(selected: (progress.puzzleDraft ?? []).filter { puzzle.words.indices.contains($0) })
        checked = false; correct = false; showAnswer = false
    }

    /// Best effort: losing a resume point is not worth interrupting the learner.
    private func persistPosition() {
        try? store.updatePractice(sessionID: sessionID) { progress in
            progress.puzzleCursor = index
            progress.puzzleDraft = assembly.selected
            progress.puzzleBankOrder = bankOrder
        }
    }
}

/// Wrap tiles using the available width, including accessibility text sizes.
struct WordFlowLayout: Layout {
    var spacing: CGFloat = 8

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
            x += itemWidth + spacing; rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), origins, widths)
    }
}

struct LessonSummaryCard: View {
    let summary: LessonWrapUp
    let mastered: Bool
    @State private var milo = MiloController()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MiloAvatarView(controller: milo, size: 112).frame(maxWidth: .infinity)
            Label(mastered ? "Lektion klar!" : "Bra övat — här är din sammanfattning", systemImage: mastered ? "checkmark.seal.fill" : "book.closed")
                .font(.title2.bold()).foregroundStyle(LanguLearn.purple)
            LearningMarkdownText(summary.summary)
            if !summary.strengths.isEmpty {
                Text("Det här har du tränat").font(.headline)
                ForEach(Array(summary.strengths.enumerated()), id: \.offset) { _, text in LearningMarkdownText("• " + text) }
            }
            Text("Ditt nästa steg").font(.headline)
            ForEach(Array(summary.nextSteps.enumerated()), id: \.offset) { _, text in LearningMarkdownText("• " + text) }
            Text(mastered ? "Dina framsteg är sparade. Du kan gå vidare." : "Passet är sparat. Öva vidare innan du går till nästa lektion.")
                .font(.footnote).foregroundStyle(.secondary)
        }.langulearnCard()
        .task { if mastered { milo.applaud() } else { milo.encourage() } }
        .miloLifetime(milo)
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
    }.langulearnCanvas().preferredColorScheme(.light)
}

#Preview("Bygg en italiensk mening") {
    NavigationStack {
        SentencePracticeView(sessionID: UUID(), puzzles: [SentencePuzzle(
            id: "cafe", cue: "Jag skulle vilja ha en kaffe, tack.",
            answers: [["Vorrei", "un", "caffè,", "per", "favore."]],
            words: ["Vorrei", "un", "caffè,", "per", "favore.", "una"],
            explanation: "Vorrei är ett artigt sätt att beställa. Caffè är maskulint: un caffè."
        )])
    }
    .environment(LearningStore())
    .environment(TutorSettings(store: UserDefaults(suiteName: "LangLearn.preview")!))
    .preferredColorScheme(.light).tint(LanguLearn.purple)
}

#Preview("Ordkort") {
    NavigationStack {
        FlashcardPracticeView(sessionID: UUID(), cards: [Flashcard(
            id: "entrance", cue: "Sista insläpp", answer: "L’ultimo ingresso", example: "L’ultimo ingresso è alle 17:30."
        )])
    }
    .environment(LearningStore())
    .environment(TutorSettings(store: UserDefaults(suiteName: "LangLearn.preview")!))
    .preferredColorScheme(.light).tint(LanguLearn.purple)
}
#endif
