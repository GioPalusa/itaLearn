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
    var swedish: String
    var italian: String
    var example: String
}

nonisolated struct SentencePuzzle: Codable, Identifiable, Sendable, Equatable {
    var id: String
    var swedish: String
    /// Alternatives must be constructible using the same word bank, including repeated words.
    var answers: [[String]]
    var words: [String]
    var explanation: String

    func matches(_ selected: [String]) -> Bool {
        answers.contains { $0.map(Self.normalized) == selected.map(Self.normalized) }
    }

    static func normalized(_ word: String) -> String {
        word.lowercased().replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;: "))
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
            guard [card.id, card.swedish, card.italian, card.example].allSatisfy({ !$0.isEmpty && $0.count <= 800 }) else {
                throw LearningValidationError.invalidResponse
            }
        }
        for puzzle in puzzles {
            guard !puzzle.id.isEmpty, !puzzle.swedish.isEmpty, puzzle.swedish.count <= 800,
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

nonisolated struct PracticeProgress: Codable, Sendable {
    var pack: PracticePack
    var knownCardIDs: Set<String> = []
    var solvedPuzzleIDs: Set<String> = []
}

/// Tile identity is its original bank index, so duplicate words remain independently movable.
nonisolated struct WordAssembly: Equatable {
    private(set) var selected: [Int] = []

    mutating func place(_ tile: Int, before destination: Int? = nil, wordCount: Int) {
        guard (0..<wordCount).contains(tile), tile != destination else { return }
        selected.removeAll { $0 == tile }
        if let destination, let index = selected.firstIndex(of: destination) { selected.insert(tile, at: index) }
        else { selected.append(tile) }
    }

    mutating func remove(_ tile: Int) { selected.removeAll { $0 == tile } }
    mutating func reset() { selected = [] }
    func words(in puzzle: SentencePuzzle) -> [String] { selected.compactMap { puzzle.words.indices.contains($0) ? puzzle.words[$0] : nil } }
}
