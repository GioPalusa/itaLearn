import SwiftUI

struct SettingsView: View {
    @Environment(TutorSettings.self) private var settings
    @Environment(OpenAIAccess.self) private var access
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemoval = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section("Läraren") {
                    TextField("Ditt namn", text: $settings.learnerName)
                    Picker("Ton", selection: $settings.tone) {
                        ForEach(TeacherTone.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Rätta även stavning", isOn: $settings.correctsSpelling)
                    Text("Nivån anpassas efter din senaste kunskapskoll. Du kan göra en ny från Min studieplan.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("OpenAI") {
                    APIKeyForm()
                    LabeledContent("Kunskapskoll och plan", value: "GPT-5.6 Sol")
                    LabeledContent("Lektioner och rättningar", value: "GPT-5.6 Luna")
                    if access.hasKey {
                        Button("Ta bort API-nyckeln", role: .destructive) { confirmRemoval = true }
                    }
                }
                Section("Dina studier") {
                    Text("Din studieplan, dina kunskapskollar och samtal sparas lokalt. För varje svar skickar appen bara den aktuella lektionen, en kort lärandesammanfattning och de senaste meddelandena till OpenAI. Kunskapskollen använder sina sex svar och din nuvarande plan.")
                    Text("Appen begär inte att OpenAI sparar en konversation. OpenAI kan ändå behålla API-data enligt sina datavillkor.")
                    Link("OpenAI:s datavillkor", destination: URL(string: "https://developers.openai.com/api/docs/guides/your-data")!)
                }
            }
            .navigationTitle("Inställningar")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klar") { dismiss() } } }
            .confirmationDialog("Ta bort nyckeln från den här enheten? Dina studier finns kvar.", isPresented: $confirmRemoval) {
                Button("Ta bort nyckeln", role: .destructive) { Task { await access.remove(); dismiss() } }
            }
        }
    }
}
