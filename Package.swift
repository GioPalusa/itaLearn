// swift-tools-version: 6.2
import PackageDescription

// Exercises the same production sources without launching a signed iOS host.
let package = Package(
    name: "LangLearnCore",
    platforms: [.macOS("27.0")],
    products: [.library(name: "LangLearnCore", targets: ["LangLearnCore"])],
    targets: [
        .target(
            name: "LangLearnCore", path: "LangLearn",
            exclude: ["Assets.xcassets", "Resources", "MiloScene.swift", "MiloDemoView.swift", "MiloSpeechView.swift", "MiloView.swift", "ContentView.swift", "ConversationEngine.swift", "ConversationView.swift", "CorrectionDiff.swift", "HomeView.swift", "LangLearn.entitlements", "LangLearnDebug.entitlements", "ItalianTutor.swift", "JourneyRoute.swift", "LearningViews.swift", "PracticeViews.swift", "LessonCatalog.swift", "LessonCatalogView.swift", "LessonHistoryView.swift", "LessonView.swift", "Localizable.xcstrings", "MyApp.swift", "OnboardingView.swift", "PaywallView.swift", "SettingsView.swift"],
            sources: ["SpeechNarrator.swift","DesignSystem.swift", "LessonDialogue.swift","MiloAnimation.swift", "MiloClipLibrary.swift", "LearningLanguage.swift", "TeacherIdentity.swift","PracticeModels.swift", "LearningMarkdown.swift", "LearningModels.swift", "LearningStore.swift", "LearningService.swift", "OpenAIClient.swift", "OpenAIKeyStore.swift", "TutorSettings.swift", "LessonRecord.swift"],
            swiftSettings: [.defaultIsolation(MainActor.self), .enableUpcomingFeature("BareSlashRegexLiterals")]
        ),
        .testTarget(name: "LangLearnCoreTests", dependencies: ["LangLearnCore"], path: "Tests/LangLearnCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
