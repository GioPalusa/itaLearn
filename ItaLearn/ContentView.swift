import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(TutorSettings.self) private var settings
    @State private var selection: TabSection = .practice
    @State private var isShowingOnboarding = false

    enum TabSection: Hashable {
        case practice
        case conversation
        case learning
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Öva", systemImage: "pencil.and.scribble", value: .practice) {
                HomeView()
            }

            Tab("Samtal", systemImage: "mic", value: .conversation) {
                ConversationTab()
            }

            Tab("Mitt lärande", systemImage: "books.vertical", value: .learning) {
                NavigationStack {
                    LessonHistoryView()
                }
            }
        }
        .tint(ItaLearn.purple)
        .onAppear { isShowingOnboarding = !settings.hasOnboarded }
        .onboardingCover(isPresented: $isShowingOnboarding) {
            OnboardingView()
        }
    }
}

/// The Samtal tab practises whichever lesson comes next.
private struct ConversationTab: View {
    @Query(sort: \LessonRecord.completedAt, order: .reverse)
    private var records: [LessonRecord]

    private var lesson: WritingLesson {
        let completed = Set(records.map(\.lessonID))
        return LessonCatalog.all.first { !completed.contains($0.id) } ?? LessonCatalog.all[0]
    }

    var body: some View {
        NavigationStack {
            ConversationView(lesson: lesson)
        }
    }
}

#Preview {
    ContentView()
        .environment(TutorSettings(store: UserDefaults(suiteName: "preview") ?? .standard))
        .modelContainer(for: LessonRecord.self, inMemory: true)
}
