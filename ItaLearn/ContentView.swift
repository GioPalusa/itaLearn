import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var store = LearningStore()
    @State private var access = OpenAIAccess()

    var body: some View {
        Group {
            if !access.isReady {
                ProgressView("Öppnar ItaLearn…")
            } else if !access.hasKey {
                OnboardingView()
            } else if !store.isLoaded {
                ContentUnavailableView {
                    Label("Kunde inte öppna dina studier", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(store.errorMessage ?? "Försök igen.")
                } actions: {
                    Button("Försök igen") { store.load(container: modelContext.container) }
                }
            } else if store.state.activePlan == nil {
                NavigationStack { AdaptiveChatView(mode: .assessment) }
            } else {
                TabView {
                    Tab("Min studieplan", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                        NavigationStack { LearningPathView() }
                    }
                    Tab("Samtal", systemImage: "bubble.left.and.bubble.right") {
                        NavigationStack { CurrentLessonView() }
                    }
                    Tab("Mitt lärande", systemImage: "books.vertical") {
                        NavigationStack { LearningProgressView() }
                    }
                }
            }
        }
        .environment(store)
        .environment(access)
        .tint(ItaLearn.purple)
        .task {
            store.load(container: modelContext.container)
            await access.load()
        }
    }
}
