import Foundation

/// Learner choices are separate from observations: difficulty is never inferred from typing speed.
nonisolated struct JourneyProfile: Codable, Equatable, Sendable {
    enum Reading: String, Codable, CaseIterable, Sendable {
        case comfortable, newScript, learningToRead
        var title: String {
            switch self {
            case .comfortable: String(localized: "Jag känner igen skriften")
            case .newScript: String(localized: "Tecknen är nya för mig")
            case .learningToRead: String(localized: "Jag vill ha hjälp att läsa")
            }
        }
    }
    enum Experience: String, Codable, CaseIterable, Sendable {
        case new, someWords, everyday, confident
        var title: String {
            switch self {
            case .new: String(localized: "Jag börjar från noll")
            case .someWords: String(localized: "Jag kan ord och enkla fraser")
            case .everyday: String(localized: "Jag klarar vardagliga samtal")
            case .confident: String(localized: "Jag uttrycker mig ganska fritt")
            }
        }
        var isExperienced: Bool { self == .everyday || self == .confident }
    }
    /// Optional so profiles saved before the richer experience picker still decode.
    var experience: Experience? = nil
    var hasSpoken = false
    var reading: Reading = .comfortable
    var goal = ""
    var interests = ""
    var minutes = 5

    var startingExperience: Experience { experience ?? (hasSpoken ? .someWords : .new) }

    func validate() throws {
        guard !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              goal.count <= 400, interests.count <= 400, [3, 5, 10].contains(minutes) else {
            throw LearningValidationError.invalidResponse
        }
    }
}

nonisolated enum JourneyTrack: String, Codable, CaseIterable, Sendable {
    case foundations, mission
    var title: String { self == .foundations ? "Ljud och tecken" : "Vardagsuppdrag" }
}

nonisolated enum JourneySkill: String, Codable, CaseIterable, Sendable {
    case listening, reading, script, writing, speaking
    var title: String {
        switch self {
        case .listening: String(localized: "Förstå det jag hör")
        case .reading: String(localized: "Förstå det jag läser")
        case .script: String(localized: "Känna igen tecken")
        case .writing: String(localized: "Formulera mig själv")
        case .speaking: String(localized: "Prova att säga orden")
        }
    }
}

nonisolated struct JourneyChoice: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var text: String
}

/// Rendering and scoring use explicit fields, never a parsed chat message or generated UI code.
nonisolated struct JourneyStep: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case example, meaningChoice, listeningChoice, scriptChoice, build, write, say
    }
    var id: String
    var kind: Kind
    var skill: JourneySkill
    var skillID: String
    var skillTitle: String
    var instruction: String
    var target: String
    var translation: String
    /// Complete, pronounceable target-language text. Not an invented phonetic transcription.
    var audioText: String
    var choices: [JourneyChoice]
    var correctChoiceID: String
    var tokens: [String]
    var acceptedAnswers: [String]
    var hints: [String]
    var explanation: String

    func validate() throws {
        guard [id, skillID, skillTitle, instruction, target, translation, explanation].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              !id.isEmpty, id.count <= 80, !skillID.isEmpty, skillID.count <= 80,
              !skillTitle.isEmpty, skillTitle.count <= 150,
              !instruction.isEmpty, instruction.count <= 600,
              !target.isEmpty, target.count <= 500, !translation.isEmpty, translation.count <= 600,
              !explanation.isEmpty, explanation.count <= 800, audioText.count <= 500,
              (1...3).contains(hints.count), hints.allSatisfy({ !$0.isEmpty && $0.count <= 500 }),
              Set(choices.map(\.id)).count == choices.count,
              choices.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 40 && !$0.text.isEmpty && $0.text.count <= 300 }),
              tokens.count <= 14, tokens.allSatisfy({ !Self.normalized($0).isEmpty && $0.count <= 80 }),
              acceptedAnswers.count <= 4,
              acceptedAnswers.allSatisfy({ !Self.normalized($0).isEmpty && $0.count <= 500 }) else {
            throw LearningValidationError.invalidResponse
        }
        switch kind {
        case .example:
            guard choices.isEmpty, tokens.isEmpty else { throw LearningValidationError.invalidResponse }
        case .meaningChoice, .listeningChoice, .scriptChoice:
            guard (2...4).contains(choices.count), choices.contains(where: { $0.id == correctChoiceID }),
                  Set(choices.map { Self.normalized($0.text) }).count == choices.count,
                  tokens.isEmpty else { throw LearningValidationError.invalidResponse }
            if kind == .listeningChoice && (skill != .listening || audioText.isEmpty) { throw LearningValidationError.invalidResponse }
            if kind == .scriptChoice && skill != .script { throw LearningValidationError.invalidResponse }
            if kind == .meaningChoice && skill != .reading { throw LearningValidationError.invalidResponse }
        case .build:
            guard skill == .writing, choices.isEmpty, (2...14).contains(tokens.count),
                  !acceptedAnswers.isEmpty else { throw LearningValidationError.invalidResponse }
            for answer in acceptedAnswers {
                var bank = tokens.map(Self.normalized)
                for word in answer.split(separator: " ").map({ Self.normalized(String($0)) }) {
                    guard let index = bank.firstIndex(of: word) else { throw LearningValidationError.invalidResponse }
                    bank.remove(at: index)
                }
            }
        case .write:
            guard skill == .writing, choices.isEmpty, tokens.isEmpty else { throw LearningValidationError.invalidResponse }
        case .say:
            guard skill == .speaking, !audioText.isEmpty, choices.isEmpty, tokens.isEmpty else { throw LearningValidationError.invalidResponse }
        }
    }

    static func normalized(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
    }
}

nonisolated struct JourneyPack: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var targetLanguage: String
    var explanationLanguage: String
    var track: JourneyTrack
    var title: String
    var reason: String
    var steps: [JourneyStep]

    func validate(course: LanguageCourse, track: JourneyTrack) throws {
        guard schemaVersion == 1, targetLanguage == course.target.code,
              explanationLanguage == course.native.code, self.track == track,
              !title.isEmpty, title.count <= 150, !reason.isEmpty, reason.count <= 600,
              (3...8).contains(steps.count), steps.first?.kind == .example,
              steps.contains(where: { ![.example, .say].contains($0.kind) }),
              Set(steps.map(\.id)).count == steps.count else { throw LearningValidationError.invalidResponse }
        for step in steps { try step.validate() }
        if track == .foundations {
            guard !steps.contains(where: { [.write, .build].contains($0.kind) }) else { throw LearningValidationError.invalidResponse }
        }
    }
}

nonisolated struct JourneyEvaluation: Codable, Equatable, Sendable {
    var stepID: String
    var accepted: Bool
    var feedback: String
    var correction: String
    /// Must quote a substring of the submitted answer; explanations alone cannot establish success.
    var evidence: String

    func validate(step: JourneyStep, answer: String) throws {
        guard stepID == step.id, !feedback.isEmpty, feedback.count <= 800,
              correction.count <= 500, evidence.count <= 500,
              !accepted || (!evidence.isEmpty && answer.contains(evidence)) else {
            throw LearningValidationError.invalidResponse
        }
    }
}

nonisolated struct JourneyObservation: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var skillID: String
    var title: String
    var skill: JourneySkill
    var correct: Bool
    var independent: Bool
    var selfReported: Bool
    var date: Date
    var phrase: String
    var translation: String
    var sessionID: UUID? = nil
}

nonisolated struct JourneyPhrase: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var text: String
    var translation: String
    var explanationLanguage: String
}

nonisolated enum JourneyDifficulty: String, Codable, CaseIterable, Sendable {
    case tooEasy, justRight, tooHard
    var title: String {
        switch self { case .tooEasy: String(localized: "För lätt"); case .justRight: String(localized: "Lagom"); case .tooHard: String(localized: "För svårt") }
    }
}

nonisolated struct JourneySession: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var pack: JourneyPack
    var cursor = 0
    var draft = ""
    var selectedTokens: [Int] = []
    var hintCount = 0
    var attempts = 0
    var heardAudio = false
    var revealedText = false
    var evaluation: JourneyEvaluation?
    var pendingAttemptID: UUID?
    var pendingAnswer: String?
    var completedAt: Date?
    var startedAt = Date()
    var difficultyFeedback: JourneyDifficulty? = nil
    var step: JourneyStep? { pack.steps.indices.contains(cursor) ? pack.steps[cursor] : nil }
    var canAdvance: Bool { evaluation?.accepted == true }

    mutating func advance(at date: Date = .now) throws {
        guard let step, canAdvance || step.kind == .example else { throw LearningValidationError.invalidResponse }
        cursor += 1
        draft = ""; selectedTokens = []; hintCount = 0; attempts = 0
        heardAudio = false; revealedText = false; evaluation = nil
        pendingAttemptID = nil; pendingAnswer = nil
        if cursor == pack.steps.count { completedAt = date }
    }
}

nonisolated struct JourneyProgress: Codable, Equatable, Sendable {
    var profile: JourneyProfile?
    var discovery: JourneyDiscovery?
    var sessions: [JourneySession] = []
    var observations: [JourneyObservation] = []
    var phrases: [JourneyPhrase] = []

    var activeSession: JourneySession? { sessions.last(where: { $0.completedAt == nil }) }

    /// This opens a scaffolded activity, not a proficiency claim. Unknown script still takes priority.
    var allowsSupportedWriting: Bool {
        guard let profile, profile.reading == .comfortable else { return false }
        let recognized = Set(observations.filter {
            $0.correct && $0.independent && !$0.selfReported && [.reading, .listening].contains($0.skill)
        }.map(\.skillID))
        return profile.startingExperience != .new || recognized.count >= 3
    }

    var recommendationReason: String {
        guard let profile else { return "Vi börjar där du är." }
        if profile.reading != .comfortable {
            return profile.startingExperience.isExperienced ? "Du har erfarenhet av språket. Vi kopplar den nya skriften till situationer du redan kan förstå." : "Du vill lära känna skriften. Vi tar några tecken i meningsfulla ord."
        }
        if let feedback = sessions.last(where: { $0.difficultyFeedback != nil })?.difficultyFeedback {
            if feedback == .tooEasy { return "Du tyckte att det var för lätt. Nästa uppdrag får mer öppna frågor och en ny utmaning." }
            if feedback == .tooHard { return "Du tyckte att det var för svårt. Nästa uppdrag får tydligare exempel och mindre steg." }
        }
        if profile.startingExperience.isExperienced && observations.isEmpty {
            return "Du har redan en grund. Vi börjar med en hel situation utifrån ditt mål, med utrymme att uttrycka dig själv."
        }
        if let recent = observations.last(where: { !$0.selfReported && (!$0.correct || !$0.independent) }) {
            return "Vi bygger vidare på \(recent.title.lowercased()) med stöd där det behövs."
        }
        if profile.startingExperience == .new && observations.isEmpty { return "Du är helt ny. Vi börjar med att lyssna och känna igen." }
        return "Vi väljer situationer som tar dig närmare ditt mål: \(profile.goal)"
    }
    var recommendedTrack: JourneyTrack {
        guard let profile else { return .foundations }
        let foundationComplete = sessions.contains { $0.pack.track == .foundations && $0.completedAt != nil }
        if profile.reading != .comfortable { return .foundations }
        return !foundationComplete && profile.startingExperience == .new ? .foundations : .mission
    }

    /// A review is due after a day, then after 3 / 7 / 14 days following independent successful recall.
    /// Recognition, help and self-reported speech never masquerade as independent production.
    func dueObservations(at now: Date = .now) -> [JourneyObservation] {
        Dictionary(grouping: observations.filter { !$0.selfReported }, by: { "\($0.skillID):\($0.skill.rawValue)" })
            .values.compactMap { history in
                guard let latest = history.max(by: { $0.date < $1.date }) else { return nil }
                let successes = Set(history.filter { $0.correct && $0.independent }.map { Int($0.date.timeIntervalSince1970 / 86400) }).count
                let days = !latest.correct || !latest.independent ? 1 : [1, 3, 7, 14][min(max(successes - 1, 0), 3)]
                return now.timeIntervalSince(latest.date) >= Double(days * 86400) ? latest : nil
            }.sorted { $0.date < $1.date }
    }

    mutating func record(_ observation: JourneyObservation) {
        guard !observations.contains(where: { $0.id == observation.id }) else { return }
        observations.append(observation)
    }
}
