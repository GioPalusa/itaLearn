import SwiftUI

struct OnboardingView: View {
    @Environment(TutorSettings.self) private var settings

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    MiloView(size: 180).frame(maxWidth: .infinity)
                    Text("Hej! Jag är Milo.")
                        .font(.largeTitle.bold())
                    Text(intro)
                        .foregroundStyle(.secondary)
                    LanguageChoiceForm(isOnboarding: true)
                    APIKeyForm(isOnboarding: true)
                }
                .padding(24)
                .padding(.bottom, 32)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .langlearnCanvas()
            .navigationTitle("LangLearn")
        }
    }

    /// Written without naming a language until the learner has picked one.
    private var intro: String {
        guard let target = settings.chosenTarget else {
            return """
            Välj vilket språk du vill lära dig, så hjälper jag dig med det. \
            Sex korta frågor hjälper mig att förstå vad du redan kan. Sedan får du \
            en egen studieplan och övar genom samtal, med hjälp och rättningar \
            längs vägen. Du kan lära dig flera språk och växla mellan dem när du vill.
            """
        }
        let language = target.displayName.lowercased()
        return """
        Sex korta frågor hjälper mig att förstå vad du redan kan. Sedan får du en \
        egen studieplan och övar \(language) genom samtal, med hjälp och rättningar \
        längs vägen. Du kan lära dig flera språk och växla mellan dem när du vill.
        """
    }
}

struct APIKeyForm: View {
    var isOnboarding = false
    @Environment(OpenAIAccess.self) private var access
    @Environment(TutorSettings.self) private var settings
    @State private var key = ""
    @State private var isSaving = false
    @State private var saved = false

    private var typedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Onboarding reached with a key already in the Keychain — someone redoing
    /// the introduction. They are here for the language, not to retype the key.
    private var keepsExistingKey: Bool { isOnboarding && access.hasKey && typedKey.isEmpty }
    /// Onboarding cannot finish until a language is chosen, and it has to differ
    /// from the one Milo explains in.
    private var languageReady: Bool {
        guard let target = settings.chosenTarget else { return false }
        return target != settings.nativeLanguage
    }

    private var heading: LocalizedStringKey {
        if isOnboarding && access.hasKey { "Klart att börja" }
        else if access.hasKey { "Byt OpenAI API-nyckel" }
        else { "Börja lära med Milo" }
    }

    private var buttonTitle: LocalizedStringKey {
        if !isOnboarding { "Spara nyckel" }
        else if keepsExistingKey { "Börja samtalet" }
        else { "Spara och börja samtalet" }
    }

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 16) {
            Text(heading)
                .font(.title2.bold())
            if isOnboarding {
                TextField("Ditt namn (valfritt)", text: $settings.learnerName)
                    .textFieldStyle(.roundedBorder)
            }
            Text(keepsExistingKey
                 ? "Din nyckel finns redan sparad. Lämna fältet tomt för att fortsätta med den."
                 : "Använd din egen OpenAI API-nyckel. Samtalen debiteras ditt API-konto.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            SecureField("OpenAI API-nyckel", text: $key)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
#if os(iOS) || os(visionOS)
                .textInputAutocapitalization(.never)
#endif
                .privacySensitive()
                .onChange(of: key) { saved = false }
            Text("Nyckeln sparas i Nyckelringen på den här enheten. Dina meddelanden och relevant lärandehistorik skickas till OpenAI när du ber Milo om ett svar. Studieplanen och samtalen sparas lokalt i appen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Link("Så hanterar OpenAI API-data", destination: URL(string: "https://developers.openai.com/api/docs/guides/your-data")!)
                .font(.footnote)
            if let error = access.errorMessage { Text(error).foregroundStyle(LangLearn.red).font(.callout) }
            if saved { Label("Nyckeln är sparad. Anslutningen kontrolleras vid nästa svar.", systemImage: "checkmark.circle").font(.callout) }
            if isOnboarding && settings.chosenTarget == nil {
                Label("Välj språket du vill lära dig först.", systemImage: "arrow.up")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                isSaving = true
                Task {
                    // An empty field means "keep the key I already have", which
                    // is what someone redoing the introduction is doing here.
                    let accepted = if keepsExistingKey { true } else { await access.save(key) }
                    if accepted {
                        key = ""
                        saved = true
                        settings.hasOnboarded = true
                        settings.confirmLanguageChoice()
                    }
                    isSaving = false
                }
            } label: {
                if isSaving { ProgressView() }
                else { Text(buttonTitle) }
            }
            .buttonStyle(LangLearnPrimaryButtonStyle())
            .disabled(
                (typedKey.isEmpty && !keepsExistingKey) || isSaving
                    || (isOnboarding && !languageReady)
            )
        }
        .langlearnCard()
        .onDisappear { key = "" }
    }
}

/// Screen 1 asks for the pair every prompt is built from: what to learn, and
/// which language Milo should explain it in.
struct LanguageChoiceForm: View {
    var isOnboarding = false
    @Environment(TutorSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 16) {
            Text(isOnboarding ? "Ditt språk" : "Språk")
                .font(.title2.bold())

            HStack {
                Text("Jag vill lära mig").font(.callout)
                Spacer(minLength: 12)
                Picker("Jag vill lära mig", selection: $settings.chosenTarget) {
                    Text("Välj språk").tag(LearningLanguage?.none)
                    ForEach(LearningLanguage.pickerOrder) { language in
                        Text(language.badge).tag(LearningLanguage?.some(language))
                    }
                }
                .labelsHidden()
            }

            Divider()

            HStack {
                Text("Förklara för mig på").font(.callout)
                Spacer(minLength: 12)
                Picker("Förklara för mig på", selection: $settings.nativeLanguage) {
                    ForEach(LearningLanguage.pickerOrder) { language in
                        Text(language.badge).tag(language)
                    }
                }
                .labelsHidden()
            }

            if let target = settings.chosenTarget {
                Text("Milo undervisar på \(target.displayName.lowercased()) och förklarar, rättar och sammanfattar på \(settings.nativeLanguage.displayName.lowercased()). Appens egna texter är på svenska.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if target == settings.nativeLanguage {
                    Label("Välj olika språk för att lära dig och för förklaringarna.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(LangLearn.red)
                } else if !target.hasVoice || !target.supportsDictation {
                    // Icelandic, for one, has neither on iOS. Say so rather than
                    // shipping buttons that quietly do nothing.
                    Label(speechCaveat(for: target), systemImage: "speaker.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Du kan lägga till fler språk senare och växla mellan dem. Varje språk får en egen studieplan.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .langlearnCard()
    }

    private func speechCaveat(for language: LearningLanguage) -> String {
        let name = language.displayName.lowercased()
        return switch (language.hasVoice, language.supportsDictation) {
        case (false, false): "Den här enheten har varken röst eller diktering för \(name). Du läser och skriver i stället."
        case (false, true): "Den här enheten kan inte läsa upp \(name), men diktering fungerar."
        default: "Den här enheten har ingen diktering för \(name), men Milo kan läsa upp texten."
        }
    }
}

#Preview("Börja lära med Milo") {
    OnboardingView()
        .environment(TutorSettings(store: UserDefaults(suiteName: "LangLearn.preview")!))
        .environment(OpenAIAccess())
}
