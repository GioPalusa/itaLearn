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
