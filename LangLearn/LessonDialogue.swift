import Foundation
import SwiftUI

/// Turns model prose into displayable lines.
///
/// The teacher writes conversations in whatever shape the model chose: guillemets,
/// ASCII `<<` `>>`, straight quotes, `Namn:` prefixes or em-dash turns. This finds
/// the structure so a dialogue can be shown as one, instead of as a wall of text.
nonisolated enum LessonDialogue {
    struct Line: Identifiable, Equatable {
        let id: Int
        /// nil for narration or instructions around the conversation.
        var speaker: String?
        var text: String
    }

    /// The model often approximates guillemets with ASCII angle brackets.
    static func normalized(_ source: String) -> String {
        source
            .replacingOccurrences(of: "<<", with: "«")
            .replacingOccurrences(of: ">>", with: "»")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
    }

    private static let speakerPattern = /^\s*(?:[-—–]\s*)?(?:\*\*)?\s*([\p{L}][\p{L} '’.-]{0,23})\s*(?:\*\*)?\s*:\s+(\S.*)$/

    /// A bare em-dash turn, the other common way the model writes conversation.
    private static let dashPattern = /^\s*[—–]\s+(\S.*)$/

    static func lines(_ source: String) -> [Line] {
        normalized(source)
            .components(separatedBy: "\n")
            .enumerated()
            .map { index, raw in
                if let match = raw.wholeMatch(of: speakerPattern) {
                    return Line(id: index, speaker: String(match.1).trimmingCharacters(in: .whitespaces),
                                text: String(match.2))
                }
                if let match = raw.wholeMatch(of: dashPattern) {
                    return Line(id: index, speaker: "", text: String(match.1))
                }
                return Line(id: index, speaker: nil, text: raw)
            }
    }

    /// True when the block reads as a conversation rather than labelled prose.
    ///
    /// Labels like `Mål:` or `Tips:` also match the speaker shape, so a dialogue must
    /// either have a speaker who takes more than one turn, or consist only of turns.
    static func isConversation(_ lines: [Line]) -> Bool {
        let turns = lines.filter { $0.speaker != nil }
        guard turns.count >= 2 else { return false }

        if turns.contains(where: { $0.speaker?.isEmpty == true }) { return true }

        let names = turns.compactMap(\.speaker)
        let distinct = Set(names)
        guard (2...4).contains(distinct.count) else { return false }

        let repeats = distinct.contains { name in names.filter { $0 == name }.count > 1 }
        let everyLineIsATurn = lines.allSatisfy { $0.speaker != nil || $0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        return repeats || everyLineIsATurn
    }

    /// Stable colour per speaker so the same voice reads the same way throughout.
    static func colors(for lines: [Line]) -> [String: Color] {
        let palette = [LangLearn.purple, LangLearn.magenta, LangLearn.cyan, LangLearn.deepGreen]
        var assigned: [String: Color] = [:]
        for name in lines.compactMap(\.speaker) where assigned[name] == nil {
            assigned[name] = palette[assigned.count % palette.count]
        }
        return assigned
    }
}

/// One conversation, with each turn attributed to a speaker.
struct LessonDialogueView: View {
    let lines: [LessonDialogue.Line]

    private var colors: [String: Color] { LessonDialogue.colors(for: lines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(lines) { line in
                if let speaker = line.speaker {
                    turn(speaker: speaker, text: line.text)
                } else if !line.text.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(LearningMarkdown.attributed(line.text))
                        .font(.callout)
                        .foregroundStyle(LangLearn.inkSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private func turn(speaker: String, text: String) -> some View {
        let tint = speaker.isEmpty ? LangLearn.purple : (colors[speaker] ?? LangLearn.purple)
        return HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                if !speaker.isEmpty {
                    Text(speaker)
                        .font(.il(12, .semibold))
                        .foregroundStyle(tint)
                }
                Text(LearningMarkdown.attributed(text))
                    .foregroundStyle(LangLearn.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(tint.opacity(0.06), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(speaker.isEmpty ? text : "\(speaker) säger: \(text)")
    }
}
