import SwiftData
import SwiftUI

@main struct MyApp: App {
    @State private var settings = TutorSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                // The design is specified for light appearance only.
                .preferredColorScheme(.light)
        }
        .modelContainer(for: LessonRecord.self)
    }
}
