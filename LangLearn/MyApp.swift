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
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--journey-preview") {
                    JourneyPreview()
                } else if ProcessInfo.processInfo.arguments.contains("--milo-placement-preview") {
                    MiloPlacementPreview()
                } else if ProcessInfo.processInfo.arguments.contains("--onboarding-preview") {
                    OnboardingPreviewHost()
                } else if ProcessInfo.processInfo.arguments.contains("--milo-avatar-demo") {
                    NavigationStack { MiloAvatarDemoView() }
                } else if ProcessInfo.processInfo.arguments.contains("--milo-demo") {
                    MiloDemoView()
                } else { appContent }
#else
                appContent
#endif
            }
            .environment(settings)
            .preferredColorScheme(.light)
        }
    }
    @ViewBuilder private var appContent: some View {
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
}
