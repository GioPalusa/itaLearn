import Foundation
import Observation

/// A snapshot of the exercise when help was opened. Help never writes to learning progress.
nonisolated struct ExerciseHelpContext: Encodable, Sendable {
    enum Activity: String, Encodable, Sendable {
        case lesson, conversation, writing, sentencePuzzle, flashcard, pronoun
    }
    var course: LanguageCourse
    var activity: Activity
    var task: String
    var material: [String] = []
    var draft: String = ""
    var profile: LearnerProfile?
    var lesson: LessonContext?
    var recentMessages: [ChatMessage] = []
    var memory: String = ""
    var tone: String
}

nonisolated enum ExerciseHelpKind: String, CaseIterable, Encodable, Sendable {
    case explain, hint, meaning, getStarted, followUp

    var title: String {
        switch self {
        case .explain: String(localized: "Förklara uppgiften")
        case .hint: String(localized: "Ge mig ett tips")
        case .meaning: String(localized: "Vad betyder det?")
        case .getStarted: String(localized: "Hjälp mig komma igång")
        case .followUp: String(localized: "Fråga Milo")
        }
    }
}

nonisolated struct ExerciseHelpExchange: Encodable, Identifiable, Sendable {
    var id = UUID()
    var kind: ExerciseHelpKind
    var question: String
    var answer: String
}

/// A help conversation that a screen can keep and reopen without mixing it into assessed chat.
nonisolated struct ExerciseHelpTranscript: Identifiable, Sendable {
    var id = UUID()
    var exercise: ExerciseHelpContext
    var exchanges: [ExerciseHelpExchange]
}

nonisolated struct ExerciseHelpRequest: Encodable, Sendable {
    var exercise: ExerciseHelpContext
    var kind: ExerciseHelpKind
    var question: String
    var previousHelp: [ExerciseHelpExchange]
}

nonisolated struct ExerciseHelpReply: Codable, Sendable {
    var explanation: String

    func validate() throws {
        guard !explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              explanation.count <= 6000 else { throw LearningValidationError.invalidResponse }
    }
}

/// Independent from LearningChat: hints cannot consume answers, award objectives or finish lessons.
@MainActor @Observable
final class ExerciseHelpSession {
    private(set) var exchanges: [ExerciseHelpExchange] = []
    private(set) var isWorking = false
    private(set) var errorMessage: String?
    private(set) var pendingRequest: ExerciseHelpRequest?
    private let service: any LearningService
    private var generation = UUID()
    private var task: Task<Void, Never>?

    init(service: any LearningService = OpenAILearningService(),
         exchanges: [ExerciseHelpExchange] = []) {
        self.service = service
        self.exchanges = exchanges
    }

    func ask(_ kind: ExerciseHelpKind, question: String, exercise: ExerciseHelpContext) {
        guard !isWorking else { return }
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard question.count <= 2000, kind != .followUp || !question.isEmpty else { return }
        let request = ExerciseHelpRequest(exercise: exercise, kind: kind, question: question,
                                          previousHelp: Array(exchanges.suffix(6)))
        run(request)
    }

    func retry() {
        guard !isWorking, let pendingRequest else { return }
        run(pendingRequest)
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        isWorking = false
    }

    func waitForCurrentRequest() async { await task?.value }

    private func run(_ request: ExerciseHelpRequest) {
        pendingRequest = request
        errorMessage = nil
        isWorking = true
        let token = UUID()
        generation = token
        task = Task {
            defer { if generation == token { isWorking = false; task = nil } }
            do {
                let reply = try await service.help(request)
                try Task.checkCancellation()
                guard generation == token else { return }
                try reply.validate()
                exchanges.append(ExerciseHelpExchange(kind: request.kind, question: request.question,
                                                      answer: reply.explanation))
                pendingRequest = nil
            } catch {
                guard generation == token, !Task.isCancelled, !(error is CancellationError) else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}

extension LearningStore {
    func helpContext(settings: TutorSettings, activity: ExerciseHelpContext.Activity,
                     task: String, material: [String] = [], draft: String = "",
                     sessionID: UUID? = nil) -> ExerciseHelpContext {
        let lesson = sessionID.flatMap { try? lessonContext(sessionID: $0, settings: settings) }
        let conversation = activity == .conversation ? state.freeChat : nil
        return ExerciseHelpContext(
            course: settings.course, activity: activity, task: task, material: material,
            draft: draft, profile: lesson?.profile ?? state.activePlan?.profile, lesson: lesson,
            recentMessages: Array((conversation?.messages ?? []).suffix(16)),
            memory: conversation?.memory ?? "", tone: settings.tone.modelInstruction
        )
    }
}
