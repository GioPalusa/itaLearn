import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TutorSettings.self) private var settings
    @State private var store = LearningStore()
    @State private var access = OpenAIAccess()

    var body: some View {
        Group {
            if !access.isReady {
                MiloLoadingView(message: "Milo gör plats för dina studier…").padding(24)
            } else if !access.hasKey {
                OnboardingView()
            } else if !store.isLoaded {
                ContentUnavailableView {
                    Label("Kunde inte öppna dina studier", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(store.errorMessage ?? "Försök igen.")
                } actions: {
                    Button("Försök igen") { store.load(container: modelContext.container, language: settings.targetLanguage) }
                }
            } else if store.state.activePlan == nil {
                NavigationStack { AdaptiveChatView(mode: .assessment) }
            } else {
                MainTabs()
            }
        }
        .environment(store)
        .environment(access)
        .tint(LangLearn.purple)
        .task {
            store.load(container: modelContext.container, language: settings.targetLanguage)
            await access.load()
        }
        // Studies are saved per language, so a switch swaps in that language's plan.
        .onChange(of: settings.targetLanguage) { store.switchLanguage(to: settings.targetLanguage) }
    }
}


private struct MainTabs: View {
    enum Section: Hashable { case plan, conversation, progress }
    @State private var selection: Section = .plan

    var body: some View {
        TabView(selection: $selection) {
            Tab("Min studieplan", systemImage: "point.topleft.down.to.point.bottomright.curvepath", value: .plan) {
                NavigationStack { LearningPathView() }
            }
            Tab("Samtal", systemImage: "bubble.left.and.bubble.right", value: .conversation) {
                NavigationStack { CurrentLessonView() }
            }
            Tab("Mitt lärande", systemImage: "books.vertical", value: .progress) {
                NavigationStack { LearningProgressView() }
            }
        }
    }
}
