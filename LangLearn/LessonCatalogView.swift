import SwiftData
import SwiftUI

/// The full route through the level, reached from the journey card on 2a.
struct LessonCatalogView: View {
    @Environment(TutorSettings.self) private var settings
    @Query(sort: \LessonRecord.completedAt, order: .reverse)
    private var records: [LessonRecord]

    private var completedLessonIDs: Set<String> {
        Set(records.map(\.lessonID))
    }

    private var nextLessonNumber: Int {
        LessonCatalog.all.first { !completedLessonIDs.contains($0.id) }?.number
            ?? LessonCatalog.all.count
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                header

                ForEach(LessonCatalog.all) { lesson in
                    NavigationLink(value: lesson.id) {
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
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .langlearnCanvas()
        .navigationTitle("Din rutt genom \(settings.level.rawValue)")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Skriv italienska, lite i taget")
                .font(.il(28, .bold))
                .foregroundStyle(LangLearn.ink)

            Text("Korta övningar för dig som precis har börjat. Din tidigare återkoppling följer med så att varje lektion kan bygga vidare på den förra.")
                .font(.il(17))
                .foregroundStyle(LangLearn.inkSecondary)
                .lineSpacing(3)

            ProgressView(
                value: Double(completedLessonIDs.count),
                total: Double(LessonCatalog.all.count)
            )
            .tint(LangLearn.purple)
            .accessibilityLabel("Avklarade lektioner")
            .accessibilityValue("\(completedLessonIDs.count) av \(LessonCatalog.all.count)")

            Text("\(completedLessonIDs.count) av \(LessonCatalog.all.count) lektioner klara")
                .font(.il(12))
                .foregroundStyle(LangLearn.inkTertiary)
        }
        .langlearnCard()
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
                    .fill((isCompleted ? LangLearn.green : LangLearn.purple).opacity(0.14))
                    .frame(width: 52, height: 52)
                Image(systemName: isCompleted ? "checkmark" : lesson.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isCompleted ? LangLearn.green : LangLearn.purple)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("Lektion \(lesson.number)")
                        .font(.il(12, .semibold))
                        .foregroundStyle(LangLearn.inkTertiary)
                    if isRecommended {
                        Text("NÄSTA")
                            .font(.il(11, .bold))
                            .tracking(0.33)
                            .foregroundStyle(LangLearn.magenta)
                    }
                }
                Text(lesson.title)
                    .font(.il(17, .semibold))
                    .foregroundStyle(LangLearn.ink)
                Text(lesson.subtitle)
                    .font(.il(15))
                    .foregroundStyle(LangLearn.inkSecondary)
            }

            Spacer(minLength: 0)

            RowChevron()
        }
        .langlearnCard()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Öppnar skrivövningen")
    }
}
