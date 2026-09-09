import SwiftData
import SwiftUI

@main struct MyApp: App {
    @State private var settings = TutorSettings()
    private let storage = Result {
        try ModelContainer(
            for: LessonRecord.self, LearningSnapshot.self,
            configurations: ModelConfiguration(cloudKitDatabase: .none)
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch storage {
                case .success(let container):
                    ContentView().modelContainer(container)
                case .failure:
                    ContentUnavailableView(
                        "Dina studier kunde inte öppnas",
                        systemImage: "externaldrive.badge.exclamationmark",
                        description: Text("Starta om appen och kontrollera ledigt lagringsutrymme. Dina sparade data har inte raderats.")
                    )
                }
            }
            .environment(settings)
            .preferredColorScheme(.light)
        }
    }
}
