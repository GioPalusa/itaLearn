import SwiftUI

struct OnboardingView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.largeTitle)
                        .foregroundStyle(ItaLearn.purple)
                    Text("Ciao! Vi börjar där du är.")
                        .font(.largeTitle.bold())
                    Text("Sex korta frågor hjälper din lärare att förstå vad du redan kan. Sedan får du en egen studieplan och övar italienska genom samtal, med hjälp och rättningar längs vägen.")
                        .foregroundStyle(.secondary)
                    APIKeyForm(isOnboarding: true)
                }
                .padding(24)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .italearnCanvas()
            .navigationTitle("ItaLearn")
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
            Text(access.hasKey ? "Byt OpenAI API-nyckel" : "Anslut din lärare")
                .font(.title2.bold())
            if isOnboarding {
                TextField("Ditt namn (valfritt)", text: $settings.learnerName)
                    .textFieldStyle(.roundedBorder)
            }
            Text("Använd din egen OpenAI API-nyckel. Samtalen debiteras ditt API-konto, separat från en ChatGPT-prenumeration.")
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
            Text("Nyckeln sparas i Nyckelringen på den här enheten. Dina meddelanden och relevant lärandehistorik skickas till OpenAI när du ber läraren om ett svar. Studieplanen och samtalen sparas lokalt i appen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Link("Så hanterar OpenAI API-data", destination: URL(string: "https://developers.openai.com/api/docs/guides/your-data")!)
                .font(.footnote)
            if let error = access.errorMessage { Text(error).foregroundStyle(ItaLearn.red).font(.callout) }
            if saved { Label("Nyckeln är sparad. Anslutningen kontrolleras vid nästa svar.", systemImage: "checkmark.circle").font(.callout) }
            Button {
                isSaving = true
                Task {
                    if await access.save(key) {
                        key = ""
                        saved = true
                        settings.hasOnboarded = true
                    }
                    isSaving = false
                }
            } label: {
                if isSaving { ProgressView() }
                else { Text(isOnboarding ? "Spara och börja samtalet" : "Spara nyckel") }
            }
            .buttonStyle(ItaLearnPrimaryButtonStyle())
            .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
        }
        .italearnCard()
        .onDisappear { key = "" }
    }
}

#Preview("Anslut din lärare") {
    OnboardingView()
        .environment(TutorSettings(store: UserDefaults(suiteName: "ItaLearn.preview")!))
        .environment(OpenAIAccess())
}
