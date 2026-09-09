import SwiftUI

/// The flag on the plan header: which language this study belongs to, and the
/// way in to the others.
struct LanguageChip: View {
    let language: LearningLanguage
    let level: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(language.flag).font(.system(size: 14))
                Text(language.displayName.uppercased())
                    .font(.il(11, .semibold)).tracking(0.66)
                if let level {
                    Text("· \(level)").font(.il(11, .semibold)).tracking(0.66)
                }
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(LangLearn.magenta)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(LangLearn.magenta.opacity(0.10), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Språk: \(language.displayName)")
        .accessibilityHint("Byt språk eller lägg till ett nytt")
    }
}

/// Every language the learner has studies for, plus a way to start another.
///
/// Switching does not touch what is on disk: each language keeps its own plan,
/// lessons and practice, so returning to one resumes exactly where it stopped.
struct LanguageSwitcherView: View {
    @Environment(LearningStore.self) private var store
    @Environment(TutorSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var studies: [LanguageStudy] = []
    @State private var isAdding = false
    /// Applied on dismissal rather than on tap: switching swaps the whole screen
    /// underneath this sheet, and doing that mid-dismissal leaves the new screen
    /// half-built.
    @State private var pending: LearningLanguage?

    var body: some View {
        NavigationStack {
            List {
                Section("Mina språk") {
                    ForEach(studies) { study in
                        Button { choose(study.language) } label: { row(study) }
                            .buttonStyle(.plain)
                    }
                }
                Section {
                    Button { isAdding = true } label: {
                        Label("Lägg till språk", systemImage: "plus.circle")
                    }
                } footer: {
                    Text("Ett nytt språk börjar med en kunskapskoll som bygger studieplanen. Dina andra språk ligger kvar precis som du lämnade dem.")
                }
            }
            .navigationTitle("Språk")
            .toolbar { Button("Klar") { dismiss() } }
            .sheet(isPresented: $isAdding) {
                AddLanguageView(taken: Set(studies.map(\.language.code))) { choose($0) }
            }
        }
        .task { studies = merged(store.studies()) }
        .onDisappear {
            guard let pending else { return }
            self.pending = nil
            settings.startLearning(pending)
        }
    }

    private func row(_ study: LanguageStudy) -> some View {
        HStack(spacing: 12) {
            Text(study.language.flag).font(.system(size: 26))
            VStack(alignment: .leading, spacing: 2) {
                Text(study.language.displayName)
                    .font(.body).foregroundStyle(LangLearn.ink)
                Text(caption(study))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if study.language == settings.chosenTarget {
                Image(systemName: "checkmark").foregroundStyle(LangLearn.purple)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private func caption(_ study: LanguageStudy) -> String {
        guard study.hasPlan else { return "Kunskapskollen är inte klar än" }
        return "\(study.lessonsCompleted) av \(study.lessonTotal) lektioner klara"
    }

    /// The language in use may have no snapshot yet — it gets one when its
    /// kunskapskoll first saves — so make sure it is still listed.
    private func merged(_ saved: [LanguageStudy]) -> [LanguageStudy] {
        guard let current = settings.chosenTarget else { return saved }
        if saved.contains(where: { $0.language == current }) { return saved }
        return [LanguageStudy(language: current, lessonsCompleted: 0, lessonTotal: 0, updatedAt: .now)] + saved
    }

    private func choose(_ language: LearningLanguage) {
        if language != settings.chosenTarget { pending = language }
        dismiss()
    }
}

/// The catalog, minus what the learner already studies.
struct AddLanguageView: View {
    let taken: Set<String>
    let onPick: (LearningLanguage) -> Void
    @Environment(TutorSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var matches: [LearningLanguage] {
        let available = LearningLanguage.pickerOrder.filter {
            !taken.contains($0.code) && $0 != settings.nativeLanguage
        }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return available }
        return available.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.englishName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(matches) { language in
                        Button {
                            dismiss()
                            onPick(language)
                        } label: {
                            HStack(spacing: 12) {
                                Text(language.flag).font(.system(size: 26))
                                Text(language.displayName).foregroundStyle(LangLearn.ink)
                                Spacer()
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Milo förklarar på \(settings.nativeLanguage.displayName.lowercased()). Det språket kan du byta i Inställningar.")
                }
            }
            .searchable(text: $search, prompt: "Sök språk")
            .navigationTitle("Lägg till språk")
            .toolbar { Button("Avbryt") { dismiss() } }
        }
    }
}
