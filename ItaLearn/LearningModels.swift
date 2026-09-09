import Foundation

nonisolated enum LearningValidationError: LocalizedError {
    case invalidResponse
    case unsupportedVersion
    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Lärarens svar gick inte att använda. Försök igen; din nuvarande plan finns kvar."
        case .unsupportedVersion: "Dina sparade studier kräver en nyare version av ItaLearn."
        }
    }
}

nonisolated struct ChatMessage: Codable, Identifiable, Sendable, Equatable {
    enum Role: String, Codable, Sendable { case user, assistant }
    var id = UUID()
    var role: Role
    var text: String
    var translation = ""
    var correction: Correction?
    var needsRetry = false
}

nonisolated struct Correction: Codable, Sendable, Equatable {
    var original: String
    var corrected: String
    var explanation: String
}

nonisolated struct LearnerProfile: Codable, Sendable, Equatable {
    var nativeLanguage: String
    var targetLanguage: String
    var cefr: String
    var goal: String
    var strengths: [String]
    var focusAreas: [String]
}

nonisolated struct PlannedLesson: Codable, Identifiable, Sendable, Equatable {
    var id: String
    var title: String
    var summary: String
    var objectives: [String]
    var prerequisites: [String]
    var vocabulary: [String]
    var scenario: String
    var successCriteria: [String]
}

/// Exactly the structured JSON contract returned by Sol. App IDs/dates live outside it.
nonisolated struct AssessmentResult: Codable, Sendable, Equatable {
    enum Recommendation: String, Codable, Sendable { case newPlan, continueCurrent }
    var schemaVersion: Int
    var recommendation: Recommendation
    var rationale: String
    var profile: LearnerProfile
    var lessons: [PlannedLesson]

    func validate(hasCurrentPlan: Bool) throws {
        guard schemaVersion == 1 else { throw LearningValidationError.unsupportedVersion }
        guard profile.nativeLanguage == "sv", profile.targetLanguage == "it",
              ["pre-A1", "A1", "A2", "B1", "B2", "C1", "C2"].contains(profile.cefr),
              !profile.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              rationale.count <= 3000,
              profile.strengths.count <= 8, profile.focusAreas.count <= 8 else {
            throw LearningValidationError.invalidResponse
        }
        if recommendation == .continueCurrent {
            guard hasCurrentPlan, lessons.isEmpty else { throw LearningValidationError.invalidResponse }
            return
        }
        guard (3...8).contains(lessons.count) else { throw LearningValidationError.invalidResponse }
        var seen = Set<String>()
        for lesson in lessons {
            guard !lesson.id.isEmpty, lesson.id.count <= 80, !seen.contains(lesson.id),
                  !lesson.title.isEmpty, lesson.title.count <= 150,
                  !lesson.summary.isEmpty, !lesson.scenario.isEmpty,
                  (1...5).contains(lesson.objectives.count),
                  (1...5).contains(lesson.successCriteria.count),
                  lesson.vocabulary.count <= 15,
                  lesson.prerequisites.allSatisfy({ seen.contains($0) }),
                  (lesson.objectives + lesson.successCriteria).allSatisfy({ !$0.isEmpty && $0.count <= 1000 }) else {
                throw LearningValidationError.invalidResponse
            }
            seen.insert(lesson.id)
        }
    }
}

nonisolated struct AssessmentQuestion: Codable, Sendable {
    var question: String
    var translation: String
    var skill: String

    func validate() throws {
        guard !question.isEmpty, question.count <= 2000,
              translation.count <= 2000, !skill.isEmpty else {
            throw LearningValidationError.invalidResponse
        }
    }
}

nonisolated struct LessonReply: Codable, Sendable {
    var italian: String
    var swedish: String
    var correction: Correction?
    var requiresRetry: Bool
    var retryPrompt: String
    var objectiveIDsAchieved: [Int]
    var lessonComplete: Bool
    var memory: String

    func validate(objectiveCount: Int) throws {
        guard !italian.isEmpty, italian.count <= 3000, swedish.count <= 3000,
              memory.count <= 3000,
              objectiveIDsAchieved.allSatisfy({ (0..<objectiveCount).contains($0) }),
              Set(objectiveIDsAchieved).count == objectiveIDsAchieved.count,
              !(requiresRetry && (lessonComplete || retryPrompt.isEmpty || !objectiveIDsAchieved.isEmpty)) else {
            throw LearningValidationError.invalidResponse
        }
        if let correction {
            guard !correction.original.isEmpty, !correction.corrected.isEmpty,
                  !correction.explanation.isEmpty else { throw LearningValidationError.invalidResponse }
        }
    }
}

nonisolated struct AssessmentSession: Codable, Identifiable, Sendable {
    static let questionCount = 6
    var id = UUID()
    var messages: [ChatMessage] = [ChatMessage(
        role: .assistant,
        text: "Ciao! Jag hjälper dig att hitta en bra start i italienskan. Vad vill du kunna använda språket till? Presentera dig gärna med en mening på italienska. Det går bra att säga att du inte vet ännu.",
        translation: "Vi tar sex korta frågor, en i taget. Det här är en uppskattning av din skriftliga nivå, inte ett formellt språkprov."
    )]
    var pendingAnswer: String?
    var answeredCount: Int { messages.filter { $0.role == .user }.count }
}

nonisolated struct SavedAssessment: Codable, Identifiable, Sendable {
    var id = UUID()
    var createdAt = Date()
    var result: AssessmentResult
    /// Validated original JSON from the API, retained for export and future migrations.
    var resultJSON: Data
    var messages: [ChatMessage]
}

nonisolated struct LearningPlan: Codable, Identifiable, Sendable {
    var id = UUID()
    var createdAt = Date()
    var profile: LearnerProfile
    var lessons: [PlannedLesson]
    var completedLessonIDs: Set<String> = []
}

nonisolated struct LessonSession: Codable, Identifiable, Sendable {
    var id = UUID()
    var planID: UUID
    var lessonID: String
    var messages: [ChatMessage] = []
    var pendingAnswer: String?
    var memory = ""
    var achievedObjectives: Set<Int> = []
    var requiresRetry = false
    var isComplete = false

    mutating func accept(_ reply: LessonReply, objectiveCount: Int) throws {
        try reply.validate(objectiveCount: objectiveCount)
        let hasAnswer = pendingAnswer != nil
        if let pendingAnswer { messages.append(ChatMessage(role: .user, text: pendingAnswer)) }
        // Opening messages cannot establish knowledge or finish a lesson.
        if hasAnswer {
            achievedObjectives.formUnion(reply.objectiveIDsAchieved)
            requiresRetry = reply.requiresRetry
            isComplete = reply.lessonComplete && !requiresRetry && achievedObjectives.count == objectiveCount
                && messages.filter({ $0.role == .user }).count >= 2
        }
        messages.append(ChatMessage(
            role: .assistant, text: reply.italian, translation: reply.swedish,
            correction: hasAnswer ? reply.correction : nil, needsRetry: hasAnswer && reply.requiresRetry
        ))
        if hasAnswer && reply.requiresRetry {
            messages.append(ChatMessage(role: .assistant, text: reply.retryPrompt))
        }
        memory = reply.memory
        pendingAnswer = nil
    }
}

nonisolated struct LearningState: Codable, Sendable {
    var schemaVersion = 1
    var activePlan: LearningPlan?
    var archivedPlans: [LearningPlan] = []
    var assessments: [SavedAssessment] = []
    var assessment: AssessmentSession?
    var sessions: [LessonSession] = []

    mutating func apply(_ result: AssessmentResult, rawJSON: Data) throws {
        try result.validate(hasCurrentPlan: activePlan != nil)
        guard let assessment, assessment.answeredCount == AssessmentSession.questionCount else {
            throw LearningValidationError.invalidResponse
        }
        assessments.append(SavedAssessment(result: result, resultJSON: rawJSON, messages: assessment.messages))
        switch result.recommendation {
        case .newPlan:
            if let activePlan { archivedPlans.append(activePlan) }
            activePlan = LearningPlan(profile: result.profile, lessons: result.lessons)
        case .continueCurrent:
            activePlan?.profile = result.profile
        }
        self.assessment = nil
    }
}
