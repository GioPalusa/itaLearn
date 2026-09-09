import Foundation

/// One language LangLearn can teach, or explain in.
///
/// The list is curated rather than open: every entry needs a speech voice and a
/// dictation locale, and the model instructions name the language in English so
/// the tutor is never guessing what "sv" or "pt" means.
nonisolated struct LearningLanguage: Identifiable, Hashable, Sendable, Codable {
    /// Stored in settings and in `LearnerProfile`, e.g. `"it"`.
    let code: String
    /// Drives speech synthesis and on-device dictation, e.g. `"it-IT"`.
    let localeIdentifier: String
    /// Used inside model instructions, where English names are unambiguous.
    let englishName: String
    let flag: String
    /// A short, language-specific correction habit worth handing the tutor.
    let usageNote: String?

    var id: String { code }
    var locale: Locale { Locale(identifier: localeIdentifier) }

    /// Named in the language the app's own strings are written in, so an
    /// interpolated name matches the sentence around it: "Italienska" in the
    /// Swedish UI, not "Italian" just because the device is set to English.
    private static let uiLocale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "sv")

    var displayName: String {
        let name = Self.uiLocale.localizedString(forLanguageCode: code) ?? englishName
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}

extension LearningLanguage {
    static let italian = Self(
        code: "it", localeIdentifier: "it-IT", englishName: "Italian", flag: "🇮🇹",
        usageNote: "For wellbeing the natural form is 'Sto bene', not 'Sono bene'. 'Sono buono' means 'I am good/kind', so clarify the intended meaning instead of replacing correct Italian."
    )
    static let spanish = Self(
        code: "es", localeIdentifier: "es-ES", englishName: "Spanish", flag: "🇪🇸",
        usageNote: "Keep ser and estar apart, and keep the personal 'a' before human direct objects."
    )
    static let french = Self(
        code: "fr", localeIdentifier: "fr-FR", englishName: "French", flag: "🇫🇷",
        usageNote: "Keep tu and vous consistent with the situation, and match adjectives in gender and number."
    )
    static let german = Self(
        code: "de", localeIdentifier: "de-DE", englishName: "German", flag: "🇩🇪",
        usageNote: "Keep du and Sie consistent, respect case endings, and keep the finite verb in second position."
    )
    static let english = Self(
        code: "en", localeIdentifier: "en-US", englishName: "English", flag: "🇬🇧", usageNote: nil
    )
    static let portuguese = Self(
        code: "pt", localeIdentifier: "pt-BR", englishName: "Brazilian Portuguese", flag: "🇧🇷",
        usageNote: "Everyday address is 'você' with third-person verb forms."
    )
    static let dutch = Self(
        code: "nl", localeIdentifier: "nl-NL", englishName: "Dutch", flag: "🇳🇱",
        usageNote: "Finite verb second in main clauses and final in subordinate clauses; watch de and het."
    )
    static let swedish = Self(
        code: "sv", localeIdentifier: "sv-SE", englishName: "Swedish", flag: "🇸🇪",
        usageNote: "Watch en/ett gender, definite endings on the noun itself, and verb-second word order."
    )
    static let danish = Self(
        code: "da", localeIdentifier: "da-DK", englishName: "Danish", flag: "🇩🇰",
        usageNote: "Watch en/et gender, definite endings on the noun itself, and verb-second word order."
    )
    static let japanese = Self(
        code: "ja", localeIdentifier: "ja-JP", englishName: "Japanese", flag: "🇯🇵",
        usageNote: "Hold one politeness level per scene (です/ます unless the situation calls for plain form) and use the right counters."
    )
    static let korean = Self(
        code: "ko", localeIdentifier: "ko-KR", englishName: "Korean", flag: "🇰🇷",
        usageNote: "Hold one speech level per scene (해요체 unless the situation calls for another) and watch subject and topic particles."
    )
    static let mandarin = Self(
        code: "zh", localeIdentifier: "zh-CN", englishName: "Mandarin Chinese", flag: "🇨🇳",
        usageNote: "Give pinyin with tone marks alongside characters when explaining, and use the right measure words."
    )

    /// Offered in the pickers, in the order they appear there.
    static let catalog: [Self] = [
        .italian, .spanish, .french, .german, .english, .portuguese,
        .dutch, .swedish, .danish, .japanese, .korean, .mandarin
    ]

    static func named(_ code: String) -> Self? {
        catalog.first { $0.code == code }
    }

    /// The catalog language closest to the device, for a sensible first pick.
    static func matchingDevice(fallback: Self) -> Self {
        let preferred = Locale.preferredLanguages
            .compactMap { Locale(identifier: $0).language.languageCode?.identifier }
        for code in preferred {
            if let match = named(code) { return match }
        }
        return fallback
    }
}

/// What the learner is studying, and which language it is explained in.
nonisolated struct LanguageCourse: Hashable, Sendable, Encodable {
    var target: LearningLanguage
    var native: LearningLanguage

    /// Italian explained in Swedish: what every study saved before language
    /// selection existed was created as.
    static let `default` = Self(target: .italian, native: .swedish)

    /// Names the model reads, kept in English so they cannot be misread.
    var targetName: String { target.englishName }
    var nativeName: String { native.englishName }

    /// The opening paragraph shared by every request to the tutor.
    var promptPreamble: String {
        var lines = """
        You teach \(targetName) to a \(nativeName)-speaking learner. All explanations, translations,
        plan titles, summaries and rationale must be written in \(nativeName). Example sentences,
        vocabulary and conversation lines are in \(targetName).
        """
        if let note = target.usageNote {
            lines += "\n\(targetName) usage to hold on to: \(note)"
        }
        return lines
    }

    enum CodingKeys: String, CodingKey { case targetLanguage, explanationLanguage }

    /// Encoded for the request body so the model sees the pairing as data too.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targetName, forKey: .targetLanguage)
        try container.encode(nativeName, forKey: .explanationLanguage)
    }
}
