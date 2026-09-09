import Foundation
import SwiftUI

/// Explicit parsing is needed for model strings: Text(String) renders Markdown markers literally.
nonisolated enum LearningMarkdown {
    static func attributed(_ source: String) -> AttributedString {
        let text = LessonDialogue.normalized(source)
        var output = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        highlightQuotations(in: &output)
        return output
    }

    /// Italian inside « » or " " is what the learner is meant to say, so it is set
    /// apart from the Swedish explanation around it.
    private static func highlightQuotations(in text: inout AttributedString) {
        for (open, close) in [(Character("«"), Character("»")), (Character("\""), Character("\""))] {
            var searchFrom = text.startIndex
            while searchFrom < text.endIndex,
                  let start = text[searchFrom...].range(of: String(open)),
                  let end = text[start.upperBound...].range(of: String(close)) {
                let span = start.lowerBound..<end.upperBound
                text[span].foregroundColor = ItaLearn.purple
                text[span].inlinePresentationIntent = .stronglyEmphasized
                searchFrom = end.upperBound
            }
        }
    }

    static func spoken(_ source: String) -> String { String(attributed(source).characters) }

    struct Change: Equatable {
        enum Kind { case unchanged, removed, added }
        var text: String
        var kind: Kind
    }

    /// Exact token comparison preserves accent, casing and punctuation corrections as well as words.
    static func changes(original: String, corrected: String) -> [Change] {
        let old = spoken(original).split(whereSeparator: \.isWhitespace).map(String.init)
        let new = spoken(corrected).split(whereSeparator: \.isWhitespace).map(String.init)
        // Bound work for unexpected model output; normal exercise sentences are much shorter.
        guard old.count <= 400, new.count <= 400 else {
            return [.init(text: spoken(original), kind: .removed), .init(text: spoken(corrected), kind: .added)]
        }
        var lengths = Array(repeating: Array(repeating: 0, count: new.count + 1), count: old.count + 1)
        for i in old.indices.reversed() {
            for j in new.indices.reversed() {
                lengths[i][j] = old[i] == new[j] ? lengths[i+1][j+1] + 1 : max(lengths[i+1][j], lengths[i][j+1])
            }
        }
        var output: [Change] = []
        var i = 0, j = 0
        while i < old.count || j < new.count {
            if i < old.count, j < new.count, old[i] == new[j] {
                output.append(.init(text: new[j], kind: .unchanged)); i += 1; j += 1
            } else if i < old.count, j == new.count || lengths[i+1][j] >= lengths[i][j+1] {
                output.append(.init(text: old[i], kind: .removed)); i += 1
            } else {
                output.append(.init(text: new[j], kind: .added)); j += 1
            }
        }
        return output
    }

    static func correction(original: String, corrected: String) -> AttributedString {
        var output = AttributedString()
        for change in changes(original: original, corrected: corrected) {
            if !output.characters.isEmpty { output.append(AttributedString(" ")) }
            var token = AttributedString(change.text)
            switch change.kind {
            case .unchanged: break
            case .removed: token.strikethroughStyle = Text.LineStyle(pattern: .solid)
            case .added: token.inlinePresentationIntent = .stronglyEmphasized
            }
            output.append(token)
        }
        return output
    }
}

struct LearningMarkdownText: View {
    let source: String
    init(_ source: String) { self.source = source }
    var body: some View {
        let dialogue = LessonDialogue.lines(source)
        if LessonDialogue.isConversation(dialogue) {
            LessonDialogueView(lines: dialogue)
        } else {
            prose
        }
    }

    private var prose: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(source.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                if line.hasPrefix("### ") {
                    Text(LearningMarkdown.attributed(String(line.dropFirst(4)))).font(.headline)
                } else if line.hasPrefix("## ") {
                    Text(LearningMarkdown.attributed(String(line.dropFirst(3)))).font(.title3.bold())
                } else if line.hasPrefix("# ") {
                    Text(LearningMarkdown.attributed(String(line.dropFirst(2)))).font(.title2.bold())
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    Text(LearningMarkdown.attributed("• " + line.dropFirst(2)))
                } else if line.hasPrefix("> ") {
                    Text(LearningMarkdown.attributed(String(line.dropFirst(2)))).italic().padding(.leading, 12)
                } else if line.hasPrefix("```") {
                    EmptyView()
                } else if line.isEmpty {
                    Color.clear.frame(height: 6)
                } else {
                    Text(LearningMarkdown.attributed(line))
                }
            }
        }.textSelection(.enabled)
    }
}
