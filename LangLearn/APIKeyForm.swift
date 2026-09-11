import SwiftUI

struct APIKeyForm: View {
    var isOnboarding = false
    var showsLearnerName = true
    var onSavingChanged: ((Bool) -> Void)? = nil
    @Environment(OpenAIAccess.self) private var access
    @Environment(TutorSettings.self) private var settings
    @State private var key = ""
    @State private var isSaving = false
    @State private var saved = false
    @State private var replacingKey = false

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
        else if isOnboarding { "Anslut till Milo" }
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
            if isOnboarding && showsLearnerName {
                TextField("Ditt namn (valfritt)", text: $settings.learnerName)
                    .textFieldStyle(.roundedBorder)
            }
            Text(keepsExistingKey
                 ? "Vi använder din sparade nyckel när du börjar samtalet. Samtalen debiteras ditt API-konto."
                 : "Använd din egen OpenAI API-nyckel. Samtalen debiteras ditt API-konto.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !isOnboarding || !access.hasKey || replacingKey {
                SecureField("OpenAI API-nyckel", text: $key)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
#if os(iOS) || os(visionOS)
                .textInputAutocapitalization(.never)
#endif
                .privacySensitive()
                .onChange(of: key) { saved = false }
            } else {
                Label("Din API-nyckel är sparad", systemImage: "checkmark.shield")
                    .font(.subheadline).foregroundStyle(LanguLearn.deepGreen)
                Button("Använd en annan nyckel") { replacingKey = true }
                    .font(.subheadline)
            }
            DisclosureGroup("Om din nyckel och dina samtal") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Nyckeln sparas i Nyckelringen på den här enheten. Dina meddelanden och relevant lärandehistorik skickas till OpenAI när du ber Milo om ett svar. Studieplanen och samtalen sparas lokalt i appen.")
                        .foregroundStyle(.secondary)
                    Link("Så hanterar OpenAI API-data", destination: URL(string: "https://developers.openai.com/api/docs/guides/your-data")!)
                }.padding(.top, 8)
            }.font(.footnote)
            if let error = access.errorMessage { Text(error).foregroundStyle(LanguLearn.red).font(.callout) }
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
            .buttonStyle(LanguLearnPrimaryButtonStyle())
            .disabled(
                (typedKey.isEmpty && !keepsExistingKey) || isSaving
                    || (isOnboarding && !languageReady)
            )
        }
        .langulearnCard()
        .onDisappear { key = "" }
        .onChange(of: isSaving) { onSavingChanged?(isSaving) }
    }
}

#Preview("Börja lära med Milo") {
    OnboardingView()
        .environment(TutorSettings(store: UserDefaults(suiteName: "LangLearn.preview")!))
        .environment(OpenAIAccess())
}
