// swift-tools-version: 6.2
import PackageDescription

// Exercises the same production sources without launching a signed iOS host.
let package = Package(
    name: "ItaLearnCore",
    platforms: [.macOS("27.0")],
    products: [.library(name: "ItaLearnCore", targets: ["ItaLearnCore"])],
    targets: [
        .target(
            name: "ItaLearnCore", path: "ItaLearn",
            exclude: ["Assets.xcassets", "Resources", "MiloScene.swift", "MiloDemoView.swift", "MiloSpeechView.swift", "MiloView.swift", "ContentView.swift", "ConversationEngine.swift", "ConversationView.swift", "CorrectionDiff.swift", "HomeView.swift", "ItaLearn.entitlements", "ItaLearnDebug.entitlements", "ItalianTutor.swift", "JourneyRoute.swift", "LearningViews.swift", "PracticeViews.swift", "LessonCatalog.swift", "LessonCatalogView.swift", "LessonHistoryView.swift", "LessonView.swift", "Localizable.xcstrings", "MyApp.swift", "OnboardingView.swift", "PaywallView.swift", "SettingsView.swift"],
            sources: ["SpeechNarrator.swift","DesignSystem.swift", "LessonDialogue.swift","MiloAnimation.swift", "MiloClipLibrary.swift", "TeacherIdentity.swift","PracticeModels.swift", "LearningMarkdown.swift", "LearningModels.swift", "LearningStore.swift", "LearningService.swift", "OpenAIClient.swift", "OpenAIKeyStore.swift", "TutorSettings.swift", "LessonRecord.swift"],
            swiftSettings: [.defaultIsolation(MainActor.self), .enableUpcomingFeature("BareSlashRegexLiterals")]
        ),
        .testTarget(name: "ItaLearnCoreTests", dependencies: ["ItaLearnCore"], path: "Tests/ItaLearnCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
