import SwiftUI

struct OnboardingLanguageStep: View {
    @Environment(TutorSettings.self) private var settings
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var picker: LanguagePickerPurpose?

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 24) {
            OnboardingMiloGuide(message: "Vilket språk är du nyfiken på?")
            Text("Ditt nästa språk")
                .font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            VStack(spacing: 12) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                    ForEach([LearningLanguage.italian, .spanish, .french, .english]) { language in
                        OnboardingLanguageCard(language: language, selected: settings.chosenTarget == language) {
                            settings.chosenTarget = language
                        }
                    }
                }
                Button { picker = .target } label: {
                    HStack(spacing: 12) {
                        Text(otherLanguageLabel).multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: "globe")
                    }
                    .font(.body.weight(.medium)).foregroundStyle(LanguLearn.purple)
                    .padding(16).frame(maxWidth: .infinity, minHeight: 52)
                    .background(.white.opacity(0.55), in: .rect(cornerRadius: 18))
                }.buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 16) {
                Button { picker = .explanation } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Jag förklarar för dig på").font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            Text(settings.nativeLanguage.badge).font(.headline).foregroundStyle(LanguLearn.ink)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.down").foregroundStyle(LanguLearn.purple)
                        }
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.plain)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Vad heter du?").font(.subheadline)
                    TextField("Ditt namn (valfritt)", text: $settings.learnerName)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                        .padding(12).background(LanguLearn.field, in: .rect(cornerRadius: 12))
                }
            }.padding(18).background(.white, in: .rect(cornerRadius: 24))
            if settings.chosenTarget == settings.nativeLanguage {
                Label("Välj olika språk för att lära dig och för förklaringarna.", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(LanguLearn.red)
            } else if let target = settings.chosenTarget, !target.hasVoice || !target.supportsDictation {
                Label("Röst eller diktering saknas för det här språket på din enhet. Du kan alltid läsa och skriva med Milo.", systemImage: "text.bubble")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Text("Börja med ett språk. Du kan lägga till fler senare – varje språk får en egen studieplan.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .sheet(item: $picker) { purpose in
            OnboardingLanguageSheet(
                title: purpose == .target ? "Välj ditt språk" : "Förklaringar på",
                selected: purpose == .target ? settings.chosenTarget : settings.nativeLanguage
            ) { language in
                if purpose == .target { settings.chosenTarget = language }
                else { settings.nativeLanguage = language }
            }
        }
    }

    private var otherLanguageLabel: LocalizedStringResource {
        if let selected = settings.chosenTarget,
           ![LearningLanguage.italian, .spanish, .french, .english].contains(selected) {
            return "\(selected.badge) · Byt språk"
        }
        return "Visa alla språk"
    }

    private enum LanguagePickerPurpose: String, Identifiable {
        case target, explanation
        var id: String { rawValue }
    }
}

private struct OnboardingLanguageCard: View {
    let language: LearningLanguage
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(language.flag).font(.title)
                    Spacer(minLength: 4)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.body).opacity(selected ? 1 : 0.25)
                }
                Text(language.displayName).font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(selected ? .white : LanguLearn.ink)
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? LanguLearn.purple : .white, in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct OnboardingLanguageSheet: View {
    let title: LocalizedStringResource
    let selected: LearningLanguage?
    let choose: (LearningLanguage) -> Void
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    private var languages: [LearningLanguage] {
        LearningLanguage.pickerOrder.filter {
            search.isEmpty || $0.displayName.localizedStandardContains(search)
                || $0.englishName.localizedStandardContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List(languages) { language in
                Button {
                    choose(language)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(language.badge).foregroundStyle(LanguLearn.ink)
                        Spacer()
                        if language == selected { Image(systemName: "checkmark").foregroundStyle(LanguLearn.purple) }
                    }.frame(minHeight: 40)
                }
                .accessibilityAddTraits(language == selected ? .isSelected : [])
            }
            .overlay {
                if languages.isEmpty { ContentUnavailableView.search(text: search) }
            }
            .searchable(text: $search, prompt: "Sök språk")
            .navigationTitle(Text(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Stäng") { dismiss() } } }
        }
    }
}
