import SwiftUI

struct SettingsView: View {
    @Environment(TutorSettings.self) private var settings
    @Environment(OpenAIAccess.self) private var access
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemoval = false
    @State private var confirmRestore = false
    @State private var restoreMessage: String?
    @State private var confirmWipe = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section("Din lärare Milo") {
                    HStack(spacing: 16) {
                        MiloView(mood: .still, size: 70)
                        Text("Milo hjälper dig att öva, rätta och prova igen. Anpassa tonen så att den passar dig.")
                    }
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
                    Text("Milo är en AI-lärare i ItaLearn. Svaren skapas med OpenAI.").font(.footnote).foregroundStyle(.secondary)
                    if access.hasKey {
                        Button("Ta bort API-nyckeln", role: .destructive) { confirmRemoval = true }
                    }
                }
                if let assessment = store.restorableAssessment,
                   assessment.result.lessons.count != store.state.activePlan?.lessons.count {
                    Section("Återställ din plan") {
                        Text("Din senaste kunskapskoll gav \(assessment.result.lessons.count) lektioner, men din aktiva plan har \(store.state.activePlan?.lessons.count ?? 0). Du kan bygga om planen från kunskapskollen.")
                        Button("Återställ plan från senaste kunskapskoll") { confirmRestore = true }
                        if let restoreMessage {
                            Text(restoreMessage).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Dina studier") {
                    Text("Din studieplan, dina kunskapskollar och samtal sparas lokalt. För varje svar skickar appen bara den aktuella lektionen, en kort lärandesammanfattning och de senaste meddelandena till OpenAI. Kunskapskollen använder sina sex svar och din nuvarande plan.")
                    Text("Appen begär inte att OpenAI sparar en konversation. OpenAI kan ändå behålla API-data enligt sina datavillkor.")
                    Link("OpenAI:s datavillkor", destination: URL(string: "https://developers.openai.com/api/docs/guides/your-data")!)
                }
                Section {
                    Button("Radera alla mina studier", role: .destructive) { confirmWipe = true }
                } header: {
                    Text("Farlig zon")
                } footer: {
                    Text("Tar bort din studieplan, alla lektioner, samtal, övningar och kunskapskollar från den här enheten och börjar om från början. Din API-nyckel påverkas inte. Det går inte att ångra.")
                }
            }
            .navigationTitle("Inställningar")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klar") { dismiss() } } }
            .confirmationDialog("Ta bort nyckeln från den här enheten? Dina studier finns kvar.", isPresented: $confirmRemoval) {
                Button("Ta bort nyckeln", role: .destructive) { Task { await access.remove(); dismiss() } }
            }
            .confirmationDialog(
                "Radera alla studier och börja om? Allt du har gjort tas bort permanent.",
                isPresented: $confirmWipe
            ) {
                Button("Radera allt", role: .destructive) {
                    do { try store.wipeAllStudies(); dismiss() }
                    catch { restoreMessage = store.errorMessage ?? "Studierna kunde inte raderas." }
                }
                Button("Avbryt", role: .cancel) {}
            }
            .confirmationDialog("Bygg om planen från din senaste kunskapskoll? Den nuvarande planen sparas i arkivet och dina avklarade lektioner följer med.", isPresented: $confirmRestore) {
                Button("Återställ planen") {
                    do {
                        try store.restorePlanFromLatestAssessment()
                        restoreMessage = "Planen är återställd."
                    } catch {
                        restoreMessage = store.errorMessage ?? "Planen kunde inte återställas."
                    }
                }
            }
        }
    }
}
