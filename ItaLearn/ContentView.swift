import SwiftData
import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                LessonCatalogView()
            }
            .tabItem {
                Label("Öva", systemImage: "pencil.and.scribble")
            }

            NavigationStack {
                LessonHistoryView()
            }
            .tabItem {
                Label("Mitt lärande", systemImage: "books.vertical")
            }
        }
        .tint(.orange)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: LessonRecord.self, inMemory: true)
}
