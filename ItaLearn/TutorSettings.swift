import Foundation
import Observation

enum TeacherTone: String, CaseIterable, Identifiable, Sendable {
    case warm
    case direct
    case upbeat

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .warm: "Varm"
        case .direct: "Rak"
        case .upbeat: "Peppig"
        }
    }

    /// The sample line shown under the tone picker in Inställningar.
    var sample: LocalizedStringResource {
        switch self {
        case .warm: "\"Fint jobbat med artigheten — nu tar vi priserna.\""
        case .direct: "\"Artigheten sitter. Nästa steg: fråga om priset.\""
        case .upbeat: "\"Snyggt! Artigheten är i hamn — nu kör vi på priserna!\""
        }
    }

    /// Appended to the tutor's system instructions.
    var modelInstruction: String {
        switch self {
        case .warm:
            "Use a warm, encouraging voice. Lead with what went well before suggesting a change."
        case .direct:
            "Use a calm, matter-of-fact voice. Be brief and concrete, and skip praise that is not earned."
        case .upbeat:
            "Use an energetic, cheerful voice. Celebrate progress, but never exaggerate what the learner got right."
        }
    }
}

enum ProficiencyLevel: String, CaseIterable, Identifiable, Sendable {
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"

    var id: String { rawValue }

    var caption: LocalizedStringResource {
        switch self {
        case .a1: "Nybörjare"
        case .a2: "Lite van"
        case .b1: "Klarar mig"
        }
    }

    var modelDescription: String {
        switch self {
        case .a1: "CEFR A1 (complete beginner)"
        case .a2: "CEFR A2 (elementary)"
        case .b1: "CEFR B1 (intermediate)"
        }
    }
}

/// User-facing preferences from screen 2f. Persisted in `UserDefaults`.
@Observable
final class TutorSettings {
    /// Legacy catalog progress scale; OpenAI usage is governed by the user's API account.
    static let dailyReviewAllowance = 12

    private enum Key {
        static let tone = "tutor.tone"
        static let level = "tutor.level"
        static let correctsSpelling = "tutor.correctsSpelling"
        static let dailyReminder = "tutor.dailyReminder"
        static let reminderTime = "tutor.reminderTime"
        static let hasOnboarded = "tutor.hasOnboarded"
        static let learnerName = "tutor.learnerName"
    }

    private let store: UserDefaults

    var tone: TeacherTone { didSet { store.set(tone.rawValue, forKey: Key.tone) } }
    var level: ProficiencyLevel { didSet { store.set(level.rawValue, forKey: Key.level) } }
    var correctsSpelling: Bool { didSet { store.set(correctsSpelling, forKey: Key.correctsSpelling) } }
    var dailyReminder: Bool { didSet { store.set(dailyReminder, forKey: Key.dailyReminder) } }
    var hasOnboarded: Bool { didSet { store.set(hasOnboarded, forKey: Key.hasOnboarded) } }
    var learnerName: String { didSet { store.set(learnerName, forKey: Key.learnerName) } }

    /// Minutes past midnight, so the reminder time survives as a plain integer.
    var reminderMinutes: Int { didSet { store.set(reminderMinutes, forKey: Key.reminderTime) } }

    init(store: UserDefaults = .standard) {
        self.store = store
        tone = (store.string(forKey: Key.tone).flatMap(TeacherTone.init)) ?? .warm
        level = (store.string(forKey: Key.level).flatMap(ProficiencyLevel.init)) ?? .a1
        correctsSpelling = store.object(forKey: Key.correctsSpelling) as? Bool ?? true
        dailyReminder = store.object(forKey: Key.dailyReminder) as? Bool ?? true
        reminderMinutes = store.object(forKey: Key.reminderTime) as? Int ?? (8 * 60 + 15)
        hasOnboarded = store.bool(forKey: Key.hasOnboarded)
        learnerName = store.string(forKey: Key.learnerName) ?? ""
    }

    var reminderDate: Date {
        get {
            Calendar.current.date(
                bySettingHour: reminderMinutes / 60,
                minute: reminderMinutes % 60,
                second: 0,
                of: .now
            ) ?? .now
        }
        set {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            reminderMinutes = (parts.hour ?? 8) * 60 + (parts.minute ?? 15)
        }
    }

    var reminderText: String {
        String(format: "%02d:%02d", reminderMinutes / 60, reminderMinutes % 60)
    }

    /// Two-letter monogram for the home-screen avatar.
    var initials: String {
        let parts = learnerName
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap(\.first)
        return parts.isEmpty ? "IT" : parts.map { String($0).uppercased() }.joined()
    }

    var greetingName: String? {
        let trimmed = learnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }
}
