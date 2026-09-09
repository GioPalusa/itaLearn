import SwiftUI

struct OnboardingView: View {
    @Environment(TutorSettings.self) private var settings

    private var language: String { settings.targetLanguage.displayName.lowercased() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    MiloView(size: 180).frame(maxWidth: .infinity)
                    Text("Hej! Jag är Milo.")
                        .font(.largeTitle.bold())
                    Text("Välj vilket språk du vill lära dig, så hjälper jag dig med det. Sex korta frågor hjälper mig att förstå vad du redan kan. Sedan får du en egen studieplan och övar \(language) genom samtal, med hjälp och rättningar längs vägen.")
                        .foregroundStyle(.secondary)
                    LanguageChoiceForm()
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
}

struct APIKeyForm: View {
    var isOnboarding = false
    @Environment(OpenAIAccess.self) private var access
    @Environment(TutorSettings.self) private var settings
    @State private var key = ""
    @State private var isSaving = false
    @State private var saved = false

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 16) {
            Text(access.hasKey ? "Byt OpenAI API-nyckel" : "Börja lära med Milo")
                .font(.title2.bold())
            if isOnboarding {
                TextField("Ditt namn (valfritt)", text: $settings.learnerName)
                    .textFieldStyle(.roundedBorder)
            }
            Text("Använd din egen OpenAI API-nyckel. Samtalen debiteras ditt API-konto.")
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
            Button {
                isSaving = true
                Task {
                    if await access.save(key) {
                        key = ""
                        saved = true
                        settings.hasOnboarded = true
                        settings.confirmLanguageChoice()
                    }
                    isSaving = false
                }
            } label: {
                if isSaving { ProgressView() }
                else { Text(isOnboarding ? "Spara och börja samtalet" : "Spara nyckel") }
            }
            .buttonStyle(LangLearnPrimaryButtonStyle())
            .disabled(
                key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving
                    || (isOnboarding && settings.targetLanguage == settings.nativeLanguage)
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
            languageRow("Jag vill lära mig", selection: $settings.targetLanguage)
            Divider()
            languageRow("Förklara för mig på", selection: $settings.nativeLanguage)
            Text("Milo undervisar på \(settings.targetLanguage.displayName.lowercased()) och förklarar, rättar och sammanfattar på \(settings.nativeLanguage.displayName.lowercased()). Appens egna texter är på svenska.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if settings.targetLanguage == settings.nativeLanguage {
                Label("Välj olika språk för att lära dig och för förklaringarna.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(LangLearn.red)
            }
        }
        .langlearnCard()
    }

    /// A menu picker on its own shows no label outside a Form, so the row carries it.
    private func languageRow(_ title: LocalizedStringKey, selection: Binding<LearningLanguage>) -> some View {
        HStack {
            Text(title).font(.callout)
            Spacer(minLength: 12)
            Picker(title, selection: selection) {
                ForEach(LearningLanguage.catalog) { language in
                    Text("\(language.flag) \(language.displayName)").tag(language)
                }
            }
            .labelsHidden()
        }
    }
}

#Preview("Börja lära med Milo") {
    OnboardingView()
        .environment(TutorSettings(store: UserDefaults(suiteName: "LangLearn.preview")!))
        .environment(OpenAIAccess())
}
