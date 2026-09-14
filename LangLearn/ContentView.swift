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
            } else if !settings.hasChosenLanguage {
                // Language selection precedes the journey; a local first lesson needs no API key.
                OnboardingView()
            } else if !store.isLoaded || store.language != settings.chosenTarget {
                ContentUnavailableView {
                    Label("Kunde inte öppna dina studier", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(store.errorMessage ?? "Försök igen.")
                } actions: {
                    Button("Försök igen") { loadStudies() }
                }
            } else if store.journey.profile == nil {
                NavigationStack { JourneySetupView() }
                    .id((store.language?.code ?? "") + settings.nativeLanguage.code)
            } else {
                MainTabs()
                    .id((store.language?.code ?? "") + settings.nativeLanguage.code)
            }
        }
        .environment(store)
        .environment(access)
        .tint(LanguLearn.purple)
        .task {
            loadStudies()
            await access.load()
        }
        // Switching restores the chosen language, including its own journey profile and drafts.
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
            Tab("Idag", systemImage: "sun.max", value: .plan) {
                NavigationStack { JourneyTodayView() }
            }
            Tab("Spela", systemImage: "gamecontroller.fill", value: .practice) {
                NavigationStack { PracticeHubView() }
            }
            Tab("Min resa", systemImage: "books.vertical", value: .progress) {
                NavigationStack { JourneyLibraryView() }
            }
        }
    }
}
