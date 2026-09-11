import SwiftData
import SwiftUI

struct LessonHistoryView: View {
    @Query(sort: \LessonRecord.completedAt, order: .reverse)
    private var lessons: [LessonRecord]

    var body: some View {
        Group {
            if lessons.isEmpty {
                ContentUnavailableView(
                    "Inga lektioner än",
                    systemImage: "books.vertical",
                    description: Text("Gör din första skrivövning så visas sammanfattningen här.")
                )
                .langulearnCanvas()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(lessons) { lesson in
                            NavigationLink {
                                LessonRecordDetail(record: lesson)
                            } label: {
                                LessonRecordRow(record: lesson)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: 720)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
                .langulearnCanvas()
            }
        }
        .navigationTitle("Mitt lärande")
    }
}

private struct LessonRecordRow: View {
    let record: LessonRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(record.lessonTitle)
                    .font(.il(17, .semibold))
                    .foregroundStyle(LanguLearn.ink)
                Spacer()
                Text("\(record.score)/5")
                    .font(.ilMono(13))
                    .monospacedDigit()
                    .foregroundStyle(LanguLearn.deepGreen)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(LanguLearn.green.opacity(0.14), in: .capsule)
            }

            Text(record.summary)
                .font(.il(15))
                .foregroundStyle(LanguLearn.inkSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(record.completedAt, format: .dateTime.day().month(.wide).year())
                .font(.il(12))
                .foregroundStyle(LanguLearn.inkQuaternary)
        }
        .langulearnCard()
        .accessibilityElement(children: .combine)
    }
}

private struct LessonRecordDetail: View {
    let record: LessonRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("Rättat i din text") {
                    Text(
                        CorrectionDiff.attributedText(
                            original: record.attempt,
                            corrected: record.correctedItalian
                        )
                    )
                    .font(.il(17))
                    .lineSpacing(8)
                    .textSelection(.enabled)
                    .accessibilityLabel("Rättad text: \(record.correctedItalian)")
                }

                if !record.ruleTitle.isEmpty {
                    section(LocalizedStringKey(record.ruleTitle)) {
                        Text(record.ruleExplanation)
                            .font(.il(15))
                            .foregroundStyle(LanguLearn.inkSecondary)
                    }
                }

                section("Lektionssammanfattning") {
                    Text(record.summary)
                        .font(.il(15))
                        .foregroundStyle(LanguLearn.inkSecondary)
                }

                section("Det här fungerar redan") {
                    FeedbackList(items: record.strengths, color: LanguLearn.green)
                }

                section("Prova nästa gång") {
                    FeedbackList(items: record.nextSteps, color: LanguLearn.magenta)
                }
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .langulearnCanvas()
        .navigationTitle(record.lessonTitle)
    }

    private func section(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.il(15, .semibold))
                .foregroundStyle(LanguLearn.ink)
            content()
        }
        .langulearnCard()
    }
}
