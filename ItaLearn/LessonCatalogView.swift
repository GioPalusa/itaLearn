import SwiftData
import SwiftUI

struct LessonCatalogView: View {
    @Query(sort: \LessonRecord.completedAt, order: .reverse)
    private var records: [LessonRecord]

    private var completedLessonIDs: Set<String> {
        Set(records.map(\.lessonID))
    }

    private var nextLessonNumber: Int {
        LessonCatalog.all.first(where: { !completedLessonIDs.contains($0.id) })?.number
            ?? LessonCatalog.all.count
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                catalogHeader

                ForEach(LessonCatalog.all) { lesson in
                    NavigationLink {
                        LessonView(lesson: lesson)
                    } label: {
                        LessonRow(
                            lesson: lesson,
                            isCompleted: completedLessonIDs.contains(lesson.id),
                            isRecommended: lesson.number == nextLessonNumber
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 720)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(Color.orange.opacity(0.06))
        .navigationTitle("ItaLearn")
    }

    private var catalogHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Skriv italienska, lite i taget")
                .font(.largeTitle.bold())
            Text("Korta övningar för dig som precis har börjat. Din tidigare återkoppling följer med så att varje lektion kan bygga vidare på den förra.")
                .font(.title3)
                .foregroundStyle(.secondary)

            ProgressView(
                value: Double(completedLessonIDs.count),
                total: Double(LessonCatalog.all.count)
            )
            .tint(.orange)
            .accessibilityLabel("Avklarade lektioner")
            .accessibilityValue("\(completedLessonIDs.count) av \(LessonCatalog.all.count)")

            Text("\(completedLessonIDs.count) av \(LessonCatalog.all.count) lektioner klara")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .italearnCard()
    }
}

private struct LessonRow: View {
    let lesson: WritingLesson
    let isCompleted: Bool
    let isRecommended: Bool

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(isCompleted ? Color.green.opacity(0.14) : Color.orange.opacity(0.14))
                    .frame(width: 52, height: 52)
                Image(systemName: isCompleted ? "checkmark" : lesson.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isCompleted ? .green : .orange)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Lektion \(lesson.number)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if isRecommended {
                        Text("NÄSTA")
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                    }
                }
                Text(lesson.title)
                    .font(.headline)
                Text(lesson.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.forward")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .italearnCard()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Öppnar skrivövningen")
    }
}
