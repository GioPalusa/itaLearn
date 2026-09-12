import SwiftUI

/// The Öva tab: every way into practice for the lesson the learner is on, plus
/// the language-level drills that do not belong to any single lesson.
struct PracticeHubView: View {
    @Environment(LearningStore.self) private var store
    @Environment(TutorSettings.self) private var settings
    @State private var planner = LearningChat()

    private var lesson: PlannedLesson? {
        guard let plan = store.state.activePlan else { return nil }
        return plan.lessons.first {
            !plan.completedLessonIDs.contains($0.id)
                && $0.prerequisites.allSatisfy(plan.completedLessonIDs.contains)
        }
    }

    /// Read without creating: opening this tab should not start a lesson session.
    private var session: LessonSession? {
        guard let lesson else { return nil }
        return store.state.sessions.last { $0.lessonID == lesson.id }
    }
    private var practice: PracticeProgress? { session?.practice }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let lesson {
                    // The tab opens with its host rather than a grey instruction.
                    MiloWhisper(text: "Välj hur du vill öva. Jag är med hela vägen.")
                        .padding(.horizontal, 2).padding(.bottom, 2)

                    NavigationLink { LessonOverviewView(lesson: lesson) } label: {
                        row("Fortsätt lektionen", lesson.title,
                            icon: "bubble.left.and.bubble.right", tint: LanguLearn.purple)
                    }.buttonStyle(.plain)

                    NavigationLink { cardsDestination(lesson) } label: {
                        row("Ordkort", cardsCaption,
                            icon: "rectangle.on.rectangle.angled", tint: LanguLearn.cyan)
                    }.buttonStyle(.plain)

                    NavigationLink { sentencesDestination(lesson) } label: {
                        row("Bygg meningar", sentencesCaption,
                            icon: "square.grid.3x1.below.line.grid.1x2", tint: LanguLearn.magenta)
                    }.buttonStyle(.plain)

                    pronounLink
                    freeChatLink
                    writingLink
                } else {
                    MiloWhisper(text: "Du har gått igenom planen. Välj hur du vill fortsätta, eller öva vidare under tiden.")
                        .padding(.horizontal, 2).padding(.bottom, 2)
                    pronounLink
                    freeChatLink
                    writingLink
                    PlanDirectionPicker(planner: planner).langulearnCard()
                    NavigationLink("Testa mina kunskaper igen") { AdaptiveChatView(mode: .assessment) }
                        .buttonStyle(LanguLearnSecondaryButtonStyle())
                }
            }
            .padding(20).padding(.bottom, 40)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .langulearnCanvas()
        .navigationTitle("Öva")
    }

    private var pronounLink: some View {
        NavigationLink { PronounGameView() } label: {
            row("Pronomenspelet", pronounCaption, icon: "person.2.wave.2", tint: LanguLearn.green)
        }.buttonStyle(.plain)
    }

    private var freeChatLink: some View {
        NavigationLink { AdaptiveChatView(mode: .freeChat) } label: {
            // The one row that leads to Milo himself wears his face instead of a
            // symbol, so it reads as a person to talk to rather than a feature.
            row("Chatta fritt med Milo", freeChatCaption,
                icon: "bubble.left.and.text.bubble.right", tint: LanguLearn.purple, showsMilo: true)
        }.buttonStyle(.plain)
    }

    private var writingLink: some View {
        NavigationLink { WritingDeskView() } label: {
            row("Skriv och få respons", writingCaption,
                icon: "square.and.pencil", tint: LanguLearn.magenta)
        }.buttonStyle(.plain)
    }

    // MARK: - Where each row goes
    //
    // Flashcards and sentences need a generated pack. When there is none yet the
    // row leads to the screen that makes one, rather than to an empty game.

    @ViewBuilder private func cardsDestination(_ lesson: PlannedLesson) -> some View {
        if let practice, let id = session?.id, !practice.pack.flashcards.isEmpty {
            FlashcardPracticeView(sessionID: id, cards: practice.pack.flashcards, lessonTitle: lesson.title)
        } else {
            LessonPracticeView(lesson: lesson)
        }
    }

    @ViewBuilder private func sentencesDestination(_ lesson: PlannedLesson) -> some View {
        if let practice, let id = session?.id, !practice.pack.puzzles.isEmpty {
            SentencePracticeView(sessionID: id, puzzles: practice.pack.puzzles, lessonTitle: lesson.title)
        } else {
            LessonPracticeView(lesson: lesson)
        }
    }

    // MARK: - Captions

    private var cardsCaption: String {
        guard let practice else { return "Skapa kort från lektionen" }
        return "\(practice.knownCardIDs.count) av \(practice.pack.flashcards.count) kan du"
    }

    private var sentencesCaption: String {
        guard let practice else { return "Skapa meningar från lektionen" }
        if practice.hasUnfinishedSentence { return "Fortsätt där du slutade" }
        return "\(practice.solvedPuzzleIDs.count) av \(practice.pack.puzzles.count) lösta"
    }

    private var pronounCaption: String {
        guard let pronouns = store.state.pronouns else {
            return "Lär dig vem som gör vad i \(settings.targetLanguage.displayName.lowercased())"
        }
        if pronouns.isComplete { return "Klart · längsta svit \(pronouns.bestStreak)" }
        return "\(pronouns.solvedRoundIDs.count) av \(pronouns.game.rounds.count) klara"
    }

    private var freeChatCaption: String {
        let turns = store.state.freeChat?.messages.filter { $0.role == .user }.count ?? 0
        return turns == 0
            ? "Prata om vad du vill, i din takt"
            : "Fortsätt samtalet · \(turns) svar hittills"
    }

    private var writingCaption: String {
        let count = store.state.writings?.count ?? 0
        return count == 0
            ? "Skriv en text och få den rättad"
            : "\(count) \(count == 1 ? "text" : "texter") lästa av Milo"
    }

    private func row(_ title: LocalizedStringKey, _ caption: String,
                     icon: String, tint: Color, showsMilo: Bool = false) -> some View {
        HStack(spacing: 14) {
            Group {
                if showsMilo {
                    MiloAvatarView(mood: .still, size: 44)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(tint)
                        .frame(width: 44, height: 44)
                        .background(tint.opacity(0.12), in: .rect(cornerRadius: 13))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.il(17, .semibold)).foregroundStyle(LanguLearn.ink)
                Text(caption).font(.il(14)).foregroundStyle(LanguLearn.inkSecondary)
                    .lineLimit(2).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            RowChevron()
        }
        .langulearnCard()
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
