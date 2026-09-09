import SwiftUI

struct OnboardingView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    MiloView(size: 180).frame(maxWidth: .infinity)
                    Text("Ciao! Jag är Milo.")
                        .font(.largeTitle.bold())
                    Text("Jag hjälper dig med italienskan. Sex korta frågor hjälper mig att förstå vad du redan kan. Sedan får du en egen studieplan och övar italienska genom samtal, med hjälp och rättningar längs vägen.")
                        .foregroundStyle(.secondary)
                    APIKeyForm(isOnboarding: true)
                }
                .padding(24)
                .padding(.bottom, 32)
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

#Preview("Börja lära med Milo") {
    OnboardingView()
        .environment(TutorSettings(store: UserDefaults(suiteName: "ItaLearn.preview")!))
        .environment(OpenAIAccess())
}
