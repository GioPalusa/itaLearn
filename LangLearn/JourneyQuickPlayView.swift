import SwiftUI

enum JourneyQuickGame: Hashable {
    case cards, listening, build

    var title: LocalizedStringResource {
        switch self {
        case .cards: "Ordblixten"
        case .listening: "Lyssna & hitta"
        case .build: "Bygg frasen"
        }
    }
}

/// A bounded, local deck made only from material Milo has already shown.
/// Opening a quick game never waits for a new model response.
struct JourneyPracticeMaterial {
    let cards: [JourneyStep]
    let builds: [JourneyStep]

    init(progress: JourneyProgress, course: LanguageCourse) {
        let learned = progress.sessions.reversed().flatMap(\.pack.steps)
        // A confident learner with no Journey history should not be dropped into
        // the beginner greeting deck. Their first guided scene seeds richer games.
        let fallback = progress.profile?.startingExperience.isExperienced == true
            ? []
            : FoundationContent.welcome(course: course)?.steps ?? []
        var seen = Set<String>()
        cards = (learned + fallback).filter { step in
            let key = JourneyStep.normalized(step.target) + "|" + JourneyStep.normalized(step.translation)
            return !key.isEmpty && seen.insert(key).inserted
        }

        let avoidsSpaceBuilding = ["ja", "zh", "th"].contains(course.target.code)
        builds = avoidsSpaceBuilding ? [] : cards.compactMap { step in
            if step.kind == .build { return step }
            let words = step.target.split(whereSeparator: \.isWhitespace).map(String.init)
            guard words.count >= 2, words.count <= 10 else { return nil }
            var copy = step
            copy.kind = .build
            copy.skill = .writing
            copy.tokens = words.enumerated().sorted {
                ($0.offset * 7 + 3) % words.count < ($1.offset * 7 + 3) % words.count
            }.map(\.element)
            copy.acceptedAnswers = [step.target]
            copy.choices = []
            copy.correctChoiceID = ""
            return copy
        }
    }
}

struct JourneyQuickPlayView: View {
    let game: JourneyQuickGame
    let steps: [JourneyStep]
    @Environment(LearningStore.self) private var store
    @Environment(TutorSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var revealed = false
    @State private var selectedTokens: [Int] = []
    @State private var result: Bool?
    @State private var streak = 0
    @State private var narrator = SpeechNarrator()

    private var step: JourneyStep? { steps.indices.contains(index) ? steps[index] : nil }

    var body: some View {
        VStack(spacing: 0) {
            QuickPlayHeader(title: game.title, current: min(index + 1, steps.count), total: steps.count, streak: streak) {
                dismiss()
            }
            .padding(.horizontal, 18).padding(.top, 8)

            ProgressView(value: Double(index), total: Double(max(steps.count, 1)))
                .tint(LanguLearn.purple).padding(.horizontal, 22).padding(.top, 14)

            if let step {
                switch game {
                case .cards: QuickFlashcardRound(step: step, revealed: $revealed, speak: speak, rate: rate)
                case .listening: QuickListeningRound(step: step, revealed: $revealed, speak: speak, rate: rate)
                case .build:
                    QuickBuildRound(step: step, selected: $selectedTokens, result: result, check: checkBuild, next: advance)
                }
            } else {
                QuickPlayFinish(game: game, streak: streak) { dismiss() }
            }

            if narrator.needsStage {
                MiloNarrationBar(narrator: narrator).padding(.horizontal, 20).padding(.bottom, 12)
            }
        }
        .frame(maxWidth: 720).frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [LanguLearn.canvas, LanguLearn.purple.opacity(0.08)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .hideNavigationBar()
        .onChange(of: selectedTokens) {
            if result == false { result = nil }
        }
        .sensoryFeedback(.selection, trigger: selectedTokens)
        .sensoryFeedback(.selection, trigger: revealed) { wasRevealed, isRevealed in
            !wasRevealed && isRevealed
        }
        .sensoryFeedback(trigger: result) { _, result in
            guard let result else { return nil }
            return result ? .success : .error
        }
        .sensoryFeedback(.success, trigger: index) { oldIndex, newIndex in
            oldIndex < steps.count && newIndex >= steps.count
        }
        .onDisappear { narrator.stop() }
    }

    private func speak() {
        guard let step else { return }
        narrator.speak(step.audioText.isEmpty ? step.target : step.audioText, in: settings.targetLanguage)
    }

    private func rate(_ knewIt: Bool) {
        guard let step else { return }
        record(step, correct: knewIt, independent: false, selfReported: true)
        streak = knewIt ? streak + 1 : 0
        advance()
    }

    private func checkBuild() {
        guard let step else { return }
        let answer = selectedTokens.map { step.tokens[$0] }.joined(separator: " ")
        let accepted = step.acceptedAnswers.contains { JourneyStep.normalized($0) == JourneyStep.normalized(answer) }
        result = accepted
        if accepted {
            streak += 1
            record(step, correct: true, independent: true, selfReported: false)
        }
    }

    private func record(_ step: JourneyStep, correct: Bool, independent: Bool, selfReported: Bool) {
        do {
            try store.updateJourney { progress in
                progress.record(JourneyObservation(
                    id: UUID(), skillID: step.skillID, title: step.skillTitle, skill: step.skill,
                    correct: correct, independent: independent, selfReported: selfReported,
                    date: .now, phrase: step.target, translation: step.translation
                ))
            }
        } catch { store.errorMessage = error.localizedDescription }
    }

    private func advance() {
        let change = {
            index += 1
            revealed = false
            selectedTokens = []
            result = nil
        }
        if reduceMotion { change() } else { withAnimation(LanguLearnMotion.move) { change() } }
    }
}

private struct QuickPlayHeader: View {
    let title: LocalizedStringResource
    let current: Int
    let total: Int
    let streak: Int
    let close: () -> Void

    var body: some View {
        HStack {
            Button(action: close) {
                GlassCircle(size: 48) { Image(systemName: "xmark").font(.headline) }
            }
            .buttonStyle(.plain).accessibilityLabel("Stäng spelet")
            Spacer()
            VStack(spacing: 2) {
                Text(title).font(.headline)
                Text("\(current) av \(total)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            Label("\(streak)", systemImage: "bolt.fill")
                .font(.subheadline.bold()).foregroundStyle(LanguLearn.magenta).frame(width: 48)
        }
    }
}

private struct QuickFlashcardRound: View {
    let step: JourneyStep
    @Binding var revealed: Bool
    let speak: () -> Void
    let rate: (Bool) -> Void

    var body: some View {
        VStack(spacing: 22) {
            Text("MINNS DU?").font(.caption.bold()).tracking(1.4).foregroundStyle(LanguLearn.magenta)
            Button { withAnimation(LanguLearnMotion.move) { revealed.toggle() } } label: {
                VStack(spacing: 18) {
                    Text(step.translation).font(.title2.bold()).foregroundStyle(.primary)
                    if revealed {
                        Divider()
                        Text(step.target).font(.largeTitle.bold()).foregroundStyle(LanguLearn.purple)
                    } else {
                        Label("Tryck för att vända", systemImage: "hand.tap.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(LanguLearn.purple)
                    }
                }
                .padding(28).frame(maxWidth: .infinity, minHeight: 330)
                .background(.white, in: .rect(cornerRadius: 34))
                .shadow(color: LanguLearn.purple.opacity(0.12), radius: 18, y: 10)
            }.buttonStyle(.plain).accessibilityHint(revealed ? "Visar uttrycket" : "Visar svaret")

            if revealed {
                Button("Lyssna", systemImage: "speaker.wave.2.fill", action: speak)
                    .font(.headline).buttonStyle(.bordered).controlSize(.large)
                HStack(spacing: 12) {
                    Button("Öva igen") { rate(false) }.buttonStyle(LanguLearnSecondaryButtonStyle(tint: LanguLearn.magenta, fill: LanguLearn.magenta.opacity(0.10)))
                    Button("Den satt!") { rate(true) }.buttonStyle(LanguLearnSecondaryButtonStyle(tint: LanguLearn.deepGreen, fill: LanguLearn.green.opacity(0.14)))
                }
            }
        }.padding(24).frame(maxHeight: .infinity)
    }
}

private struct QuickListeningRound: View {
    let step: JourneyStep
    @Binding var revealed: Bool
    let speak: () -> Void
    let rate: (Bool) -> Void

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().fill(LanguLearn.cyan.opacity(0.14)).frame(width: 220, height: 220)
                MiloAvatarView(mood: .listening, size: 184, zoom: 2.6)
                Button(action: speak) {
                    Image(systemName: "play.fill").font(.title2).foregroundStyle(.white)
                        .frame(width: 64, height: 64).background(LanguLearn.purple, in: .circle)
                        .shadow(color: .black.opacity(0.14), radius: 8, y: 5)
                }.buttonStyle(.plain).offset(y: 92).accessibilityLabel("Spela upp uttrycket")
            }.padding(.bottom, 22)
            Text(revealed ? step.target : "Lyssna först. Vad tror du att Milo säger?")
                .font(.title2.bold()).multilineTextAlignment(.center)
            if revealed {
                Text(step.translation).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button("En gång till") { rate(false) }.buttonStyle(LanguLearnSecondaryButtonStyle())
                    Button("Jag förstod") { rate(true) }.buttonStyle(LanguLearnPrimaryButtonStyle())
                }
            } else {
                Button("Visa betydelsen") { withAnimation(LanguLearnMotion.move) { revealed = true } }
                    .buttonStyle(LanguLearnPrimaryButtonStyle())
            }
        }.padding(24).frame(maxHeight: .infinity)
    }
}

private struct QuickBuildRound: View {
    let step: JourneyStep
    @Binding var selected: [Int]
    let result: Bool?
    let check: () -> Void
    let next: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Bygg: \(step.translation)").font(.title2.bold())
                Text(selected.map { step.tokens[$0] }.joined(separator: " ").isEmpty
                     ? "Tryck på orden i rätt ordning"
                     : selected.map { step.tokens[$0] }.joined(separator: " "))
                    .font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                    .padding(20).background(.white, in: .rect(cornerRadius: 24))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                    ForEach(step.tokens.indices, id: \.self) { token in
                        Button(step.tokens[token]) {
                            if let position = selected.firstIndex(of: token) { selected.remove(at: position) }
                            else { selected.append(token) }
                        }
                        .buttonStyle(.bordered).controlSize(.large)
                        .disabled(result == true)
                    }
                }
                if let result {
                    Label(result ? "Precis så!" : "Nästan – prova en annan ordning.", systemImage: result ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                        .font(.headline).foregroundStyle(result ? LanguLearn.deepGreen : LanguLearn.magenta)
                }
                Button(result == true ? "Nästa fras" : "Kolla min fras", action: result == true ? next : check)
                    .buttonStyle(LanguLearnPrimaryButtonStyle()).disabled(selected.isEmpty)
            }.padding(24)
        }
    }
}

private struct QuickPlayFinish: View {
    let game: JourneyQuickGame
    let streak: Int
    let close: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            MiloAvatarView(mood: .joyful, size: 220, zoom: 2.6)
            Text("Snygg snabbrunda!").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(streak > 0 ? "Du fick ihop en svit på \(streak)." : "Du gav orden en ny chans att fastna.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Klar", action: close).buttonStyle(LanguLearnPrimaryButtonStyle())
        }.padding(28).frame(maxHeight: .infinity)
    }
}
