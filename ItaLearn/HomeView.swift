import SwiftData
import SwiftUI

/// Screen 2a — "Hem, dagens lektion skapas ur din historik".
struct HomeView: View {
    @Environment(TutorSettings.self) private var settings
    @Query(sort: \LessonRecord.completedAt, order: .reverse)
    private var records: [LessonRecord]

    @State private var isShowingSettings = false
    @State private var isShowingVocabulary = false

    private var completedLessonIDs: Set<String> {
        Set(records.map(\.lessonID))
    }

    private var todaysLesson: WritingLesson {
        LessonCatalog.all.first { !completedLessonIDs.contains($0.id) } ?? LessonCatalog.all[0]
    }

    private var currentIndex: Int {
        LessonCatalog.all.firstIndex { $0.id == todaysLesson.id } ?? 0
    }

    /// The most recent "next step" the teacher left, used as the hero rationale.
    private var carriedNextStep: String? {
        records.first?.nextSteps.first
    }

    private var levelProgress: Double {
        guard !LessonCatalog.all.isEmpty else { return 0 }
        return Double(completedLessonIDs.count) / Double(LessonCatalog.all.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    heroCard
                    NavigationLink(value: HomeDestination.allLessons) {
                        journeyCard
                    }
                    .buttonStyle(.plain)
                    vocabularySection
                    widgetCard
                }
                .frame(maxWidth: 720)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .italearnCanvas()
            .hideNavigationBar()
            .navigationDestination(for: WritingLesson.ID.self) { id in
                if let lesson = LessonCatalog.all.first(where: { $0.id == id }) {
                    LessonView(lesson: lesson)
                }
            }
            .navigationDestination(for: HomeDestination.self) { destination in
                switch destination {
                case .allLessons:
                    LessonCatalogView()
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $isShowingVocabulary) {
                VocabularySheet()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.il(12, .semibold))
                    .tracking(0.24)
                    .textCase(.uppercase)
                    .foregroundStyle(ItaLearn.inkTertiary)

                Text(greeting)
                    .font(.il(34, .bold))
                    .foregroundStyle(ItaLearn.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                isShowingSettings = true
            } label: {
                Text(settings.initials)
                    .font(.il(15, .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(ItaLearn.brandGradient, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Inställningar")
        }
        .padding(.horizontal, 2)
        .padding(.top, 8)
    }

    private var greeting: String {
        if let name = settings.greetingName {
            String(localized: "Buongiorno, \(name)")
        } else {
            String(localized: "Buongiorno")
        }
    }

    // MARK: - Today's lesson

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandBadge(title: "SKAPAD FÖR DIG · \(settings.level.rawValue)")

            Text(todaysLesson.title)
                .font(.il(26, .bold))
                .foregroundStyle(.white)
                .padding(.top, 12)

            Text(heroRationale)
                .font(.il(15))
                .foregroundStyle(.white.opacity(0.92))
                .frame(maxWidth: 280, alignment: .leading)
                .padding(.top, 6)

            chips
                .padding(.top, 14)

            HStack(spacing: 10) {
                NavigationLink(value: todaysLesson.id) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("Börja · \(todaysLesson.estimatedMinutes) min")
                    }
                    .font(.il(17, .semibold))
                    .foregroundStyle(ItaLearn.purple)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(ItaLearn.card, in: .capsule)
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 4)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ConversationView(lesson: todaysLesson)
                } label: {
                    Image(systemName: "mic")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.22), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Öva som samtal")
            }
            .padding(.top, 16)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ItaLearn.brandGradient, in: .rect(cornerRadius: ItaLearn.cardRadius))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 6)
    }

    private var heroRationale: String {
        if let carriedNextStep {
            String(localized: "Din lärare tar med sig ditt förra nästa steg: \(carriedNextStep)")
        } else {
            String(localized: "Din första lektion. Vi börjar lugnt och bygger vidare på den nästa gång.")
        }
    }

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(todaysLesson.promptChips, id: \.self) { chip in
                Text(chip)
                    .font(.il(12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.22), in: .capsule)
            }
        }
    }

    // MARK: - Route through the level

    @ViewBuilder
    private var journeyCard: some View {
        let done = completedLessonIDs.count
        let total = LessonCatalog.all.count

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Din rutt genom \(settings.level.rawValue)")
                    .font(.il(17, .semibold))
                    .foregroundStyle(ItaLearn.ink)
                Spacer()
                Text("\(done) / \(total)")
                    .font(.ilMono(13))
                    .foregroundStyle(ItaLearn.purple)
                    .monospacedDigit()
            }

            Text(remainingText(done: done, total: total))
                .font(.il(13))
                .foregroundStyle(ItaLearn.inkSecondary)
                .padding(.top, 3)

            JourneyRoute(currentIndex: currentIndex, totalStops: total)
                .padding(.top, 8)
        }
        .italearnCard()
    }

    private func remainingText(done: Int, total: Int) -> String {
        let remaining = max(total - done, 0)
        return remaining == 0
            ? String(localized: "Alla lektioner på den här nivån är klara.")
            : String(localized: "\(remaining) lektioner kvar på nivån.")
    }

    // MARK: - Ordkort

    private var vocabularySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ordkort")
                    .font(.il(20, .semibold))
                    .foregroundStyle(ItaLearn.ink)
                Spacer()
                Button("Alla") { isShowingVocabulary = true }
                    .font(.il(15))
                    .foregroundStyle(ItaLearn.purple)
            }
            .padding(.horizontal, 2)

            HStack(spacing: 10) {
                ForEach(Array(todaysLesson.vocabulary.prefix(2).enumerated()), id: \.element.id) { index, entry in
                    WordCard(entry: entry, paletteIndex: index)
                }

                Button {
                    isShowingVocabulary = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .medium))
                        Text("Alla\nordkort")
                            .font(.il(12, .semibold))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(ItaLearn.purple)
                    .frame(maxWidth: .infinity, minHeight: 128)
                    .padding(12)
                    .background(ItaLearn.card, in: .rect(cornerRadius: ItaLearn.cardRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: ItaLearn.cardRadius)
                            .strokeBorder(
                                Color.black.opacity(0.14),
                                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                            )
                    }
                }
                .buttonStyle(.plain)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    // MARK: - Widget promo

    private var widgetCard: some View {
        Button {
            isShowingSettings = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("I DAG")
                        .font(.il(8, .semibold))
                        .foregroundStyle(ItaLearn.inkTertiary)
                    Spacer(minLength: 0)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(todaysLesson.estimatedMinutes)")
                            .font(.ilMono(20))
                            .monospacedDigit()
                            .foregroundStyle(ItaLearn.purple)
                        Text("min")
                            .font(.il(9))
                            .foregroundStyle(ItaLearn.inkTertiary)
                    }
                    Capsule()
                        .fill(Color.black.opacity(0.10))
                        .frame(height: 4)
                        .overlay(alignment: .leading) {
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(ItaLearn.magenta)
                                    .frame(width: proxy.size.width * levelProgress)
                            }
                        }
                }
                .padding(8)
                .frame(width: 64, height: 64)
                .background(ItaLearn.canvas, in: .rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(ItaLearn.cardBorder, lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Öva från hemskärmen")
                        .font(.il(15, .semibold))
                        .foregroundStyle(ItaLearn.ink)
                    Text("Widgeten visar dagens mening. En notis kl. \(settings.reminderText) om du vill.")
                        .font(.il(13))
                        .foregroundStyle(ItaLearn.inkSecondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                RowChevron()
            }
            .italearnCard(padding: 14)
        }
        .buttonStyle(.plain)
    }
}

enum HomeDestination: Hashable {
    case allLessons
}

/// One vocabulary card with the design's soft radial "object" swatch.
private struct WordCard: View {
    let entry: VocabularyEntry
    let paletteIndex: Int

    private static let palette: [(Color, Color)] = [
        (Color(red: 0xF0 / 255, green: 0xD9 / 255, blue: 0xB5 / 255),
         Color(red: 0xC9 / 255, green: 0x8A / 255, blue: 0x3E / 255)),
        (Color(red: 0xB2 / 255, green: 0xDB / 255, blue: 0xAC / 255),
         Color(red: 0x66 / 255, green: 0xB6 / 255, blue: 0x59 / 255)),
        (Color(red: 0xC7 / 255, green: 0xD9 / 255, blue: 0xF2 / 255), ItaLearn.cyan),
        (Color(red: 0xE8 / 255, green: 0xC5 / 255, blue: 0xDD / 255), ItaLearn.magenta)
    ]

    var body: some View {
        let colors = Self.palette[paletteIndex % Self.palette.count]

        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    RadialGradient(
                        colors: [colors.0, colors.1],
                        center: UnitPoint(x: 0.3, y: 0.3),
                        startRadius: 2,
                        endRadius: 52
                    )
                )
                .frame(width: 56, height: 56)
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.12)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                        )
                }

            Text(entry.italian)
                .font(.il(14, .semibold))
                .foregroundStyle(ItaLearn.ink)
            Text(entry.swedish)
                .font(.il(11))
                .foregroundStyle(ItaLearn.inkTertiary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 128)
        .padding(12)
        .background(ItaLearn.card, in: .rect(cornerRadius: ItaLearn.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ItaLearn.cardRadius)
                .strokeBorder(ItaLearn.cardBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 4, y: 4)
        .accessibilityElement(children: .combine)
    }
}

/// Every lesson's word bank, reachable from "Alla".
private struct VocabularySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(LessonCatalog.all) { lesson in
                    Section("Lektion \(lesson.number) · \(String(localized: lesson.title))") {
                        ForEach(lesson.vocabulary) { entry in
                            HStack {
                                Text(entry.italian)
                                    .font(.il(17, .semibold))
                                Spacer()
                                Text(entry.swedish)
                                    .font(.il(15))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Ordkort")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klar") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    HomeView()
        .environment(TutorSettings(store: UserDefaults(suiteName: "preview") ?? .standard))
        .modelContainer(for: LessonRecord.self, inMemory: true)
}
