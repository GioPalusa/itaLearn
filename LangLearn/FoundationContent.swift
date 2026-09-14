import Foundation

/// Small, explicit inventories constrain script lessons. They are introductions, not a complete
/// orthography course. Never synthesize isolated phonemes: demonstrate letters inside whole words.
nonisolated struct FoundationInventory: Encodable, Sendable {
    var script: String
    var units: [String]
    var guidance: String

    static func forLanguage(_ language: LearningLanguage) -> Self {
        switch language.code {
        case "ja": return .init(script: "Japanese kana", units: Array("あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをんアイウエオカキクケコ").map(String.init), guidance: "Start with 2–3 hiragana per pack, then review. Kana represent morae, not alphabet letters. Teach katakana later. Do not invent kanji readings or stroke-order animations.")
        case "zh": return .init(script: "Simplified Chinese characters", units: ["人", "口", "日", "月", "山", "水", "火", "木", "一", "二", "三", "大", "小", "你", "好"], guidance: "Characters are not an alphabet. Teach meaning in familiar whole words with pinyin tone marks as optional support. Audio must be a whole Mandarin word, never a claimed isolated phoneme.")
        case "ko": return .init(script: "Hangul", units: ["가", "나", "다", "마", "바", "사", "아", "오", "우", "이", "고", "구", "기", "ㄱ", "ㄴ", "ㅁ", "ㅅ", "ㅇ", "ㅏ", "ㅗ", "ㅜ", "ㅣ"], guidance: "Introduce easy complete syllable blocks first, then show how consonant and vowel jamo combine. Do not treat a block as one alphabet letter.")
        case "ar": return .init(script: "Arabic", units: Array("ابتثجحخدذرزسشصضطظعغفقكلمنهوي").map(String.init), guidance: "Right-to-left. Show contextual connected forms inside whole words. Add short vowels to new words. Do not claim isolated-letter TTS demonstrates its phoneme.")
        case "he": return .init(script: "Hebrew", units: Array("אבגדהוזחטיכלמנסעפצקרשתךםןףץ").map(String.init), guidance: "Right-to-left. Introduce final forms with words. Add niqqud in beginner examples where useful. Distinguish the letter name from its sound.")
        case "hi": return .init(script: "Devanagari", units: ["अ", "आ", "इ", "ई", "उ", "ऊ", "ए", "ऐ", "ओ", "औ", "क", "ख", "ग", "च", "ज", "ट", "त", "द", "न", "प", "ब", "म", "य", "र", "ल", "व", "स", "ह"], guidance: "Introduce independent vowels and simple consonants in whole words before vowel signs and conjuncts. Explain the inherent vowel rather than calling every unit an alphabet letter.")
        case "th": return .init(script: "Thai", units: ["ก", "ข", "ค", "ง", "จ", "ช", "ด", "ต", "ท", "น", "บ", "ป", "พ", "ม", "ย", "ร", "ล", "ว", "ส", "ห", "อ"], guidance: "Introduce consonants inside familiar syllables. Vowel placement and consonant class affect reading; don't claim a letter alone determines tone. Use whole-word audio.")
        case "el": return .init(script: "Greek", units: Array("αβγδεζηθικλμνξοπρστυφχψω").map(String.init), guidance: "Modern Greek pronunciation. Introduce lowercase first and final sigma in context. Add stress marks to example words.")
        case "ru": return .init(script: "Russian Cyrillic", units: Array("абвгдеёжзийклмнопрстуфхцчшщъыьэюя").map(String.init), guidance: "Use Russian whole-word audio. Distinguish Cyrillic lookalikes from Latin letters; soft/hard signs are not independent sounds.")
        case "uk": return .init(script: "Ukrainian Cyrillic", units: Array("абвгґдеєжзиіїйклмнопрстуфхцчшщьюя").map(String.init), guidance: "Use Ukrainian pronunciation, including і, ї, є and ґ. Do not substitute Russian sound values.")
        default:
            let extra: String
            switch language.code {
            case "sv", "fi": extra = "åäö"
            case "da", "nb": extra = "æøå"
            case "is": extra = "áéíóúýðþæö"
            case "tr": extra = "çğıöşü"
            case "vi": extra = "ăâđêôơư"
            case "pl": extra = "ąćęłńóśźż"
            case "cs": extra = "áčďéěíňóřšťúůýž"
            case "sk": extra = "áäčďéíĺľňóôŕšťúýž"
            case "hr": extra = "čćđšž"
            case "hu": extra = "áéíóöőúüű"
            case "ro": extra = "ăâîșț"
            case "de": extra = "äöüß"
            case "fr": extra = "àâæçéèêëîïôœùûüÿ"
            case "es": extra = "áéíñóúü"
            case "it": extra = "àèéìòóù"
            case "pt": extra = "áâãàçéêíóôõú"
            case "ca": extra = "àçèéíïòóúü"
            case "nl": extra = "áéëïóöü"
            default: extra = ""
            }
            return .init(script: "Latin script used for \(language.englishName)", units: Array("abcdefghijklmnopqrstuvwxyz" + extra).map(String.init), guidance: "Use this language's letter-to-sound relationships, not English alphabet pronunciations. Teach 2–3 useful units in whole words and meaningful phrases. A shared Latin alphabet does not imply known pronunciation. Vietnamese tones must remain marked.")
        }
    }
}

/// An immediate, network-free first success for the app's Swedish UI and English explanations.
/// Other explanation languages use the same guided engine with a validated generated pack.
nonisolated enum FoundationContent {
    static func welcome(course: LanguageCourse) -> JourneyPack? {
        guard ["sv", "en"].contains(course.native.code) else { return nil }
        let sv = course.native.code == "sv"
        let greeting = course.target.greeting
        let translation = sv ? "Hej" : "Hello"
        let example = JourneyStep(id: "welcome-example", kind: .example, skill: .reading,
            skillID: "greetings.hello", skillTitle: sv ? "Hälsa på någon" : "Greet someone",
            instruction: sv ? "Milo hälsar på dig. Lyssna och prova när du vill." : "Milo is saying hello. Listen and try when you feel ready.",
            target: greeting, translation: translation, audioText: greeting,
            choices: [], correctChoiceID: "", tokens: [], acceptedAnswers: [],
            hints: [sv ? "Vi börjar med en hälsning." : "We are starting with a greeting."],
            explanation: sv ? "Du kan använda det här uttrycket för att hälsa. Vi börjar med att känna igen det." : "You can use this expression to greet someone. First, let's recognize it.")
        var recognize = example
        recognize.id = "welcome-meaning"; recognize.kind = .meaningChoice
        recognize.instruction = sv ? "Vad betyder hälsningen? Du kan lyssna på alternativen." : "What does the greeting mean? You can listen to the options."
        recognize.choices = [.init(id: "hello", text: sv ? "Hej 👋" : "Hello 👋"), .init(id: "thanks", text: sv ? "Tack 🙏" : "Thank you 🙏")]
        recognize.correctChoiceID = "hello"
        var say = example
        say.id = "welcome-say"; say.kind = .say; say.skill = .speaking
        say.instruction = sv ? "Lyssna igen och prova att hälsa. Du behöver inte spela in något." : "Listen again and try saying hello. You don't need to record yourself."
        say.explanation = sv ? "Det här är ett tillfälle att prova, inte ett uttalsprov." : "This is a chance to try, not a pronunciation test."
        return JourneyPack(schemaVersion: 1, targetLanguage: course.target.code, explanationLanguage: course.native.code,
            track: .foundations, title: sv ? "Din första hälsning" : "Your first greeting",
            reason: sv ? "Du börjar med ett användbart uttryck. Inga förkunskaper eller skrivna svar behövs." : "Start with one useful expression. No prior knowledge or written answers needed.",
            steps: [example, recognize, say])
    }
}
