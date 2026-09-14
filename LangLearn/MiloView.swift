import SwiftUI

/// Live 3D only for a visible, active teacher; compact avatars use the matching portrait.
struct MiloView: View {
    typealias Mood = MiloMood
    var mood: Mood = .greeting
    var size: CGFloat = 120
    var wanders = false
    var mouthOpening: Float = 0
    var trigger = 0
    /// Explicit framings are stable constants; never animate the rig's render size or zoom.
    var zoom: Float? = nil
    var pinsFaceFocus = false
    var placeholderSize: CGFloat? = nil
    var debug: MiloDebugControls? = nil
    var onRigStatus: ((String) -> Void)? = nil
    var onAnimationCompleted: ((Int) -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    private var framing: Float { zoom ?? (size < 80 ? 3.3 : size < 180 ? 2.6 : 1) }

    var body: some View {
        Group {
            if !reduceMotion && isVisible && scenePhase == .active && mood != .still && size >= 64 {
                MiloRealityView(
                    mood: mood, mouth: mouthOpening, wanders: wanders && size >= 230 && framing <= 1.2,
                    trigger: trigger, zoom: framing, pinsFaceFocus: pinsFaceFocus,
                    placeholderSize: placeholderSize, debug: debug, onRigStatus: onRigStatus,
                    onAnimationCompleted: onAnimationCompleted
                )
            } else {
                Image(mood == .thinking ? "MiloThinking" : "Milo").resizable().scaledToFit()
                    // The supplied still is a bust, so never stretch it to a full-body stage.
                    .frame(width: placeholderSize ?? (framing < 2 ? min(size, 120) : size))
                    .scaleEffect(framing >= 3 ? CGFloat(framing / 3) : 1)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .accessibilityHidden(true)
        .task { await waitForCalmMainThread() }
        .onDisappear { isVisible = false }
    }

    /// The rig costs a few hundred milliseconds of main-thread work the first
    /// time it is pulled in, so the portrait stands in until the surrounding
    /// screen has settled. Once the assets are cached the 3D view starts at once.
    private func waitForCalmMainThread() async {
        if !MiloAssets.isWarm {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
        }
        isVisible = true
    }
}

struct MiloLoadingView: View {
    var message: LocalizedStringResource = "Milo funderar…"
    var showsMascot = true
    var body: some View {
        HStack(spacing: 14) {
            // A loading row must never silently introduce a second live rig.
            if showsMascot { MiloAvatarView(mood: .thinking, size: 56) }
            VStack(alignment: .leading, spacing: 8) {
                Text(message).font(.subheadline.weight(.medium))
                ProgressView().accessibilityLabel(Text(message))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(LanguLearn.purple.opacity(0.06), in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}

struct MiloGreetingCard: View {
    @Environment(TutorSettings.self) private var settings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var greetingIndex = 0
    @State private var companion = MiloController()
    private var tips: [LocalizedStringResource] { [
        "Lite \(settings.targetLanguage.displayName.lowercased()) i taget. Vi tar nästa steg tillsammans.",
        "Fastnar du? Be mig om en ledtråd, så provar vi igen.",
        "Ordkorten hjälper dig att minnas. Prova några efter lektionen.",
        "Säg gärna att du inte vet. Då hittar vi en bra plats att börja."
    ] }
    private var greeting: LocalizedStringResource {
        let name = settings.learnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let hello = settings.targetLanguage.greeting
        return name.isEmpty ? "\(hello)! Milo här." : "\(hello), \(name)!"
    }

    var body: some View {
        Button {
            greetingIndex = (greetingIndex + 1) % tips.count
            if greetingIndex == 1 { companion.curious() }
            else if greetingIndex == 2 { companion.present() }
            else { companion.joyful() }
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        mascot.frame(maxWidth: .infinity)
                        words.padding(.horizontal, 16).padding(.bottom, 16)
                    }
                } else {
                    HStack(spacing: 4) {
                        mascot
                        words
                            .padding(.trailing, 14).padding(.vertical, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LanguLearn.purple.opacity(0.09), in: .rect(cornerRadius: 28))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Visar ett nytt studietips")
        .miloLifetime(companion)
    }

    private var mascot: some View {
        MiloView(mood: companion.mood, size: 188, trigger: companion.trigger, zoom: 2.6,
                 onAnimationCompleted: { companion.animationCompleted(trigger: $0) })
            .frame(width: 140, height: 156, alignment: .bottom)
            .clipped()
            .allowsHitTesting(false)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MILO · DIN SPRÅKLÄRARE")
                .font(.caption2.bold()).foregroundStyle(LanguLearn.purple)
            Text(greeting).font(.title2.bold())
            Text(tips[greetingIndex]).font(.callout).fixedSize(horizontal: false, vertical: true)
            Text("Tryck för ett nytt studietips")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

#Preview("Milo välkomnar") {
    ScrollView {
        VStack(spacing: 20) {
            MiloGreetingCard()
            MiloLoadingView()
        }.padding(20)
    }
    .langulearnCanvas()
    .environment(TutorSettings(store: UserDefaults(suiteName: "LangLearn.milo-preview")!))
}

#Preview("Milo med större text") {
    ScrollView { MiloGreetingCard().padding(20) }
        .langulearnCanvas()
        .environment(TutorSettings(store: UserDefaults(suiteName: "LangLearn.milo-preview")!))
        .environment(\.dynamicTypeSize, .accessibility3)
}
