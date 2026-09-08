import Foundation

struct WritingLesson: Identifiable, Sendable {
    let id: String
    let number: Int
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let goal: LocalizedStringResource
    let prompt: LocalizedStringResource
    let modelGoal: String
    let modelPrompt: String
    let scaffold: LocalizedStringResource
    let wordBank: [LocalizedStringResource]
    let systemImage: String
}

enum LessonCatalog {
    static let all: [WritingLesson] = [
        WritingLesson(
            id: "introduce-yourself",
            number: 1,
            title: "Presentera dig",
            subtitle: "Hälsa och berätta lite om dig själv.",
            goal: "Jag kan skriva enkla meningar med mi chiamo, abito och mi piace.",
            prompt: "Skriv 2–4 korta meningar. Säg hej, vad du heter, var du bor och en sak du tycker om.",
            modelGoal: "The learner can write simple sentences using mi chiamo, abito, and mi piace.",
            modelPrompt: "Write 2–4 short sentences. Say hello, give your name, say where you live, and mention one thing you like.",
            scaffold: "Ciao! Mi chiamo … Abito a … Mi piace …",
            wordBank: ["ciao = hej", "mi chiamo = jag heter", "abito a = jag bor i", "mi piace = jag tycker om"],
            systemImage: "hand.wave.fill"
        ),
        WritingLesson(
            id: "family-friend",
            number: 2,
            title: "En person du känner",
            subtitle: "Beskriv en vän eller familjemedlem.",
            goal: "Jag kan använda è, ha och enkla adjektiv för att beskriva en person.",
            prompt: "Skriv 3–5 meningar om en vän eller familjemedlem. Berätta vad personen heter, hur hen är och något hen tycker om.",
            modelGoal: "The learner can use è, ha, and simple adjectives to describe a person.",
            modelPrompt: "Write 3–5 sentences about a friend or family member. Give their name, describe what they are like, and mention something they like.",
            scaffold: "Si chiama … È … Ha … Gli/Le piace …",
            wordBank: ["simpatico/a = trevlig", "gentile = snäll", "ha = har", "gli/le piace = han/hon tycker om"],
            systemImage: "person.2.fill"
        ),
        WritingLesson(
            id: "morning-routine",
            number: 3,
            title: "Min morgon",
            subtitle: "Skriv om en enkel vardagsrutin.",
            goal: "Jag kan beskriva vad jag gör på morgonen i en tydlig ordning.",
            prompt: "Skriv 3–5 meningar om din morgon. När vaknar du, vad äter eller dricker du och vad gör du sedan?",
            modelGoal: "The learner can describe a morning routine in a clear sequence.",
            modelPrompt: "Write 3–5 sentences about your morning. Say when you wake up, what you eat or drink, and what you do next.",
            scaffold: "Mi sveglio alle … Poi … Faccio colazione … Dopo …",
            wordBank: ["mi sveglio = jag vaknar", "poi = sedan", "faccio colazione = jag äter frukost", "vado = jag går/åker"],
            systemImage: "sunrise.fill"
        ),
        WritingLesson(
            id: "at-the-cafe",
            number: 4,
            title: "På kafé",
            subtitle: "Beställ något på ett artigt sätt.",
            goal: "Jag kan beställa mat och dryck med vorrei och per favore.",
            prompt: "Skriv en kort dialog på ett kafé. Beställ en dryck och något att äta och fråga vad det kostar.",
            modelGoal: "The learner can order food and drink politely using vorrei and per favore.",
            modelPrompt: "Write a short café dialogue. Order a drink and something to eat, then ask how much it costs.",
            scaffold: "Buongiorno. Vorrei … per favore. Quanto costa? Grazie!",
            wordBank: ["vorrei = jag skulle vilja ha", "un caffè = en kaffe", "per favore = tack/är du snäll", "quanto costa? = vad kostar det?"],
            systemImage: "cup.and.saucer.fill"
        ),
        WritingLesson(
            id: "grocery-list",
            number: 5,
            title: "I mataffären",
            subtitle: "Berätta vad du behöver köpa.",
            goal: "Jag kan använda mängdord och enkla substantiv i en inköpssituation.",
            prompt: "Skriv 3–5 meningar om vad du behöver köpa till en middag. Ta med minst en mängd och en fråga till personalen.",
            modelGoal: "The learner can use quantities and simple nouns while shopping for groceries.",
            modelPrompt: "Write 3–5 sentences about what you need to buy for dinner. Include at least one quantity and one question for a shop assistant.",
            scaffold: "Devo comprare … Vorrei un chilo di … Dove sono …?",
            wordBank: ["devo comprare = jag måste köpa", "un chilo di = ett kilo", "del pane = lite bröd", "dove sono? = var finns de?"],
            systemImage: "basket.fill"
        ),
        WritingLesson(
            id: "weekend-plans",
            number: 6,
            title: "Helgplaner",
            subtitle: "Skriv om något du vill göra.",
            goal: "Jag kan berätta om enkla framtidsplaner med voglio och vado a.",
            prompt: "Skriv 4–6 meningar om dina planer för helgen. Berätta vart du ska, med vem och vad du vill göra.",
            modelGoal: "The learner can describe simple future plans using voglio and vado a.",
            modelPrompt: "Write 4–6 sentences about your weekend plans. Say where you are going, who you are going with, and what you want to do.",
            scaffold: "Questo fine settimana … Vado a … con … Voglio …",
            wordBank: ["questo fine settimana = i helgen", "vado a = jag åker till", "con = med", "voglio = jag vill"],
            systemImage: "calendar.badge.clock"
        ),
        WritingLesson(
            id: "favorite-place",
            number: 7,
            title: "En plats jag tycker om",
            subtitle: "Beskriv en plats med enkla detaljer.",
            goal: "Jag kan beskriva var en plats ligger, hur den är och varför jag tycker om den.",
            prompt: "Skriv 4–6 meningar om en plats du tycker om. Beskriv var den ligger, hur den ser ut och vad du brukar göra där.",
            modelGoal: "The learner can say where a place is, describe it, and explain why they like it.",
            modelPrompt: "Write 4–6 sentences about a place you like. Say where it is, what it looks like, and what you usually do there.",
            scaffold: "Il mio posto preferito è … Si trova … È … Mi piace perché …",
            wordBank: ["si trova = den ligger", "bello/a = vacker", "tranquillo/a = lugn", "perché = eftersom"],
            systemImage: "mappin.and.ellipse"
        ),
        WritingLesson(
            id: "send-invitation",
            number: 8,
            title: "Bjud in en vän",
            subtitle: "Skriv ett kort och vänligt meddelande.",
            goal: "Jag kan föreslå tid och plats och ställa en enkel fråga.",
            prompt: "Skriv ett kort meddelande där du bjuder in en vän till något. Föreslå en dag, tid och plats och fråga om vännen kan komma.",
            modelGoal: "The learner can suggest a time and place and ask a simple question in an invitation.",
            modelPrompt: "Write a short message inviting a friend to an activity. Suggest a day, time, and place, then ask whether they can come.",
            scaffold: "Ciao …! Vuoi …? Ci vediamo … alle … Puoi venire?",
            wordBank: ["vuoi? = vill du?", "ci vediamo = vi ses", "alle sette = klockan sju", "puoi venire? = kan du komma?"],
            systemImage: "envelope.open.fill"
        )
    ]
}
