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
            } else {
                List(lessons) { lesson in
                    NavigationLink {
                        LessonRecordDetail(record: lesson)
                    } label: {
                        LessonRecordRow(record: lesson)
                    }
                }
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
                    .font(.headline)
                Spacer()
                Text("\(record.score)/5")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.orange)
            }
            Text(record.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(record.completedAt, format: .dateTime.day().month(.wide).year())
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct LessonRecordDetail: View {
    let record: LessonRecord

    var body: some View {
        List {
            Section("Ditt svar") {
                Text(record.attempt)
            }

            Section("Naturlig rättning") {
                Text(record.correctedItalian)
            }

            Section("Lektionssammanfattning") {
                Text(record.summary)
            }

            Section("Styrkor") {
                ForEach(record.strengths, id: \.self) { Text($0) }
            }

            Section("Nästa steg") {
                ForEach(record.nextSteps, id: \.self) { Text($0) }
            }
        }
        .navigationTitle(record.lessonTitle)
    }
}
