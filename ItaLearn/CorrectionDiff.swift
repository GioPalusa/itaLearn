import SwiftUI

/// Word-level diff between what the learner wrote and the teacher's correction,
/// rendered inline the way Writing Tools shows a rewrite: removals struck
/// through in red, additions underlined on green.
enum CorrectionDiff {
    enum Kind {
        case unchanged
        case removed
        case added
    }

    struct Token: Equatable {
        let text: String
        let kind: Kind

        static func == (lhs: Token, rhs: Token) -> Bool {
            lhs.text == rhs.text && lhs.kind == rhs.kind
        }
    }

    /// Words match on their letters alone, so punctuation and casing changes
    /// ride along with the word instead of showing as separate edits.
    private static func matchKey(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func tokens(original: String, corrected: String) -> [Token] {
        let old = original.split(whereSeparator: \.isWhitespace).map(String.init)
        let new = corrected.split(whereSeparator: \.isWhitespace).map(String.init)

        guard !old.isEmpty else { return new.map { Token(text: $0, kind: .added) } }
        guard !new.isEmpty else { return old.map { Token(text: $0, kind: .removed) } }

        let oldKeys = old.map(matchKey)
        let newKeys = new.map(matchKey)

        // Longest common subsequence over word keys.
        var lengths = Array(
            repeating: Array(repeating: 0, count: new.count + 1),
            count: old.count + 1
        )
        for i in stride(from: old.count - 1, through: 0, by: -1) {
            for j in stride(from: new.count - 1, through: 0, by: -1) {
                lengths[i][j] = oldKeys[i] == newKeys[j]
                    ? lengths[i + 1][j + 1] + 1
                    : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }

        var tokens: [Token] = []
        var i = 0
        var j = 0
        while i < old.count, j < new.count {
            if oldKeys[i] == newKeys[j] {
                // Keep the corrected spelling — it carries the fixed punctuation.
                tokens.append(Token(text: new[j], kind: .unchanged))
                i += 1
                j += 1
            } else if lengths[i + 1][j] >= lengths[i][j + 1] {
                // Ties favour a removal, so a replacement reads
                // "struck-through original, then correction".
                tokens.append(Token(text: old[i], kind: .removed))
                i += 1
            } else {
                tokens.append(Token(text: new[j], kind: .added))
                j += 1
            }
        }
        while i < old.count {
            tokens.append(Token(text: old[i], kind: .removed))
            i += 1
        }
        while j < new.count {
            tokens.append(Token(text: new[j], kind: .added))
            j += 1
        }

        return tokens
    }

    /// Styled text for the "Rättat i din text" card.
    static func attributedText(original: String, corrected: String) -> AttributedString {
        var output = AttributedString()

        for (index, token) in tokens(original: original, corrected: corrected).enumerated() {
            if index > 0 {
                output.append(AttributedString(" "))
            }

            var piece = AttributedString(token.text)
            switch token.kind {
            case .unchanged:
                piece.foregroundColor = ItaLearn.ink
            case .removed:
                piece.foregroundColor = .black.opacity(0.35)
                piece.strikethroughStyle = Text.LineStyle(pattern: .solid, color: ItaLearn.red)
            case .added:
                piece.foregroundColor = ItaLearn.ink
                piece.backgroundColor = ItaLearn.green.opacity(0.16)
                piece.underlineStyle = Text.LineStyle(pattern: .solid, color: ItaLearn.green)
            }
            output.append(piece)
        }

        return output
    }
}
