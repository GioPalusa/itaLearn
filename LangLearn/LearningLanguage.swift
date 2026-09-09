import AVFoundation
import Foundation
import Speech

/// One language LangLearn can teach, or explain in.
///
/// The list is curated rather than open: every entry names the language in English
/// so the model instructions are never guessing what "sv" or "pt" means, and carries
/// a dictation locale. Speech support is looked up on the device rather than assumed,
/// because a few languages people genuinely want to learn — Icelandic among them —
/// have neither a voice nor a recognizer.
nonisolated struct LearningLanguage: Identifiable, Hashable, Sendable, Codable {
    /// Stored in settings and in `LearnerProfile`, e.g. `"it"`.
    let code: String
    /// Drives speech synthesis and on-device dictation, e.g. `"it-IT"`.
    let localeIdentifier: String
    /// Used inside model instructions, where English names are unambiguous.
    let englishName: String
    let flag: String
    /// How the app itself says hello in this language, so a Mandarin learner is
    /// not greeted in Italian.
    let greeting: String
    /// One spoken sentence, used wherever Milo demonstrates his voice.
    let sampleLine: String
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

    /// Flag and name together, the way every picker and chip shows a language.
    var badge: String { "\(flag) \(displayName)" }
}

// MARK: - What the device can actually do with a language

extension LearningLanguage {
    private static let voiceLanguages: Set<String> = Set(
        AVSpeechSynthesisVoice.speechVoices().map(\.language)
    )
    private static let dictationLanguages: Set<String> = Set(
        SFSpeechRecognizer.supportedLocales().map {
            $0.identifier.replacingOccurrences(of: "_", with: "-")
        }
    )

    private static func supports(_ code: String, in installed: Set<String>) -> Bool {
        installed.contains { $0 == code || $0.hasPrefix(code + "-") }
    }

    /// Whether Milo can read this language out loud on this device.
    var hasVoice: Bool { Self.supports(code, in: Self.voiceLanguages) }
    /// Whether the learner can dictate answers in this language on this device.
    var supportsDictation: Bool { Self.supports(code, in: Self.dictationLanguages) }
}

extension LearningLanguage {
    // MARK: Nordic
    static let swedish = Self(
        code: "sv", localeIdentifier: "sv-SE", englishName: "Swedish", flag: "🇸🇪",
        greeting: "Hej", sampleLine: "Hej! Jag heter Milo. Vi provar tillsammans, ett steg i taget.",
        usageNote: "Watch en/ett gender, definite endings on the noun itself, and verb-second word order."
    )
    static let danish = Self(
        code: "da", localeIdentifier: "da-DK", englishName: "Danish", flag: "🇩🇰",
        greeting: "Hej", sampleLine: "Hej! Jeg hedder Milo. Vi prøver sammen, et skridt ad gangen.",
        usageNote: "Watch en/et gender, definite endings on the noun itself, and verb-second word order."
    )
    static let norwegian = Self(
        code: "nb", localeIdentifier: "nb-NO", englishName: "Norwegian Bokmål", flag: "🇳🇴",
        greeting: "Hei", sampleLine: "Hei! Jeg heter Milo. Vi prøver sammen, ett steg om gangen.",
        usageNote: "Watch en/ei/et gender, definite endings on the noun itself, and verb-second word order."
    )
    static let finnish = Self(
        code: "fi", localeIdentifier: "fi-FI", englishName: "Finnish", flag: "🇫🇮",
        greeting: "Hei", sampleLine: "Hei! Nimeni on Milo. Kokeillaan yhdessä, askel kerrallaan.",
        usageNote: "Finnish has no articles and no grammatical gender; case endings carry the meaning, so watch consonant gradation."
    )
    static let icelandic = Self(
        code: "is", localeIdentifier: "is-IS", englishName: "Icelandic", flag: "🇮🇸",
        greeting: "Halló", sampleLine: "Halló! Ég heiti Milo. Við prófum saman, eitt skref í einu.",
        usageNote: "Four cases and three genders; nouns, adjectives and articles all inflect together."
    )

    // MARK: Western Europe
    static let italian = Self(
        code: "it", localeIdentifier: "it-IT", englishName: "Italian", flag: "🇮🇹",
        greeting: "Ciao", sampleLine: "Ciao! Mi chiamo Milo. Proviamo insieme, un passo alla volta.",
        usageNote: "For wellbeing the natural form is 'Sto bene', not 'Sono bene'. 'Sono buono' means 'I am good/kind', so clarify the intended meaning instead of replacing correct Italian."
    )
    static let spanish = Self(
        code: "es", localeIdentifier: "es-ES", englishName: "Spanish", flag: "🇪🇸",
        greeting: "Hola", sampleLine: "¡Hola! Me llamo Milo. Vamos a intentarlo juntos, paso a paso.",
        usageNote: "Keep ser and estar apart, and keep the personal 'a' before human direct objects."
    )
    static let french = Self(
        code: "fr", localeIdentifier: "fr-FR", englishName: "French", flag: "🇫🇷",
        greeting: "Bonjour", sampleLine: "Bonjour ! Je m'appelle Milo. Essayons ensemble, une étape à la fois.",
        usageNote: "Keep tu and vous consistent with the situation, and match adjectives in gender and number."
    )
    static let german = Self(
        code: "de", localeIdentifier: "de-DE", englishName: "German", flag: "🇩🇪",
        greeting: "Hallo", sampleLine: "Hallo! Ich heiße Milo. Wir versuchen es zusammen, Schritt für Schritt.",
        usageNote: "Keep du and Sie consistent, respect case endings, and keep the finite verb in second position."
    )
    static let english = Self(
        code: "en", localeIdentifier: "en-US", englishName: "English", flag: "🇬🇧",
        greeting: "Hello", sampleLine: "Hello! My name is Milo. Let's try together, one step at a time.",
        usageNote: nil
    )
    static let portuguese = Self(
        code: "pt", localeIdentifier: "pt-BR", englishName: "Brazilian Portuguese", flag: "🇧🇷",
        greeting: "Olá", sampleLine: "Olá! Eu me chamo Milo. Vamos tentar juntos, um passo de cada vez.",
        usageNote: "Everyday address is 'você' with third-person verb forms."
    )
    static let dutch = Self(
        code: "nl", localeIdentifier: "nl-NL", englishName: "Dutch", flag: "🇳🇱",
        greeting: "Hallo", sampleLine: "Hallo! Ik heet Milo. We proberen het samen, stap voor stap.",
        usageNote: "Finite verb second in main clauses and final in subordinate clauses; watch de and het."
    )
    static let catalan = Self(
        code: "ca", localeIdentifier: "ca-ES", englishName: "Catalan", flag: "🇦🇩",
        greeting: "Hola", sampleLine: "Hola! Em dic Milo. Ho provem junts, pas a pas.",
        usageNote: "Watch the weak pronouns (em, et, es, hi, en) and the periphrastic past with 'vaig'."
    )
    static let greek = Self(
        code: "el", localeIdentifier: "el-GR", englishName: "Greek", flag: "🇬🇷",
        greeting: "Γεια σου", sampleLine: "Γεια σου! Με λένε Μίλο. Ας δοκιμάσουμε μαζί, ένα βήμα τη φορά.",
        usageNote: "Give the article with every noun, since it carries gender and case."
    )

    // MARK: Central and Eastern Europe
    static let polish = Self(
        code: "pl", localeIdentifier: "pl-PL", englishName: "Polish", flag: "🇵🇱",
        greeting: "Cześć", sampleLine: "Cześć! Nazywam się Milo. Spróbujmy razem, krok po kroku.",
        usageNote: "Seven cases and verb aspect: pick perfective or imperfective deliberately and say why."
    )
    static let czech = Self(
        code: "cs", localeIdentifier: "cs-CZ", englishName: "Czech", flag: "🇨🇿",
        greeting: "Ahoj", sampleLine: "Ahoj! Jmenuji se Milo. Zkusíme to spolu, krok za krokem.",
        usageNote: "Seven cases and verb aspect; watch the fixed second position of clitics."
    )
    static let slovak = Self(
        code: "sk", localeIdentifier: "sk-SK", englishName: "Slovak", flag: "🇸🇰",
        greeting: "Ahoj", sampleLine: "Ahoj! Volám sa Milo. Skúsime to spolu, krok za krokom.",
        usageNote: "Six cases and verb aspect; watch the rhythmic shortening rule."
    )
    static let croatian = Self(
        code: "hr", localeIdentifier: "hr-HR", englishName: "Croatian", flag: "🇭🇷",
        greeting: "Bok", sampleLine: "Bok! Zovem se Milo. Pokušajmo zajedno, korak po korak.",
        usageNote: "Seven cases and verb aspect; clitics take second position in the clause."
    )
    static let romanian = Self(
        code: "ro", localeIdentifier: "ro-RO", englishName: "Romanian", flag: "🇷🇴",
        greeting: "Salut", sampleLine: "Salut! Mă numesc Milo. Să încercăm împreună, pas cu pas.",
        usageNote: "The definite article attaches to the end of the noun."
    )
    static let hungarian = Self(
        code: "hu", localeIdentifier: "hu-HU", englishName: "Hungarian", flag: "🇭🇺",
        greeting: "Szia", sampleLine: "Szia! Milo vagyok. Próbáljuk meg együtt, lépésről lépésre.",
        usageNote: "Vowel harmony governs endings, and definite versus indefinite conjugation is not optional."
    )
    static let russian = Self(
        code: "ru", localeIdentifier: "ru-RU", englishName: "Russian", flag: "🇷🇺",
        greeting: "Привет", sampleLine: "Привет! Меня зовут Мило. Давай попробуем вместе, шаг за шагом.",
        usageNote: "Six cases and verb aspect; mark the stressed vowel when a word is new."
    )
    static let ukrainian = Self(
        code: "uk", localeIdentifier: "uk-UA", englishName: "Ukrainian", flag: "🇺🇦",
        greeting: "Привіт", sampleLine: "Привіт! Мене звати Міло. Спробуймо разом, крок за кроком.",
        usageNote: "Seven cases and verb aspect; mark the stressed vowel when a word is new."
    )
    static let turkish = Self(
        code: "tr", localeIdentifier: "tr-TR", englishName: "Turkish", flag: "🇹🇷",
        greeting: "Merhaba", sampleLine: "Merhaba! Benim adım Milo. Birlikte deneyelim, adım adım.",
        usageNote: "Agglutinative suffixes in a fixed order, governed by vowel harmony."
    )

    // MARK: Middle East and Asia
    static let arabic = Self(
        code: "ar", localeIdentifier: "ar-SA", englishName: "Modern Standard Arabic", flag: "🇸🇦",
        greeting: "مرحبا", sampleLine: "مرحبا! اسمي ميلو. لنجرب معًا، خطوة بخطوة.",
        usageNote: "Write right-to-left, and add short vowels when a word or form is new."
    )
    static let hebrew = Self(
        code: "he", localeIdentifier: "he-IL", englishName: "Hebrew", flag: "🇮🇱",
        greeting: "שלום", sampleLine: "שלום! קוראים לי מילו. ננסה יחד, צעד אחר צעד.",
        usageNote: "Write right-to-left; verbs follow root-and-binyan patterns, and gender marks the verb too."
    )
    static let hindi = Self(
        code: "hi", localeIdentifier: "hi-IN", englishName: "Hindi", flag: "🇮🇳",
        greeting: "नमस्ते", sampleLine: "नमस्ते! मेरा नाम मिलो है। चलिए साथ मिलकर कोशिश करते हैं, एक कदम एक बार।",
        usageNote: "Postpositions rather than prepositions, and gender agreement reaches the verb."
    )
    static let japanese = Self(
        code: "ja", localeIdentifier: "ja-JP", englishName: "Japanese", flag: "🇯🇵",
        greeting: "こんにちは", sampleLine: "こんにちは！ミロです。一緒に少しずつ練習しましょう。",
        usageNote: "Hold one politeness level per scene (です/ます unless the situation calls for plain form) and use the right counters."
    )
    static let korean = Self(
        code: "ko", localeIdentifier: "ko-KR", englishName: "Korean", flag: "🇰🇷",
        greeting: "안녕하세요", sampleLine: "안녕하세요! 저는 밀로예요. 함께 한 걸음씩 해봐요.",
        usageNote: "Hold one speech level per scene (해요체 unless the situation calls for another) and watch subject and topic particles."
    )
    static let mandarin = Self(
        code: "zh", localeIdentifier: "zh-CN", englishName: "Mandarin Chinese", flag: "🇨🇳",
        greeting: "你好", sampleLine: "你好！我叫米洛。我们一起一步一步来吧。",
        usageNote: "Give pinyin with tone marks alongside characters when explaining, and use the right measure words."
    )
    static let thai = Self(
        code: "th", localeIdentifier: "th-TH", englishName: "Thai", flag: "🇹🇭",
        greeting: "สวัสดี", sampleLine: "สวัสดี! ผมชื่อไมโล มาลองไปด้วยกันทีละขั้นนะ",
        usageNote: "Five tones and no spaces between words; keep the polite particle consistent with the speaker."
    )
    static let vietnamese = Self(
        code: "vi", localeIdentifier: "vi-VN", englishName: "Vietnamese", flag: "🇻🇳",
        greeting: "Xin chào", sampleLine: "Xin chào! Tôi tên là Milo. Chúng ta cùng thử nhé, từng bước một.",
        usageNote: "Six tones marked by diacritics, and the pronoun depends on the relative age of the speakers."
    )
    static let indonesian = Self(
        code: "id", localeIdentifier: "id-ID", englishName: "Indonesian", flag: "🇮🇩",
        greeting: "Halo", sampleLine: "Halo! Nama saya Milo. Ayo kita coba bersama, selangkah demi selangkah.",
        usageNote: "No tense or plural inflection; affixes such as me-, ber- and -kan carry the work."
    )
    static let malay = Self(
        code: "ms", localeIdentifier: "ms-MY", englishName: "Malay", flag: "🇲🇾",
        greeting: "Helo", sampleLine: "Helo! Nama saya Milo. Mari kita cuba bersama, langkah demi langkah.",
        usageNote: "No tense or plural inflection; reduplication marks plurality where it matters."
    )

    /// Every language that can be picked, in a stable declaration order.
    static let catalog: [Self] = [
        .swedish, .danish, .norwegian, .finnish, .icelandic,
        .italian, .spanish, .french, .german, .english, .portuguese, .dutch, .catalan, .greek,
        .polish, .czech, .slovak, .croatian, .romanian, .hungarian, .russian, .ukrainian, .turkish,
        .arabic, .hebrew, .hindi, .japanese, .korean, .mandarin, .thai, .vietnamese, .indonesian, .malay
    ]

    /// The order pickers use: alphabetical in the language the UI is written in,
    /// because a list this long is only findable when it is sorted the reader's way.
    static var pickerOrder: [Self] {
        catalog.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    static func named(_ code: String) -> Self? {
        catalog.first { $0.code == code }
    }

    /// The catalog language closest to the device, for a sensible explanation language.
    static func matchingDevice(fallback: Self) -> Self {
        let preferred = Locale.preferredLanguages
            .compactMap { Locale(identifier: $0).language.languageCode?.identifier }
        for code in preferred {
            // Norwegian reaches us as "no" or "nn" at least as often as "nb".
            if code == "no" || code == "nn" { return .norwegian }
            if let match = named(code) { return match }
        }
        return fallback
    }
}

/// What the learner is studying, and which language it is explained in.
///
/// There is deliberately no default pairing: the app teaches nothing until the
/// learner has picked a language.
nonisolated struct LanguageCourse: Hashable, Sendable, Encodable {
    var target: LearningLanguage
    var native: LearningLanguage

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
