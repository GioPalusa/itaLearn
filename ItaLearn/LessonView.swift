import FoundationModels
import SwiftData
import SwiftUI

struct LessonView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LessonRecord.completedAt, order: .reverse)
    private var records: [LessonRecord]

    let lesson: WritingLesson

    @StateObject private var tutor = ItalianTutor()
    @State private var attempt = ""
    @State private var feedback: LessonFeedback?
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var reviewTask: Task<Void, Never>?
    @FocusState private var isEditorFocused: Bool

    private var learningMemories: [LearningMemory] {
        records
            .filter { $0.lessonNumber < lesson.number }
            .prefix(3)
            .map { LearningMemory(record: $0) }
    }

    private var latestFocusAreas: [String] {
        Array(learningMemories.first?.nextSteps.prefix(2) ?? [])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LessonHeader(lesson: lesson)

                if !latestFocusAreas.isEmpty {
                    PreviousFeedbackCard(focusAreas: latestFocusAreas)
                }

                writingCard

                if isSubmitting {
                    thinkingCard
                }

                if let errorMessage {
                    ErrorCard(message: errorMessage)
                }

                if let feedback {
                    FeedbackCard(feedback: feedback)
                }
            }
            .frame(maxWidth: 720)
            .padding()
            .frame(maxWidth: .infinity)
        }
#if os(iOS)
        .scrollDismissesKeyboard(.interactively)
#endif
        .background(Color.orange.opacity(0.06))
        .navigationTitle(lesson.title)
        .toolbar {
#if os(iOS)
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Klar") {
                    isEditorFocused = false
                }
            }
#endif
        }
        .task {
            tutor.prewarm()
        }
        .onDisappear {
            reviewTask?.cancel()
            reviewTask = nil
        }
    }

    private var writingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Skriv på italienska", systemImage: "text.cursor")
                .font(.headline)

            TextEditor(text: $attempt)
                .focused($isEditorFocused)
                .frame(minHeight: 170)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(.background.secondary)
                .clipShape(.rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.quaternary, lineWidth: 1)
                }
                .writingToolsBehavior(.limited)
                .accessibilityLabel("Ditt svar på italienska")
                .overlay(alignment: .topLeading) {
                    if attempt.isEmpty {
                        Text(lesson.scaffold)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

            Button {
                isEditorFocused = false
                reviewTask = Task { await checkWriting() }
            } label: {
                Label("Kontrollera min text", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSubmit)

            modelStatus
        }
        .italearnCard()
    }

    private var thinkingCard: some View {
        HStack {
            ProgressView()
            VStack(alignment: .leading) {
                Text("Din lärare läser …")
                    .font(.headline)
                Text("Private Cloud Compute förbereder återkoppling på engelska.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .italearnCard()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var modelStatus: some View {
        switch tutor.availability {
        case .available:
            if tutor.isLimitReached {
                quotaMessage("Dagens gräns för Private Cloud Compute är nådd.", color: .red)
            } else if tutor.isApproachingLimit {
                quotaMessage("Du närmar dig dagens gräns för Private Cloud Compute.", color: .orange)
            } else {
                Label("Återkopplingen är privat och sparas inte av Apple.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .unavailable(let reason):
            Label(reason.userMessage, systemImage: "sparkles.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var canSubmit: Bool {
        !attempt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSubmitting
            && tutor.isAvailable
            && !tutor.isLimitReached
    }

    @ViewBuilder
    private func quotaMessage(_ text: LocalizedStringKey, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(text, systemImage: "gauge.with.dots.needle.67percent")
                .font(.caption)
                .foregroundStyle(color)

            if tutor.canShowLimitOptions {
                Button("Visa alternativ för gränsen") {
                    tutor.showLimitOptions()
                }
                .font(.caption)
            }
        }
    }

    private func checkWriting() async {
        let submittedAttempt = attempt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submittedAttempt.isEmpty else { return }

        isSubmitting = true
        errorMessage = nil
        feedback = nil
        defer {
            isSubmitting = false
            reviewTask = nil
        }

        do {
            let newFeedback = try await tutor.review(
                attempt: submittedAttempt,
                lesson: lesson,
                memories: learningMemories
            )
            try Task.checkCancellation()

            let record = LessonRecord(
                lessonID: lesson.id,
                lessonNumber: lesson.number,
                lessonTitle: String(localized: lesson.title),
                prompt: String(localized: lesson.prompt),
                attempt: submittedAttempt,
                correctedItalian: newFeedback.correctedItalian,
                summary: newFeedback.lessonSummary,
                strengths: newFeedback.strengths,
                nextSteps: newFeedback.nextSteps,
                score: newFeedback.progressScore
            )

            modelContext.insert(record)
            try modelContext.save()
            feedback = newFeedback
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = tutor.userMessage(for: error)
        }
    }
}

private struct LessonHeader: View {
    let lesson: WritingLesson

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LEKTION \(lesson.number) · A1")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                    Text(lesson.title)
                        .font(.largeTitle.bold())
                }

                Spacer()

                Image(systemName: lesson.systemImage)
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            }

            Text(lesson.prompt)
                .font(.title3)

            Label(lesson.goal, systemImage: "target")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Text("Ord du kan låna")
                    .font(.subheadline.weight(.semibold))
                LessonWordBank(words: lesson.wordBank)
            }
        }
        .italearnCard()
    }
}

private struct LessonWordBank: View {
    let words: [LocalizedStringResource]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                    wordChip(word)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                    wordChip(word)
                }
            }
        }
    }

    private func wordChip(_ word: LocalizedStringResource) -> some View {
        Text(word)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.orange.opacity(0.1), in: .capsule)
    }
}

private struct PreviousFeedbackCard: View {
    let focusAreas: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Vi bygger vidare", systemImage: "arrow.triangle.branch")
                .font(.headline)
            Text("Din lärare tar med sig tidigare återkoppling och håller extra utkik efter:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            FeedbackList(items: focusAreas, color: .blue)
        }
        .italearnCard()
    }
}

private struct FeedbackCard: View {
    let feedback: LessonFeedback

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Lärarens återkoppling", systemImage: "checkmark.seal.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.green)

                Spacer()

                Text("\(feedback.progressScore)/5")
                    .font(.headline.monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.green.opacity(0.12), in: .capsule)
                    .accessibilityLabel("Framstegspoäng \(feedback.progressScore) av 5")
            }

            FeedbackSection(title: "En naturlig rättning", systemImage: "quote.bubble") {
                Text(feedback.correctedItalian)
                    .font(.title3)
                    .textSelection(.enabled)
            }

            FeedbackSection(title: "Det här lärde du dig", systemImage: "lightbulb") {
                Text(feedback.lessonSummary)
            }

            FeedbackSection(title: "Det här fungerar redan", systemImage: "heart") {
                FeedbackList(items: feedback.strengths, color: .green)
            }

            FeedbackSection(title: "Prova nästa gång", systemImage: "arrow.up.right") {
                FeedbackList(items: feedback.nextSteps, color: .orange)
            }

            Label("Sparad i Mitt lärande", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .italearnCard()
    }
}

private struct ErrorCard: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .italearnCard()
    }
}
