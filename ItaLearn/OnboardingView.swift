import FoundationModels
import SwiftUI

/// Screen 2d — "Onboarding, Apple Intelligence-uppsättning".
struct OnboardingView: View {
    @Environment(TutorSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var model = PrivateCloudComputeLanguageModel()
    @State private var name = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        @Bindable var settings = settings

        VStack(spacing: 0) {
            hero

            ScrollView {
                VStack(spacing: 12) {
                    capabilityCard
                    nameCard
                    levelCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 12)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }

            VStack(spacing: 10) {
                Button("Kom igång") {
                    settings.learnerName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    settings.hasOnboarded = true
                    dismiss()
                }
                .buttonStyle(ItaLearnPrimaryButtonStyle())

                Text("Du kan ändra allt i Inställningar sedan.")
                    .font(.il(13))
                    .foregroundStyle(ItaLearn.inkTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: 720)
        }
        .italearnCanvas()
        .ignoresSafeArea(edges: .top)
        .interactiveDismissDisabled()
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            Text("ItaLearn")
                .font(.il(15))
                .foregroundStyle(.white.opacity(0.9))

            Text("En italienlärare som stannar i din telefon")
                .font(.il(34, .bold))
                .foregroundStyle(.white)
                .padding(.top, 6)

            Text("Texten du skriver granskas i Private Cloud Compute. Inget sparas hos Apple, och inget konto behövs.")
                .font(.il(17))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.top, 10)
        }
        .frame(maxWidth: 340, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 72)
        .padding(.bottom, 24)
        .frame(minHeight: 300, alignment: .bottomLeading)
        .background(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: 220, height: 220)
                .offset(x: 40, y: -60)
        }
        .background(ItaLearn.brandGradient)
        .clipped()
    }

    // MARK: - Cards

    private var capabilityCard: some View {
        @Bindable var settings = settings

        return GroupedCard {
            HStack(spacing: 12) {
                statusIcon
                VStack(alignment: .leading, spacing: 1) {
                    Text(availabilityTitle)
                        .font(.il(15, .semibold))
                        .foregroundStyle(ItaLearn.ink)
                    Text(availabilityDetail)
                        .font(.il(13))
                        .foregroundStyle(ItaLearn.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            RowSeparator(inset: 60)

            toggleRow(
                icon: "pencil.and.scribble",
                tint: ItaLearn.purple,
                title: "Writing Tools i övningarna",
                subtitle: "Rättar i din egen text, inte i en chatt",
                isOn: $settings.correctsSpelling
            )

            RowSeparator(inset: 60)

            toggleRow(
                icon: "bell",
                tint: ItaLearn.magenta,
                title: "En mikrolektion om dagen",
                subtitle: "En mening kl. \(settings.reminderText) — svara direkt i notisen",
                isOn: $settings.dailyReminder
            )
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch model.availability {
        case .available:
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(ItaLearn.green, in: .circle)
        case .unavailable:
            Image(systemName: "exclamationmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(ItaLearn.magenta, in: .circle)
        }
    }

    private var availabilityTitle: LocalizedStringKey {
        switch model.availability {
        case .available: "Apple Intelligence är på"
        case .unavailable: "Apple Intelligence är inte redo"
        }
    }

    private var availabilityDetail: String {
        switch model.availability {
        case .available:
            String(localized: "Rättningen körs i Private Cloud Compute")
        case .unavailable(let reason):
            reason.userMessage
        }
    }

    private func toggleRow(
        icon: String,
        tint: Color,
        title: LocalizedStringKey,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.il(15, .semibold))
                    .foregroundStyle(ItaLearn.ink)
                Text(subtitle)
                    .font(.il(13))
                    .foregroundStyle(ItaLearn.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(ItaLearn.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Vad ska läraren kalla dig?")
                .font(.il(15, .semibold))
                .foregroundStyle(ItaLearn.ink)

            TextField("Ditt namn", text: $name)
                .textFieldStyle(.plain)
                .font(.il(17))
                .focused($isNameFocused)
                .submitLabel(.done)
                .padding(12)
                .background(ItaLearn.field, in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                }
        }
        .italearnCard()
    }

    private var levelCard: some View {
        @Bindable var settings = settings

        return VStack(alignment: .leading, spacing: 10) {
            Text("Var är du nu?")
                .font(.il(15, .semibold))
                .foregroundStyle(ItaLearn.ink)

            HStack(spacing: 8) {
                ForEach(ProficiencyLevel.allCases) { level in
                    let isSelected = settings.level == level

                    Button {
                        settings.level = level
                    } label: {
                        VStack(spacing: 2) {
                            Text(level.rawValue)
                                .font(.il(17, .bold))
                                .foregroundStyle(isSelected ? .white : Color.black.opacity(0.7))
                            Text(level.caption)
                                .font(.il(11))
                                .foregroundStyle(isSelected ? .white.opacity(0.9) : ItaLearn.inkTertiary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(
                            isSelected ? AnyShapeStyle(ItaLearn.purple) : AnyShapeStyle(Color.black.opacity(0.05)),
                            in: .rect(cornerRadius: 12)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
        }
        .italearnCard()
    }
}

#Preview {
    OnboardingView()
        .environment(TutorSettings(store: UserDefaults(suiteName: "preview") ?? .standard))
}
