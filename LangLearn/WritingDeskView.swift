import SwiftUI

/// Write something, get it read back. The correction is shown as a diff against
/// what the learner actually wrote, so the change is the lesson.
struct WritingDeskView: View {
    @Environment(LearningStore.self) private var store
    @Environment(TutorSettings.self) private var settings
    @Environment(OpenAIAccess.self) private var access
    @State private var reviewer = LearningChat()
    @State private var draft = ""
    @State private var prompt = ""
    @FocusState private var editorFocused: Bool

    private var reviews: [WritingReview] { store.state.writings ?? [] }
    private var latest: WritingReview? { reviews.last }
    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Starting points for anyone who wants to write but not to choose a subject.
    private var starters: [String] {
        [
            "Berätta om din dag",
            "Beskriv någon du tycker om",
            "Skriv ett kort meddelande till en vän",
            "Berätta vad du gjorde i helgen"
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                editorCard
                if reviewer.isWorking {
                    MiloLoadingView(message: "Milo läser din text…")
                }
                if let error = reviewer.errorMessage ?? store.errorMessage {
                    Text(error).foregroundStyle(LangLearn.red).font(.callout)
                }
                if let latest, !reviewer.isWorking {
                    feedbackCard(latest)
                }
                if reviews.count > 1 {
                    NavigationLink {
                        WritingHistoryView()
                    } label: {
                        Label("Tidigare texter (\(reviews.count))", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(LangLearnSecondaryButtonStyle())
                }
            }
            .padding(20).padding(.bottom, 40)
            .frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .langlearnCanvas()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Skriv och få respons")
        .inlineNavigationTitle()
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Skriv på \(settings.targetLanguage.displayName.lowercased())")
                .font(.il(17, .semibold)).foregroundStyle(LangLearn.ink)
            if prompt.isEmpty && trimmed.isEmpty {
                Text("Välj en start, eller skriv om vad du vill.")
                    .font(.il(14)).foregroundStyle(LangLearn.inkSecondary)
                WordFlowLayout(spacing: 8) {
                    ForEach(starters, id: \.self) { starter in
                        Button {
                            prompt = starter
                            editorFocused = true
                        } label: {
                            Text(starter)
                                .font(.il(14))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(LangLearn.purple.opacity(0.10), in: .capsule)
                                .foregroundStyle(LangLearn.purple)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if !prompt.isEmpty {
                HStack(spacing: 8) {
                    Text(prompt).font(.il(14, .semibold)).foregroundStyle(LangLearn.purple)
                    Spacer(minLength: 0)
                    Button("Byt", systemImage: "xmark.circle.fill") { prompt = "" }
                        .labelStyle(.iconOnly).foregroundStyle(LangLearn.inkQuaternary)
                }
            }

            TextEditor(text: $draft)
                .focused($editorFocused)
                .font(.il(17))
                .frame(minHeight: 180)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(LangLearn.field, in: .rect(cornerRadius: 14))
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Skriv några meningar…")
                            .font(.il(17)).foregroundStyle(LangLearn.inkQuaternary)
                            .padding(.horizontal, 15).padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

            HStack {
                Text("\(trimmed.count) tecken")
                    .font(.il(12)).foregroundStyle(LangLearn.inkQuaternary)
                Spacer()
            }

            Button("Be Milo läsa", systemImage: "text.magnifyingglass") {
                editorFocused = false
                reviewer.reviewWriting(store: store, settings: settings, prompt: prompt, text: draft)
            }
            .buttonStyle(LangLearnPrimaryButtonStyle())
            .disabled(trimmed.isEmpty || trimmed.count > 4000 || reviewer.isWorking || !access.hasKey)

            Text(access.hasKey
                 ? "Milo rättar bara det som faktiskt är fel och behåller din röst."
                 : "Lägg till din OpenAI API-nyckel i Inställningar för att få respons.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .langlearnCard()
    }

    private func feedbackCard(_ review: WritingReview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Milos respons").font(.il(17, .semibold)).foregroundStyle(LangLearn.ink)
                Spacer()
                Text("\(review.feedback.score)/5")
                    .font(.ilMono(13)).monospacedDigit()
                    .foregroundStyle(LangLearn.deepGreen)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(LangLearn.green.opacity(0.14), in: .capsule)
            }
            WritingReviewBody(review: review)
        }
        .langlearnCard()
    }
}

/// Shared by the desk and the history list.
struct WritingReviewBody: View {
    let review: WritingReview
    @Environment(TutorSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Rättat i din text") {
                Text(CorrectionDiff.attributedText(original: review.text,
                                                   corrected: review.feedback.corrected))
                    .font(.il(17)).lineSpacing(8).textSelection(.enabled)
                    .accessibilityLabel("Rättad text: \(review.feedback.corrected)")
            }
            if !review.feedback.ruleTitle.isEmpty {
                section(LocalizedStringKey(review.feedback.ruleTitle)) {
                    Text(review.feedback.ruleExplanation)
                        .font(.il(15)).foregroundStyle(LangLearn.inkSecondary)
                }
            }
            section("Sammanfattning") {
                Text(review.feedback.summary)
                    .font(.il(15)).foregroundStyle(LangLearn.inkSecondary)
            }
            if !review.feedback.strengths.isEmpty {
                section("Det här fungerar redan") {
                    FeedbackList(items: review.feedback.strengths, color: LangLearn.green)
                }
            }
            section("Prova nästa gång") {
                FeedbackList(items: review.feedback.nextSteps, color: LangLearn.magenta)
            }
        }
    }

    private func section(_ title: LocalizedStringKey,
                         @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.il(15, .semibold)).foregroundStyle(LangLearn.ink)
            content()
        }
    }
}

/// Every text the learner has had reviewed in this language.
struct WritingHistoryView: View {
    @Environment(LearningStore.self) private var store
    private var reviews: [WritingReview] { (store.state.writings ?? []).reversed() }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(reviews) { review in
                    NavigationLink {
                        ScrollView {
                            WritingReviewBody(review: review)
                                .padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
                        }
                        .langlearnCanvas()
                        .navigationTitle(review.createdAt.formatted(.dateTime.day().month().year()))
                        .inlineNavigationTitle()
                    } label: {
                        row(review)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .langlearnCanvas()
        .navigationTitle("Mina texter")
        .inlineNavigationTitle()
    }

    private func row(_ review: WritingReview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(review.prompt.isEmpty ? "Egen text" : review.prompt)
                    .font(.il(17, .semibold)).foregroundStyle(LangLearn.ink)
                Spacer()
                Text("\(review.feedback.score)/5")
                    .font(.ilMono(13)).monospacedDigit()
                    .foregroundStyle(LangLearn.deepGreen)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(LangLearn.green.opacity(0.14), in: .capsule)
            }
            Text(review.text)
                .font(.il(15)).foregroundStyle(LangLearn.inkSecondary)
                .lineLimit(2).multilineTextAlignment(.leading)
            Text(review.createdAt, format: .dateTime.day().month(.wide).year())
                .font(.il(12)).foregroundStyle(LangLearn.inkQuaternary)
        }
        .langlearnCard()
        .accessibilityElement(children: .combine)
    }
}
