import SwiftUI

/// Subject pronouns as a game: read the sentence, pick who is doing it.
///
/// The paradigm is shown as a grid rather than a list, because the thing being
/// learned is the shape of the system — which slots the language fills, and where
/// it splits on politeness or gender.
struct PronounGameView: View {
    @Environment(LearningStore.self) private var store
    @Environment(TutorSettings.self) private var settings
    @Environment(OpenAIAccess.self) private var access
    @State private var generator = LearningChat()
    @State private var narrator = SpeechNarrator()
    @State private var picked: String?
    @State private var streak = 0
    @State private var showingParadigm = false

    private var progress: PronounGameProgress? { store.state.pronouns }
    private var round: PronounRound? {
        guard let progress, progress.game.rounds.indices.contains(progress.cursor) else { return nil }
        return progress.game.rounds[progress.cursor]
    }
    private var isCorrect: Bool { picked != nil && picked == round?.answer }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let progress {
                    if let round {
                        scoreboard(progress)
                        paradigmCard(progress.game)
                        roundCard(round, game: progress.game)
                    } else {
                        finishedCard(progress)
                        paradigmCard(progress.game)
                    }
                } else {
                    introCard
                }
                if let error = generator.errorMessage ?? store.errorMessage {
                    Text(error).foregroundStyle(LanguLearn.red).font(.callout)
                }
            }
            .padding(20).padding(.bottom, 40)
            .frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .langulearnCanvas()
        .navigationTitle("Pronomenspelet")
        .onDisappear { narrator.stop(); generator.cancel() }
    }

    // MARK: - Before there is a game

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            MiloView(size: 120).frame(maxWidth: .infinity)
            Text("Vem gör vad?").font(.il(26, .bold)).foregroundStyle(LanguLearn.ink)
            Text("Subjektspronomen är de småord som avgör vem meningen handlar om. Milo bygger ett spel för \(settings.targetLanguage.displayName.lowercased()): du får meningar med ett hål och väljer vem som gör saken.")
                .font(.il(15)).foregroundStyle(LanguLearn.inkSecondary)
            if generator.isWorking {
                MiloLoadingView(message: "Milo bygger pronomenspelet…")
            } else {
                Button("Skapa spelet", systemImage: "sparkles") {
                    generator.generatePronounGame(store: store, settings: settings)
                }
                .buttonStyle(LanguLearnPrimaryButtonStyle())
                .disabled(!access.hasKey)
                Text(access.hasKey
                     ? "Skapas en gång per språk. Sedan kan du spela utan internet."
                     : "Lägg till din OpenAI API-nyckel i Inställningar för att skapa spelet.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .langulearnCard()
    }

    // MARK: - Playing

    private func scoreboard(_ progress: PronounGameProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Label("\(streak)", systemImage: "flame.fill")
                    .foregroundStyle(streak > 0 ? LanguLearn.magenta : LanguLearn.inkQuaternary)
                    .accessibilityLabel("Svit: \(streak) rätt i rad")
                Spacer()
                Text("\(progress.cursor + 1) av \(progress.game.rounds.count)")
                    .font(.ilMono(13)).foregroundStyle(LanguLearn.inkSecondary)
            }
            .font(.il(15, .semibold))
            ProgressView(value: Double(progress.cursor), total: Double(progress.game.rounds.count))
                .tint(LanguLearn.purple)
        }
        .langulearnCard()
    }

    private func roundCard(_ round: PronounRound, game: PronounGame) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(round.translation)
                .font(.il(15)).foregroundStyle(LanguLearn.inkSecondary)
            sentence(round)
            pronounChips(game, round: round)
            if let picked {
                feedback(round, picked: picked)
            }
        }
        .langulearnCard()
    }

    /// The blank is the point of the exercise, so it is drawn as a slot rather
    /// than as three underscores in a run of text.
    private func sentence(_ round: PronounRound) -> some View {
        let parts = round.sentence.components(separatedBy: PronounGame.blank)
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(parts.first ?? "")
            Text(picked ?? "?")
                .foregroundStyle(picked == nil ? LanguLearn.inkQuaternary : .white)
                .padding(.horizontal, 10).padding(.vertical, 2)
                .background(
                    picked == nil ? AnyShapeStyle(LanguLearn.purple.opacity(0.12))
                                  : AnyShapeStyle(isCorrect ? LanguLearn.deepGreen : LanguLearn.red),
                    in: .rect(cornerRadius: 8)
                )
            Text(parts.dropFirst().joined(separator: PronounGame.blank))
        }
        .font(.il(22, .semibold))
        .foregroundStyle(LanguLearn.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(round.sentence.replacingOccurrences(of: PronounGame.blank, with: "tomrum"))
    }

    private func pronounChips(_ game: PronounGame, round: PronounRound) -> some View {
        WordFlowLayout(spacing: 8) {
            ForEach(game.pronouns) { pronoun in
                Button {
                    choose(pronoun.pronoun, round: round)
                } label: {
                    VStack(spacing: 1) {
                        Text(pronoun.pronoun).font(.il(17, .semibold))
                        if !pronoun.pronunciation.isEmpty {
                            Text(pronoun.pronunciation).font(.il(11)).opacity(0.7)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .foregroundStyle(chipInk(pronoun.pronoun, round: round))
                    .background(chipFill(pronoun.pronoun, round: round), in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(isCorrect)
                .accessibilityLabel("\(pronoun.pronoun), \(pronoun.meaning)")
            }
        }
    }

    private func chipInk(_ form: String, round: PronounRound) -> Color {
        guard let picked, picked == form else { return LanguLearn.ink }
        return .white
    }

    private func chipFill(_ form: String, round: PronounRound) -> AnyShapeStyle {
        guard let picked, picked == form else { return AnyShapeStyle(LanguLearn.purple.opacity(0.10)) }
        return AnyShapeStyle(form == round.answer ? LanguLearn.deepGreen : LanguLearn.red)
    }

    private func feedback(_ round: PronounRound, picked: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(isCorrect ? "Rätt!" : "Inte riktigt", systemImage: isCorrect ? "checkmark.circle.fill" : "arrow.uturn.left")
                .font(.il(15, .semibold))
                .foregroundStyle(isCorrect ? LanguLearn.deepGreen : LanguLearn.red)
            Text(isCorrect ? round.explanation : "Prova igen — vem är det som gör det här?")
                .font(.il(15)).foregroundStyle(LanguLearn.inkSecondary)
            if isCorrect {
                HStack(spacing: 12) {
                    Button("Nästa", systemImage: "arrow.right") { advance() }
                        .buttonStyle(LanguLearnPrimaryButtonStyle())
                    if settings.targetLanguage.hasVoice {
                        Button("Lyssna", systemImage: "speaker.wave.2") {
                            narrator.stop()
                            narrator.speak(round.sentence.replacingOccurrences(of: PronounGame.blank, with: round.answer),
                                           in: settings.targetLanguage)
                        }
                        .font(.callout)
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: - The paradigm

    private func paradigmCard(_ game: PronounGame) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(LanguLearnMotion.move) { showingParadigm.toggle() }
            } label: {
                HStack {
                    Text("Pronomen i \(settings.targetLanguage.displayName.lowercased())")
                        .font(.il(15, .semibold)).foregroundStyle(LanguLearn.ink)
                    Spacer()
                    Image(systemName: showingParadigm ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold)).foregroundStyle(LanguLearn.inkTertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if showingParadigm {
                Text(game.overview).font(.il(14)).foregroundStyle(LanguLearn.inkSecondary)
                ForEach([false, true], id: \.self) { plural in
                    let group = game.pronouns.filter { $0.plural == plural }
                    if !group.isEmpty {
                        Text(plural ? "FLERTAL" : "ENTAL")
                            .font(.il(11, .semibold)).tracking(0.6)
                            .foregroundStyle(LanguLearn.inkQuaternary)
                            .padding(.top, 4)
                        ForEach(group.sorted { $0.person < $1.person }) { pronoun in
                            paradigmRow(pronoun)
                        }
                    }
                }
            }
        }
        .langulearnCard()
    }

    private func paradigmRow(_ pronoun: SubjectPronoun) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(pronoun.pronoun).font(.il(16, .semibold)).foregroundStyle(LanguLearn.purple)
                if !pronoun.pronunciation.isEmpty {
                    Text(pronoun.pronunciation).font(.il(11)).foregroundStyle(LanguLearn.inkQuaternary)
                }
            }
            .frame(minWidth: 74, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(pronoun.meaning).font(.il(15)).foregroundStyle(LanguLearn.ink)
                if !pronoun.note.isEmpty {
                    Text(pronoun.note).font(.il(12)).foregroundStyle(LanguLearn.inkTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Finished

    private func finishedCard(_ progress: PronounGameProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MiloView(mood: .celebrating, size: 110).frame(maxWidth: .infinity)
            Text("Alla rundor klara").font(.il(24, .bold)).foregroundStyle(LanguLearn.ink)
            Text("\(progress.firstTryCount) av \(progress.game.rounds.count) satt direkt. Längsta svit: \(progress.bestStreak).")
                .font(.il(15)).foregroundStyle(LanguLearn.inkSecondary)
            Button("Spela om samma rundor", systemImage: "arrow.counterclockwise") { replay() }
                .buttonStyle(LanguLearnSecondaryButtonStyle())
            if generator.isWorking {
                MiloLoadingView(message: "Milo skriver nya rundor…")
            } else {
                Button("Nya rundor", systemImage: "sparkles") {
                    generator.refreshPronounGame(store: store, settings: settings)
                }
                .buttonStyle(LanguLearnPrimaryButtonStyle())
                .disabled(!access.hasKey)
            }
        }
        .langulearnCard()
    }

    // MARK: - Moves

    private func choose(_ form: String, round: PronounRound) {
        guard !isCorrect else { return }
        withAnimation(LanguLearnMotion.pop) { picked = form }
        let correct = form == round.answer
        streak = correct ? streak + 1 : 0
        try? store.updatePronouns { progress in
            progress.attemptsByRound[round.id, default: 0] += 1
            if correct {
                progress.solvedRoundIDs.insert(round.id)
                progress.bestStreak = max(progress.bestStreak, streak)
            }
        }
    }

    private func advance() {
        picked = nil
        narrator.stop()
        try? store.updatePronouns { $0.cursor += 1 }
    }

    private func replay() {
        picked = nil
        streak = 0
        try? store.updatePronouns { progress in
            progress.cursor = 0
            progress.solvedRoundIDs = []
            progress.attemptsByRound = [:]
        }
    }
}
