import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome, language, connection
}

struct OnboardingView: View {
    @Environment(TutorSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = OnboardingStep.welcome
    @State private var isSaving = false

    init(startingAt step: OnboardingStep = .welcome) {
        _step = State(initialValue: step)
    }

    private var canContinue: Bool {
        step == .welcome || (settings.chosenTarget != nil && settings.chosenTarget != settings.nativeLanguage)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    OnboardingHeader(step: step, isSaving: isSaving) {
                        if let previous = OnboardingStep(rawValue: step.rawValue - 1) { step = previous }
                    }
                    ScrollView {
                        Group {
                            switch step {
                            case .welcome:
                                OnboardingWelcome(height: min(350, max(230, geometry.size.height * 0.43)))
                            case .language:
                                OnboardingLanguageStep()
                            case .connection:
                                OnboardingConnectionStep(isSaving: $isSaving)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                        .frame(maxWidth: 620)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .clipped()
                    .id(step)
                    .transition(.opacity)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if step != .connection {
                        OnboardingFooter(step: step, isEnabled: canContinue) {
                            guard canContinue, let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
                            step = next
                        }
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: step)
            }
            .langulearnCanvas()
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct OnboardingHeader: View {
    let step: OnboardingStep
    let isSaving: Bool
    let goBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: goBack) {
                Image(systemName: "arrow.left").font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.65), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Föregående steg")
            .disabled(step == .welcome || isSaving)
            .opacity(step == .welcome ? 0 : 1)
            .accessibilityHidden(step == .welcome)
            Text("LanguLearn").font(.headline).foregroundStyle(LanguLearn.purple)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
                    Capsule().fill(item.rawValue <= step.rawValue ? LanguLearn.purple : LanguLearn.purple.opacity(0.15))
                        .frame(width: item == step ? 22 : 8, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Steg \(step.rawValue + 1) av 3")
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
    }
}

private struct OnboardingWelcome: View {
    let height: CGFloat
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 20) {
            OnboardingMiloStage(height: typeSize.isAccessibilitySize ? 220 : height)
            VStack(spacing: 12) {
                Text("Hitta orden.\nMed Milo vid din sida.")
                    .font(.largeTitle.bold()).foregroundStyle(LanguLearn.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Öva i små samtal, få hjälp när du fastnar och bygg vidare på det du kan.")
                    .font(.body).foregroundStyle(LanguLearn.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            Label("Vi börjar med sex korta frågor", systemImage: "bubble.left.and.bubble.right")
                .font(.subheadline).foregroundStyle(LanguLearn.purple)
                .multilineTextAlignment(.center)
        }
    }
}

private struct OnboardingMiloStage: View {
    let height: CGFloat
    @State private var milo = MiloController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            let size = min(height, geometry.size.width)
            Button { milo.wave() } label: {
                ZStack(alignment: .bottom) {
                    Ellipse().fill(LanguLearn.purple.opacity(0.10))
                        .frame(width: size * 0.6, height: 22).blur(radius: 10)
                        .padding(.bottom, 14)
                    Circle()
                        .fill(.linearGradient(colors: [.white.opacity(0.95), LanguLearn.purple.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: size * 0.90, height: size * 0.90)
                        .padding(.bottom, 8)
                    MiloView(mood: milo.mood, size: size, wanders: true, trigger: milo.trigger,
                             onAnimationCompleted: { milo.animationCompleted(trigger: $0) })
                    Text("Hej! Jag är Milo.")
                        .font(.callout.weight(.semibold)).foregroundStyle(LanguLearn.purple)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(.white, in: .capsule)
                        .shadow(color: LanguLearn.purple.opacity(0.08), radius: 12, y: 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hälsa på Milo")
            .accessibilityHint("Milo vinkar tillbaka")
        }
        .frame(height: height)
        .task { milo.wave() }
        .onDisappear { milo.stop() }
        .onChange(of: scenePhase) { if scenePhase != .active { milo.stop() } }
    }
}

struct OnboardingMiloGuide: View {
    let message: LocalizedStringResource
    var mood: MiloMood = .idle
    /// Supply one and Milo is live here: he can answer the choice being made, and
    /// say a line in the language the learner just pointed at.
    var controller: MiloController? = nil
    var caption: LocalizedStringResource? = nil
    var listen: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    portrait(88)
                    words
                }
            } else {
                HStack(spacing: 16) {
                    portrait(100)
                    words
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func portrait(_ size: CGFloat) -> some View {
        // A controller carries its own mood, so the fixed one is only for the
        // guides that never react.
        let avatar = MiloAvatarView(controller: controller, mood: controller == nil ? mood : nil, size: size)
        if let listen {
            Button(action: listen) { avatar }
                .buttonStyle(.plain)
                .accessibilityLabel("Lyssna på Milo")
                .accessibilityHint("Milo säger en mening på språket du har valt")
        } else {
            avatar
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message).font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            if let caption {
                Text(caption).font(.footnote).foregroundStyle(LanguLearn.purple)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.75), in: .rect(cornerRadius: 24))
    }
}

private struct OnboardingFooter: View {
    let step: OnboardingStep
    let isEnabled: Bool
    let advance: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 10) {
            Button(action: advance) {
                HStack {
                    Text(step == .welcome ? "Nu börjar vi" : "Fortsätt")
                    Image(systemName: "arrow.right")
                }
                .font(.headline).foregroundStyle(.white)
                .padding(.horizontal, 24).padding(.vertical, 18)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(LanguLearn.purple.opacity(isEnabled ? 1 : 0.4), in: .capsule)
            }
            .buttonStyle(.plain).disabled(!isEnabled)
            if !typeSize.isAccessibilitySize {
                Text(step == .welcome ? "Välj ditt språk i nästa steg" : "Du kan ändra dina val i Inställningar")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 12)
        .frame(maxWidth: 620).frame(maxWidth: .infinity)
        .background(LanguLearn.canvas)
    }
}

private struct OnboardingConnectionStep: View {
    @Binding var isSaving: Bool
    @State private var milo = MiloController()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingMiloGuide(message: "Du behöver inte kunna något i förväg.", controller: milo)
                .task { milo.present() }
                .miloLifetime(milo)
            VStack(alignment: .leading, spacing: 10) {
                Text("Vi börjar där du är.").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                Text("Efter sex korta frågor får du en studieplan att börja med. Svara gärna att du inte vet – det hjälper mig också.")
                    .foregroundStyle(.secondary)
            }
            APIKeyForm(isOnboarding: true, showsLearnerName: false, onSavingChanged: { isSaving = $0 })
        }
    }
}

#if DEBUG
/// Isolated layout preview: no learner store or automatic Keychain/API access.
struct OnboardingPreviewHost: View {
    @State private var settings = TutorSettings(store: UserDefaults(suiteName: "LanguLearn.onboarding-layout")!)
    @State private var access = OpenAIAccess()
    private let arguments = ProcessInfo.processInfo.arguments

    var body: some View {
        OnboardingView(startingAt: arguments.contains("--onboarding-connection") ? .connection : arguments.contains("--onboarding-language") ? .language : .welcome)
            .environment(settings)
            .environment(access)
            .environment(\.dynamicTypeSize, arguments.contains("--onboarding-large-text") ? .accessibility3 : .large)
            .task {
                settings.chosenTarget = arguments.contains("--onboarding-selected") ? .italian : nil
                settings.nativeLanguage = .swedish
                settings.learnerName = ""
            }
    }
}

#Preview("Välkommen till Milo") { OnboardingPreviewHost() }
#endif
