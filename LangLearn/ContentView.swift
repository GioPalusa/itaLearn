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
            } else if !access.hasKey || !settings.hasChosenLanguage {
                // The key lives in the Keychain and outlives the app, so it
                // cannot stand in for "has been introduced": a learner who
                // onboarded before the language step still owes us that answer.
                OnboardingView()
            } else if !store.isLoaded {
                ContentUnavailableView {
                    Label("Kunde inte öppna dina studier", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(store.errorMessage ?? "Försök igen.")
                } actions: {
                    Button("Försök igen") { loadStudies() }
                }
            } else if store.state.activePlan == nil {
                NavigationStack { AdaptiveChatView(mode: .assessment) }
                    .id(store.language?.code)
            } else {
                MainTabs()
                    .id(store.language?.code)
            }
        }
        .environment(store)
        .environment(access)
        .tint(LangLearn.purple)
        .task {
            loadStudies()
            await access.load()
        }
        // Studies are saved per language, so a switch swaps in that language's
        // plan; a language with none routes to a kunskapskoll, which builds one.
        .onChange(of: settings.chosenTarget) { loadStudies() }
    }

    /// Nothing is read from disk until the learner has named a language.
    private func loadStudies() {
        guard let language = settings.chosenTarget else { return }
        store.load(container: modelContext.container, language: language)
    }
}


private struct MainTabs: View {
    enum Section: Hashable { case plan, practice, progress }
    @State private var selection: Section = .plan

    var body: some View {
        TabView(selection: $selection) {
            Tab("Min studieplan", systemImage: "point.topleft.down.to.point.bottomright.curvepath", value: .plan) {
                NavigationStack { LearningPathView() }
            }
            Tab("Öva", systemImage: "gamecontroller", value: .practice) {
                NavigationStack { PracticeHubView() }
            }
            Tab("Mitt lärande", systemImage: "books.vertical", value: .progress) {
                NavigationStack { LearningProgressView() }
            }
        }
    }
}
