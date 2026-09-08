import SwiftData
import SwiftUI

/// Screen 2f — "Inställningar: lärarens ton, widget, notiser".
struct SettingsView: View {
    @Environment(TutorSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LessonRecord.completedAt, order: .reverse)
    private var records: [LessonRecord]

    @State private var isShowingPrivacyNote = false


    private var reviewsToday: Int {
        let calendar = Calendar.current
        return records.filter { calendar.isDateInToday($0.completedAt) }.count
    }

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Inställningar")
                        .font(.il(34, .bold))
                        .foregroundStyle(ItaLearn.ink)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 14)

                    SettingsSectionHeader(title: "LÄRAREN")
                    teacherCard
                        .padding(.horizontal, 16)

                    SettingsSectionHeader(title: "ÖVNING VARJE DAG")
                        .padding(.top, 22)
                    practiceCard
                        .padding(.horizontal, 16)

                    SettingsSectionHeader(title: "APPLE INTELLIGENCE")
                        .padding(.top, 22)
                    intelligenceCard
                        .padding(.horizontal, 16)

                    Text("Dina texter och lärarens återkoppling stannar på din iPhone. Ingenting används för att träna modeller.")
                        .font(.il(13))
                        .foregroundStyle(ItaLearn.inkTertiary)
                        .lineSpacing(3)
                        .padding(.horizontal, 32)
                        .padding(.top, 12)
                }
                .frame(maxWidth: 720)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
            .italearnCanvas()
            .hideNavigationBar()
            .safeAreaInset(edge: .top) {
                HStack {
                    Spacer()
                    Button("Klar") { dismiss() }
                        .font(.il(17, .semibold))
                        .foregroundStyle(ItaLearn.purple)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .sheet(isPresented: $isShowingPrivacyNote) {
                PrivateCloudComputeNote()
            }
        }
    }

    // MARK: - Läraren

    private var teacherCard: some View {
        @Bindable var settings = settings

        return GroupedCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("Ton")
                    .font(.il(15, .semibold))
                    .foregroundStyle(ItaLearn.ink)

                Picker("Ton", selection: $settings.tone) {
                    ForEach(TeacherTone.allCases) { tone in
                        Text(tone.label).tag(tone)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.top, 10)

                Text(settings.tone.sample)
                    .font(.il(13))
                    .foregroundStyle(ItaLearn.inkSecondary)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            RowSeparator()

            SettingsRow(title: "Rättar även stavning") {
                Toggle("", isOn: $settings.correctsSpelling)
                    .labelsHidden()
                    .tint(ItaLearn.green)
            }

            RowSeparator()

            SettingsRow(title: "Nivå") {
                Picker("Nivå", selection: $settings.level) {
                    ForEach(ProficiencyLevel.allCases) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                .labelsHidden()
                .tint(ItaLearn.inkTertiary)
            }
        }
    }

    // MARK: - Övning varje dag

    private var practiceCard: some View {
        @Bindable var settings = settings

        return GroupedCard {
            SettingsRow(
                title: "Mikrolektion som notis",
                subtitle: "Svara direkt i notisen"
            ) {
                Toggle("", isOn: $settings.dailyReminder)
                    .labelsHidden()
                    .tint(ItaLearn.green)
            }

            RowSeparator()

            SettingsRow(title: "Tid") {
                DatePicker(
                    "Tid",
                    selection: Binding(
                        get: { settings.reminderDate },
                        set: { settings.reminderDate = $0 }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .disabled(!settings.dailyReminder)
            }

            RowSeparator()

            NavigationLink {
                WidgetGuide()
            } label: {
                SettingsRow(title: "Widget på hemskärmen") {
                    RowChevron()
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Apple Intelligence

    private var intelligenceCard: some View {
        GroupedCard {
            SettingsRow(
                title: "Granskningar i dag",
                subtitle: "Återställs kl. 00:00"
            ) {
                Text("\(reviewsToday) / \(TutorSettings.dailyReviewAllowance)")
                    .font(.ilMono(15))
                    .monospacedDigit()
                    .foregroundStyle(ItaLearn.purple)
            }

            RowSeparator()

            Button {
                isShowingPrivacyNote = true
            } label: {
                SettingsRow(title: "Om Private Cloud Compute") {
                    RowChevron()
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct PrivateCloudComputeNote: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Din text lämnar aldrig ett spår")
                        .font(.il(28, .bold))
                        .foregroundStyle(ItaLearn.ink)

                    Text("När du trycker på Kontrollera skickas din övningstext till Private Cloud Compute. Servern körs på Apple-kisel, kan inte lagra din text och granskas av oberoende forskare.")
                        .font(.il(17))
                        .foregroundStyle(ItaLearn.inkSecondary)
                        .lineSpacing(4)

                    Text("Lärarens återkoppling sparas bara i Mitt lärande på din iPhone. Ingenting används för att träna modeller.")
                        .font(.il(17))
                        .foregroundStyle(ItaLearn.inkSecondary)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .italearnCanvas()
            .navigationTitle("Private Cloud Compute")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klar") { dismiss() }
                }
            }
        }
    }
}

/// Placeholder destination for the widget row — the app ships no widget
/// extension yet, so this explains how to add one rather than pretending.
private struct WidgetGuide: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Widgeten är inte med i den här versionen")
                    .font(.il(22, .semibold))
                    .foregroundStyle(ItaLearn.ink)

                Text("Designen visar en widget med dagens mening på hemskärmen. Den kräver en WidgetKit-tillägg i projektet, som inte finns ännu.")
                    .font(.il(17))
                    .foregroundStyle(ItaLearn.inkSecondary)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .italearnCanvas()
        .navigationTitle("Widget")
    }
}

#Preview {
    SettingsView()
        .environment(TutorSettings(store: UserDefaults(suiteName: "preview") ?? .standard))
        .modelContainer(for: LessonRecord.self, inMemory: true)
}
