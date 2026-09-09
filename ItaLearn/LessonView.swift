import SwiftData
import SwiftUI

/// Screen 2b — "Lektion + Writing Tools-rättning".
struct LessonView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TutorSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LessonRecord.completedAt, order: .reverse)
    private var records: [LessonRecord]

    let lesson: WritingLesson

    @StateObject private var tutor = ItalianTutor()
    @State private var attempt = ""
    @State private var submittedAttempt = ""
    @State private var feedback: LessonFeedback?
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var reviewTask: Task<Void, Never>?
    @State private var isShowingPaywall = false
    @FocusState private var isEditorFocused: Bool

    private let narrator = SpeechNarrator()

    private var learningMemories: [LearningMemory] {
        records
            .filter { $0.lessonNumber < lesson.number }
            .prefix(3)
            .map { LearningMemory(record: $0) }
    }

    private var latestFocusAreas: [String] {
        Array(learningMemories.first?.nextSteps.prefix(2) ?? [])
    }

    private var wordCount: Int {
        attempt.split(whereSeparator: \.isWhitespace).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                briefCard
                writingCard

                if isSubmitting {
                    ThinkingCard()
                }

                if let errorMessage {
                    ErrorCard(message: errorMessage)
                }

                if let feedback {
                    correctionCard(feedback)
                    summaryCard(feedback)
                }
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
            .animation(.spring(duration: 0.45), value: feedback == nil)
        }
#if os(iOS)
        .scrollDismissesKeyboard(.interactively)
#endif
        .italearnCanvas()
        .hideNavigationBar()
        .toolbar {
#if os(iOS)
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Klar") { isEditorFocused = false }
            }
#endif
        }
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView(tutor: tutor)
        }
        .task {
            tutor.apply(tone: settings.tone, level: settings.level)
            tutor.prewarm()
        }
        .onChange(of: settings.tone) { tutor.apply(tone: settings.tone, level: settings.level) }
        .onChange(of: settings.level) { tutor.apply(tone: settings.tone, level: settings.level) }
        .onDisappear {
            reviewTask?.cancel()
            reviewTask = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                GlassCircle {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ItaLearn.inkSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tillbaka")

            VStack(alignment: .leading, spacing: 1) {
                Text("LEKTION \(lesson.number) · \(settings.level.rawValue)")
                    .font(.il(11, .semibold))
                    .tracking(0.33)
                    .foregroundStyle(ItaLearn.purple)
                Text(lesson.title)
                    .font(.il(20, .semibold))
                    .foregroundStyle(ItaLearn.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 4)
    }

    // MARK: - Brief

    private var briefCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(lesson.prompt)
                .font(.il(17))
                .foregroundStyle(ItaLearn.ink)
                .lineSpacing(4)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 15))
                    .foregroundStyle(ItaLearn.inkTertiary)
                    .padding(.top, 2)
                Text(lesson.goal)
                    .font(.il(15))
                    .foregroundStyle(ItaLearn.inkSecondary)
            }

            if !latestFocusAreas.isEmpty {
                Rectangle()
                    .fill(ItaLearn.hairline)
                    .frame(height: 1)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 15))
                        .foregroundStyle(ItaLearn.cyan)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Din lärare håller extra utkik efter det här — det var dina nästa steg förra gången.")
                            .font(.il(14))
                            .foregroundStyle(ItaLearn.inkSecondary)
                        FeedbackList(items: latestFocusAreas, color: ItaLearn.cyan)
                    }
                }
            }
        }
        .italearnCard()
    }

    // MARK: - Writing

    private var writingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Skriv på italienska")
                    .font(.il(17, .semibold))
                    .foregroundStyle(ItaLearn.ink)
                Spacer()
                Text("\(wordCount) ord")
                    .font(.ilMono(12, .regular))
                    .monospacedDigit()
                    .foregroundStyle(ItaLearn.inkQuaternary)
            }

            TextEditor(text: $attempt)
                .focused($isEditorFocused)
                .font(.il(17))
                .foregroundStyle(ItaLearn.ink)
                .frame(minHeight: 150)
                .padding(12)
                .scrollContentBackground(.hidden)
                .background(ItaLearn.field, in: .rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                }
                .overlay(alignment: .topLeading) {
                    if attempt.isEmpty {
                        Text(lesson.scaffold)
                            .font(.il(17))
                            .foregroundStyle(ItaLearn.inkQuaternary)
                            .padding(.horizontal, 17)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }
                .writingToolsBehavior(.limited)
                .accessibilityLabel("Ditt svar på italienska")

            Button {
                isEditorFocused = false
                if tutor.isLimitReached {
                    isShowingPaywall = true
                } else {
                    reviewTask = Task { await checkWriting() }
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "sparkles")
                    Text(ctaLabel)
                }
            }
            .buttonStyle(
                ItaLearnPrimaryButtonStyle(
                    background: AnyShapeStyle(ItaLearn.purple),
                    isEnabled: canSubmit || tutor.isLimitReached
                )
            )
            .disabled(!canSubmit && !tutor.isLimitReached)

            modelStatus
        }
        .italearnCard()
    }

    private var ctaLabel: LocalizedStringKey {
        if isSubmitting { "Granskar …" }
        else if tutor.isLimitReached { "Dagens gräns är nådd" }
        else if feedback != nil { "Kontrollera igen" }
        else { "Kontrollera" }
    }

    @ViewBuilder
    private var modelStatus: some View {
        statusLine(
            tutor.isAvailable ? "Texten skickas till OpenAI. Återkopplingen sparas lokalt." : "Lägg till din OpenAI API-nyckel i Inställningar.",
            systemImage: "network", tint: ItaLearn.inkTertiary
        )
    }

    private func statusLine(
        _ text: LocalizedStringKey,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .foregroundStyle(tint)
            Text(text)
                .font(.il(12))
                .foregroundStyle(ItaLearn.inkSecondary)
        }
    }

    private var canSubmit: Bool {
        !attempt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSubmitting
            && tutor.isAvailable
            && !tutor.isLimitReached
    }

    // MARK: - Correction

    private func correctionCard(_ feedback: LessonFeedback) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label {
                    Text("Rättat i din text")
                        .font(.il(20, .semibold))
                } icon: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundStyle(ItaLearn.deepGreen)

                Spacer()

                Text("\(feedback.progressScore)/5")
                    .font(.ilMono(13))
                    .monospacedDigit()
                    .foregroundStyle(ItaLearn.deepGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ItaLearn.green.opacity(0.14), in: .capsule)
                    .accessibilityLabel("Framstegspoäng \(feedback.progressScore) av 5")
            }

            Text(
                CorrectionDiff.attributedText(
                    original: submittedAttempt,
                    corrected: feedback.correctedItalian
                )
            )
            .font(.il(17))
            .lineSpacing(8)
            .textSelection(.enabled)
            .accessibilityLabel("Rättad text: \(feedback.correctedItalian)")

            if !feedback.ruleTitle.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 15))
                        .foregroundStyle(ItaLearn.purple)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(feedback.ruleTitle)
                            .font(.il(14, .semibold))
                            .foregroundStyle(ItaLearn.ink)
                        Text(feedback.ruleExplanation)
                            .font(.il(14))
                            .foregroundStyle(ItaLearn.inkSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(ItaLearn.field, in: .rect(cornerRadius: 12))
            }

            HStack(spacing: 8) {
                Button("Ersätt min text") {
                    attempt = feedback.correctedItalian
                }
                .buttonStyle(ItaLearnSecondaryButtonStyle())

                Button("Läs upp") {
                    narrator.speak(feedback.correctedItalian)
                }
                .buttonStyle(
                    ItaLearnSecondaryButtonStyle(
                        tint: Color.black.opacity(0.7),
                        fill: Color.black.opacity(0.05)
                    )
                )
            }
        }
        .italearnCard()
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func summaryCard(_ feedback: LessonFeedback) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(feedback.lessonSummary)
                .font(.il(17))
                .foregroundStyle(ItaLearn.ink)
                .lineSpacing(4)

            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Det här fungerar redan")
                        .font(.il(15, .semibold))
                        .foregroundStyle(ItaLearn.ink)
                } icon: {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(ItaLearn.green)
                }
                FeedbackList(items: feedback.strengths, color: ItaLearn.green)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Prova nästa gång")
                        .font(.il(15, .semibold))
                        .foregroundStyle(ItaLearn.ink)
                } icon: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ItaLearn.magenta)
                }
                FeedbackList(items: feedback.nextSteps, color: ItaLearn.magenta)
            }

            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(ItaLearn.inkTertiary)
                Text("Sparad i Mitt lärande · nästa lektion bygger vidare")
                    .font(.il(12))
                    .foregroundStyle(ItaLearn.inkSecondary)
            }
        }
        .italearnCard()
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Actions

    private func checkWriting() async {
        let trimmed = attempt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSubmitting = true
        errorMessage = nil
        feedback = nil
        defer {
            isSubmitting = false
            reviewTask = nil
        }

        do {
            let newFeedback = try await tutor.review(
                attempt: trimmed,
                lesson: lesson,
                memories: learningMemories,
                correctsSpelling: settings.correctsSpelling
            )
            try Task.checkCancellation()

            let record = LessonRecord(
                lessonID: lesson.id,
                lessonNumber: lesson.number,
                lessonTitle: String(localized: lesson.title),
                prompt: String(localized: lesson.prompt),
                attempt: trimmed,
                correctedItalian: newFeedback.correctedItalian,
                summary: newFeedback.lessonSummary,
                strengths: newFeedback.strengths,
                nextSteps: newFeedback.nextSteps,
                score: newFeedback.progressScore,
                ruleTitle: newFeedback.ruleTitle,
                ruleExplanation: newFeedback.ruleExplanation
            )

            modelContext.insert(record)
            try modelContext.save()
            submittedAttempt = trimmed
            feedback = newFeedback
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            if tutor.isLimitReached {
                isShowingPaywall = true
            } else {
                errorMessage = tutor.userMessage(for: error)
            }
        }
    }
}

/// "Din lärare läser …" — pulsing avatar over shimmering placeholder lines.
private struct ThinkingCard: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(ItaLearn.brandGradient)
                        .frame(width: 34, height: 34)
                        .scaleEffect(isAnimating ? 1.14 : 1)
                        .opacity(isAnimating ? 0.18 : 0.55)
                    Circle()
                        .fill(ItaLearn.brandGradient)
                        .frame(width: 20, height: 20)
                }
                .animation(
                    .easeInOut(duration: 0.75).repeatForever(autoreverses: true),
                    value: isAnimating
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text("Din lärare läser …")
                        .font(.il(17, .semibold))
                        .foregroundStyle(ItaLearn.ink)
                    Text("Jämför med dina tre senaste lektioner.")
                        .font(.il(13))
                        .foregroundStyle(ItaLearn.inkSecondary)
                }
            }

            VStack(spacing: 8) {
                shimmerBar(tint: ItaLearn.magenta, widthFactor: 1, delay: 0)
                shimmerBar(tint: ItaLearn.cyan, widthFactor: 0.78, delay: 0.2)
                shimmerBar(tint: ItaLearn.purple, widthFactor: 0.54, delay: 0.4)
            }
        }
        .italearnCard()
        .accessibilityElement(children: .combine)
        .onAppear { isAnimating = true }
    }

    private func shimmerBar(tint: Color, widthFactor: CGFloat, delay: Double) -> some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.black.opacity(0.05))
                .overlay {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.clear, tint.opacity(0.18), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * 0.5)
                        .offset(x: isAnimating ? proxy.size.width : -proxy.size.width * 0.5)
                        .animation(
                            .linear(duration: 1.1).repeatForever(autoreverses: false).delay(delay),
                            value: isAnimating
                        )
                }
                .clipShape(.capsule)
                .frame(width: proxy.size.width * widthFactor, alignment: .leading)
        }
        .frame(height: 12)
    }
}

private struct ErrorCard: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ItaLearn.red)
            Text(message)
                .font(.il(15))
                .foregroundStyle(ItaLearn.ink)
        }
        .italearnCard()
    }
}
