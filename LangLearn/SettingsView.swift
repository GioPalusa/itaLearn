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
    @State private var confirmRestartOnboarding = false
    @State private var showingLanguages = false

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
                    Text("Ändra din startpunkt och dina mål i Min resa. En frivillig kunskapskoll finns under Upptäck.")
                        .font(.footnote).foregroundStyle(.secondary)
                    NavigationLink {
                        MiloDemoView()
                    } label: {
                        Label("Öppna Milos karaktärsstudio", systemImage: "figure.wave")
                    }
                }
                Section {
                    Button { showingLanguages = true } label: {
                        HStack {
                            Text("Jag lär mig").foregroundStyle(LanguLearn.ink)
                            Spacer()
                            Text(settings.targetLanguage.badge).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    Picker("Förklaringar på", selection: $settings.nativeLanguage) {
                        ForEach(LearningLanguage.pickerOrder) { language in
                            Text(language.badge).tag(language)
                        }
                    }
                } header: {
                    Text("Språk")
                } footer: {
                    Text("Milo undervisar på \(settings.targetLanguage.displayName.lowercased()) och förklarar på \(settings.nativeLanguage.displayName.lowercased()). Varje språk har sin egen studieplan: byter du språk ligger dina nuvarande studier kvar och kommer tillbaka när du byter tillbaka.")
                }
                Section("OpenAI") {
                    APIKeyForm()
                    Text("Milo är en AI-lärare i LanguLearn. Svaren skapas med artificiell intelligens.").font(.footnote).foregroundStyle(.secondary)
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
                Section("Om") {
                    Text("Milo bygger på karaktären Snow av Blender Studio (CC BY 4.0).")
                    Link("Licens för Snow", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                }
                Section {
                    Button("Gör om introduktionen") { confirmRestartOnboarding = true }
                } footer: {
                    Text("Visar välkomsten och språkvalet igen. Dina studier och din sparade nyckel påverkas inte.")
                }
                Section {
                    Button("Radera alla mina studier", role: .destructive) { confirmWipe = true }
                } header: {
                    Text("Farlig zon")
                } footer: {
                    Text("Tar bort dina studieplaner på alla språk, med lektioner, samtal, övningar och kunskapskollar, från den här enheten. Din API-nyckel påverkas inte. Det går inte att ångra.")
                }
            }
            .navigationTitle("Inställningar")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klar") { dismiss() } } }
            .sheet(isPresented: $showingLanguages) { LanguageSwitcherView() }
            .confirmationDialog(
                "Visa introduktionen igen? Dina studier och din nyckel ligger kvar.",
                isPresented: $confirmRestartOnboarding
            ) {
                Button("Gör om introduktionen") { settings.restartOnboarding(); dismiss() }
                Button("Avbryt", role: .cancel) {}
            }
            .confirmationDialog("Ta bort nyckeln från den här enheten? Dina studier finns kvar.", isPresented: $confirmRemoval) {
                Button("Ta bort nyckeln", role: .destructive) { Task { await access.remove(); dismiss() } }
            }
            .confirmationDialog(
                "Radera alla studier på alla språk och börja om? Allt du har gjort tas bort permanent.",
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
