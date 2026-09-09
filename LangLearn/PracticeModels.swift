import Foundation

nonisolated struct LessonWrapUp: Codable, Sendable, Equatable {
    var summary: String
    var strengths: [String]
    var nextSteps: [String]
    var demonstratedObjectives: [Int]
    var readyToAdvance: Bool

    func validate(objectiveCount: Int) throws {
        guard !summary.isEmpty, summary.count <= 3000,
              strengths.count <= 5, (1...5).contains(nextSteps.count),
              (strengths + nextSteps).allSatisfy({ !$0.isEmpty && $0.count <= 1000 }),
              Set(demonstratedObjectives).count == demonstratedObjectives.count,
              demonstratedObjectives.allSatisfy({ (0..<objectiveCount).contains($0) }),
              !readyToAdvance || demonstratedObjectives.count == objectiveCount else {
            throw LearningValidationError.invalidResponse
        }
    }
}

nonisolated struct Flashcard: Codable, Identifiable, Sendable, Equatable {
    var id: String
    /// The prompt, in the learner's own language.
    var cue: String
    /// The answer, in the language being learned.
    var answer: String
    var example: String

    // Packs saved before the app went multilingual keyed these by language name.
    private enum CodingKeys: String, CodingKey { case id, cue, answer, example, swedish, italian }

    init(id: String, cue: String, answer: String, example: String) {
        self.id = id
        self.cue = cue
        self.answer = answer
        self.example = example
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        cue = try values.decodeIfPresent(String.self, forKey: .cue)
            ?? values.decode(String.self, forKey: .swedish)
        answer = try values.decodeIfPresent(String.self, forKey: .answer)
            ?? values.decode(String.self, forKey: .italian)
        example = try values.decode(String.self, forKey: .example)
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(cue, forKey: .cue)
        try values.encode(answer, forKey: .answer)
        try values.encode(example, forKey: .example)
    }
}

nonisolated struct SentencePuzzle: Codable, Identifiable, Sendable, Equatable {
    var id: String
    /// The sentence to translate, in the learner's own language.
    var cue: String
    /// Alternatives must be constructible using the same word bank, including repeated words.
    var answers: [[String]]
    var words: [String]
    var explanation: String

    // Packs saved before the app went multilingual keyed the cue by language name.
    private enum CodingKeys: String, CodingKey { case id, cue, answers, words, explanation, swedish }

    init(id: String, cue: String, answers: [[String]], words: [String], explanation: String) {
        self.id = id
        self.cue = cue
        self.answers = answers
        self.words = words
        self.explanation = explanation
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        cue = try values.decodeIfPresent(String.self, forKey: .cue)
            ?? values.decode(String.self, forKey: .swedish)
        answers = try values.decode([[String]].self, forKey: .answers)
        words = try values.decode([String].self, forKey: .words)
        explanation = try values.decode(String.self, forKey: .explanation)
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(cue, forKey: .cue)
        try values.encode(answers, forKey: .answers)
        try values.encode(words, forKey: .words)
        try values.encode(explanation, forKey: .explanation)
    }

    func matches(_ selected: [String]) -> Bool {
        answers.contains { $0.map(Self.normalized) == selected.map(Self.normalized) }
    }

    static func normalized(_ word: String) -> String {
        word.lowercased().replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;: "))
    }
}

/// One way forward Milo can propose after a finished plan.
nonisolated struct PlanDirection: Codable, Sendable, Identifiable, Equatable {
    var id: String
    /// Swedish, e.g. "Fortsätt träna på resor" or "Mat och restaurang".
    var title: String
    /// Why Milo suggests it, grounded in what the learner actually did.
    var rationale: String
    /// True when this consolidates the area they are already on.
    var consolidates: Bool
}

nonisolated struct PlanDirections: Codable, Sendable {
    /// The id Milo recommends; the learner can pick any of them.
    var recommended: String
    var options: [PlanDirection]

    func validate() throws {
        guard (3...5).contains(options.count),
              Set(options.map(\.id)).count == options.count,
              options.contains(where: { $0.id == recommended }),
              options.allSatisfy({ option in
                  !option.id.isEmpty && option.id.count <= 60
                      && !option.title.isEmpty && option.title.count <= 80
                      && !option.rationale.isEmpty && option.rationale.count <= 600
              })
        else { throw LearningValidationError.invalidResponse }
    }
}

/// Lessons that continue an existing plan rather than replacing it.
nonisolated struct PlanExtension: Codable, Sendable {
    var lessons: [PlannedLesson]

    func validate(existingIDs: Set<String>) throws {
        guard (6...12).contains(lessons.count) else { throw LearningValidationError.invalidResponse }
        var known = existingIDs
        for lesson in lessons {
            guard !lesson.id.isEmpty, lesson.id.count <= 80, !known.contains(lesson.id),
                  !lesson.title.isEmpty, lesson.title.count <= 150,
                  !lesson.summary.isEmpty, !lesson.scenario.isEmpty,
                  (1...5).contains(lesson.objectives.count),
                  (1...5).contains(lesson.successCriteria.count),
                  lesson.vocabulary.count <= 15,
                  lesson.estimatedMinutes.map({ (3...60).contains($0) }) ?? true,
                  // A new lesson may build on the existing plan or on earlier new ones.
                  lesson.prerequisites.allSatisfy({ known.contains($0) }),
                  (lesson.objectives + lesson.successCriteria).allSatisfy({ !$0.isEmpty && $0.count <= 1000 })
            else { throw LearningValidationError.invalidResponse }
            known.insert(lesson.id)
        }
    }
}

nonisolated struct PuzzleHint: Codable, Sendable, Equatable {
    var encouragement: String
    var hint: String
    /// One word from the bank that belongs next, or empty when a nudge is enough.
    var nextWord: String

    func validate(words: [String]) throws {
        let normalizedBank = words.map(SentencePuzzle.normalized)
        guard !encouragement.isEmpty, encouragement.count <= 400,
              !hint.isEmpty, hint.count <= 800, nextWord.count <= 60,
              nextWord.isEmpty || normalizedBank.contains(SentencePuzzle.normalized(nextWord)) else {
            throw LearningValidationError.invalidResponse
        }
    }
}

nonisolated struct PracticePack: Codable, Sendable, Equatable {
    var flashcards: [Flashcard]
    var puzzles: [SentencePuzzle]

    func validate() throws {
        guard (4...12).contains(flashcards.count), (3...8).contains(puzzles.count),
              Set(flashcards.map(\.id)).count == flashcards.count,
              Set(puzzles.map(\.id)).count == puzzles.count else { throw LearningValidationError.invalidResponse }
        for card in flashcards {
            guard [card.id, card.cue, card.answer, card.example].allSatisfy({ !$0.isEmpty && $0.count <= 800 }) else {
                throw LearningValidationError.invalidResponse
            }
        }
        for puzzle in puzzles {
            guard !puzzle.id.isEmpty, !puzzle.cue.isEmpty, puzzle.cue.count <= 800,
                  !puzzle.explanation.isEmpty, puzzle.explanation.count <= 1000,
                  (3...16).contains(puzzle.words.count), (1...4).contains(puzzle.answers.count),
                  puzzle.words.allSatisfy({ !$0.isEmpty && $0.count <= 60 && !$0.contains(where: \.isWhitespace) }) else {
                throw LearningValidationError.invalidResponse
            }
            for answer in puzzle.answers {
                guard (2...14).contains(answer.count) else { throw LearningValidationError.invalidResponse }
                var available = puzzle.words.map(SentencePuzzle.normalized)
                for word in answer.map(SentencePuzzle.normalized) {
                    guard let index = available.firstIndex(of: word) else { throw LearningValidationError.invalidResponse }
                    available.remove(at: index)
                }
            }
        }
    }
}

nonisolated extension PracticePack {
    /// Adds a freshly generated pack, dropping anything the learner already has and
    /// renaming ids that collide, so existing progress keys stay valid.
    mutating func append(_ other: PracticePack) {
        var usedIDs = Set(flashcards.map(\.id)).union(puzzles.map(\.id))
        let knownCues = Set(flashcards.map { SentencePuzzle.normalized($0.cue) })
        let knownPrompts = Set(puzzles.map { SentencePuzzle.normalized($0.cue) })

        for var card in other.flashcards where !knownCues.contains(SentencePuzzle.normalized(card.cue)) {
            card.id = PracticePack.uniqueID(card.id, taken: &usedIDs)
            flashcards.append(card)
        }
        for var puzzle in other.puzzles where !knownPrompts.contains(SentencePuzzle.normalized(puzzle.cue)) {
            puzzle.id = PracticePack.uniqueID(puzzle.id, taken: &usedIDs)
            puzzles.append(puzzle)
        }
    }

    private static func uniqueID(_ proposed: String, taken: inout Set<String>) -> String {
        var candidate = proposed
        var suffix = 2
        while taken.contains(candidate) {
            candidate = "\(proposed)-\(suffix)"
            suffix += 1
        }
        taken.insert(candidate)
        return candidate
    }
}

nonisolated struct PracticeProgress: Codable, Sendable {
    var pack: PracticePack
    var knownCardIDs: Set<String> = []
    var solvedPuzzleIDs: Set<String> = []

    // Optional additions keep existing snapshots decodable.
    /// Where the learner stopped, so a round resumes instead of restarting.
    var puzzleCursor: Int?
    /// Tiles already placed in the unfinished sentence, by bank index.
    var puzzleDraft: [Int]?
    /// The shuffled bank order, kept so resuming does not reshuffle the tiles.
    var puzzleBankOrder: [Int]?
    var puzzleAttempts: [String: Int]?
    var puzzleHints: [String: PuzzleHint]?
    var cardCursor: Int?
    /// Flashcard ids in their shuffled order, including cards queued for another look.
    var cardQueue: [String]?

    func attempts(for puzzleID: String) -> Int { puzzleAttempts?[puzzleID] ?? 0 }
    func hint(for puzzleID: String) -> PuzzleHint? { puzzleHints?[puzzleID] }

    /// True when a round was left part-way through.
    var hasUnfinishedSentence: Bool {
        guard let puzzleCursor else { return false }
        return puzzleCursor > 0 && puzzleCursor < pack.puzzles.count
    }
}

/// Tile identity is its original bank index, so duplicate words remain independently movable.
nonisolated struct WordAssembly: Equatable {
    private(set) var selected: [Int] = []

    init(selected: [Int] = []) { self.selected = selected }

    mutating func place(_ tile: Int, before destination: Int? = nil, wordCount: Int) {
        guard (0..<wordCount).contains(tile), tile != destination else { return }
        let target = destination.flatMap { selected.firstIndex(of: $0) } ?? selected.count
        insert(tile, at: target, wordCount: wordCount)
    }

    /// Moves `tile` to `index` in the sentence. Removing it first shifts everything
    /// after it left, so the target is corrected before inserting.
    mutating func insert(_ tile: Int, at index: Int, wordCount: Int) {
        guard (0..<wordCount).contains(tile) else { return }
        var target = min(max(index, 0), selected.count)
        if let current = selected.firstIndex(of: tile) {
            selected.remove(at: current)
            if current < target { target -= 1 }
        }
        selected.insert(tile, at: min(max(target, 0), selected.count))
    }

    mutating func remove(_ tile: Int) { selected.removeAll { $0 == tile } }
    mutating func reset() { selected = [] }
    func words(in puzzle: SentencePuzzle) -> [String] { selected.compactMap { puzzle.words.indices.contains($0) ? puzzle.words[$0] : nil } }
}

// MARK: - Subject pronouns

/// One subject pronoun in the language being learned.
///
/// Person and number are kept as data rather than baked into a label, because the
/// paradigm is what the learner is trying to internalise: the game lays the
/// pronouns out as a grid, and every language fills that grid differently.
nonisolated struct SubjectPronoun: Codable, Identifiable, Sendable, Equatable {
    /// The pronoun itself, e.g. "io", "你", "hän".
    var pronoun: String
    /// What it means in the learner's own language, e.g. "jag".
    var meaning: String
    /// 1, 2 or 3.
    var person: Int
    var plural: Bool
    /// Politeness, gender or register, e.g. "formellt" or "hon". Often empty.
    var note: String
    /// Reading help where the script needs it: pinyin, romaji, transliteration.
    var pronunciation: String

    var id: String { "\(person)\(plural ? "p" : "s")-\(pronoun)" }
}

/// One round: a sentence with the subject pronoun taken out.
nonisolated struct PronounRound: Codable, Identifiable, Sendable, Equatable {
    var id: String
    /// The sentence in the target language, with `PronounGame.blank` where the
    /// pronoun belongs.
    var sentence: String
    /// The whole sentence in the learner's own language, so the blank is decidable.
    var translation: String
    /// The pronoun that belongs in the blank; always one of the game's pronouns.
    var answer: String
    /// Why that one, in the learner's own language.
    var explanation: String
}

nonisolated struct PronounGame: Codable, Sendable, Equatable {
    /// How this language handles subject pronouns as a whole — dropped subjects in
    /// Italian, politeness levels in Korean, no person marking in Indonesian.
    var overview: String
    var pronouns: [SubjectPronoun]
    var rounds: [PronounRound]

    /// What the model writes where the pronoun should go.
    static let blank = "___"

    func validate() throws {
        guard (2...12).contains(pronouns.count),
              (6...16).contains(rounds.count),
              !overview.isEmpty, overview.count <= 1000,
              Set(rounds.map(\.id)).count == rounds.count,
              Set(pronouns.map(\.id)).count == pronouns.count else {
            throw LearningValidationError.invalidResponse
        }
        for pronoun in pronouns {
            guard !pronoun.pronoun.isEmpty, pronoun.pronoun.count <= 40,
                  !pronoun.meaning.isEmpty, pronoun.meaning.count <= 80,
                  (1...3).contains(pronoun.person),
                  pronoun.note.count <= 120, pronoun.pronunciation.count <= 60 else {
                throw LearningValidationError.invalidResponse
            }
        }
        let forms = Set(pronouns.map(\.pronoun))
        for round in rounds {
            guard !round.id.isEmpty, round.id.count <= 60,
                  round.sentence.contains(Self.blank), round.sentence.count <= 300,
                  !round.translation.isEmpty, round.translation.count <= 300,
                  // An answer outside the paradigm would be unanswerable in the UI.
                  forms.contains(round.answer),
                  !round.explanation.isEmpty, round.explanation.count <= 600 else {
                throw LearningValidationError.invalidResponse
            }
        }
    }
}

/// How far the learner has got with the pronoun game for one language.
nonisolated struct PronounGameProgress: Codable, Sendable, Equatable {
    var game: PronounGame
    var solvedRoundIDs: Set<String> = []
    var attemptsByRound: [String: Int] = [:]
    var bestStreak = 0
    /// Where to resume, so the game does not restart from the top.
    var cursor = 0

    var isComplete: Bool { solvedRoundIDs.count == game.rounds.count }
    func attempts(for roundID: String) -> Int { attemptsByRound[roundID] ?? 0 }

    /// Solved on the first try, which is what "learned it" actually looks like.
    var firstTryCount: Int {
        solvedRoundIDs.filter { attempts(for: $0) <= 1 }.count
    }
}

// MARK: - Free conversation and written feedback

/// One turn of open conversation. Unlike a lesson turn there are no objectives to
/// tick off, so the reply carries only the correction and what to remember.
nonisolated struct ChatTurn: Codable, Sendable, Equatable {
    /// Milo's message, in the language being learned.
    var reply: String
    /// The same message in the learner's own language.
    var translation: String
    var correction: Correction?
    /// A short running note on the learner, carried into the next turn.
    var memory: String

    func validate() throws {
        guard !reply.isEmpty, reply.count <= 3000,
              translation.count <= 3000, memory.count <= 3000 else {
            throw LearningValidationError.invalidResponse
        }
        if let correction {
            guard !correction.original.isEmpty, !correction.corrected.isEmpty,
                  !correction.explanation.isEmpty else { throw LearningValidationError.invalidResponse }
        }
    }
}

/// An open-ended conversation, kept per language beside the plan.
nonisolated struct FreeChatSession: Codable, Sendable, Equatable {
    var messages: [ChatMessage] = []
    var pendingAnswer: String?
    var memory = ""

    /// Bounded so a long-running chat cannot grow the request without limit.
    static let contextWindow = 20

    mutating func accept(_ turn: ChatTurn) throws {
        try turn.validate()
        if let pendingAnswer { messages.append(ChatMessage(role: .user, text: pendingAnswer)) }
        messages.append(ChatMessage(
            role: .assistant, text: turn.reply, translation: turn.translation,
            correction: pendingAnswer == nil ? nil : turn.correction
        ))
        memory = turn.memory
        pendingAnswer = nil
    }
}

/// Milo's response to a piece of writing the learner submitted.
nonisolated struct WritingFeedback: Codable, Sendable, Equatable {
    /// The learner's text, corrected, in the language being learned.
    var corrected: String
    /// What the text achieved, in the learner's own language.
    var summary: String
    var strengths: [String]
    var nextSteps: [String]
    /// 1–5, deliberately coarse: this is encouragement with evidence, not a grade.
    var score: Int
    /// The one rule most worth taking away, named and explained.
    var ruleTitle: String
    var ruleExplanation: String

    func validate() throws {
        guard !corrected.isEmpty, corrected.count <= 6000,
              !summary.isEmpty, summary.count <= 2000,
              (1...5).contains(score),
              strengths.count <= 5, (1...5).contains(nextSteps.count),
              (strengths + nextSteps).allSatisfy({ !$0.isEmpty && $0.count <= 600 }),
              ruleTitle.count <= 120, ruleExplanation.count <= 1200 else {
            throw LearningValidationError.invalidResponse
        }
    }
}

/// One finished piece of writing and its feedback, saved per language.
nonisolated struct WritingReview: Codable, Identifiable, Sendable, Equatable {
    var id = UUID()
    var createdAt = Date()
    /// The prompt the learner picked, or empty when they wrote freely.
    var prompt = ""
    var text: String
    var feedback: WritingFeedback
}
