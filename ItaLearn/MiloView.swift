import SwiftUI

/// Live 3D only for a visible, active teacher; compact avatars use the matching portrait.
struct MiloView: View {
    typealias Mood = MiloMood
    var mood: Mood = .greeting
    var size: CGFloat = 120
    var wanders = false
    var mouthOpening: Float = 0
    var trigger = 0
    var debug: MiloDebugControls? = nil
    var onRigStatus: ((String) -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    var body: some View {
        Group {
            if !reduceMotion && isVisible && scenePhase == .active && mood != .still && size > 48 {
                MiloRealityView(
                    mood: mood, mouth: mouthOpening, wanders: wanders,
                    trigger: trigger, debug: debug, onRigStatus: onRigStatus
                )
            } else {
                Image(mood == .thinking ? "MiloThinking" : "Milo").resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}

struct MiloLoadingView: View {
    var message: LocalizedStringResource = "Milo funderar…"
    var showsMascot = true
    var body: some View {
        HStack(spacing: 14) {
            if showsMascot { MiloView(mood: .thinking, size: 64) }
            VStack(alignment: .leading, spacing: 8) {
                Text(message).font(.subheadline.weight(.medium))
                ProgressView().accessibilityLabel(Text(message))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(ItaLearn.purple.opacity(0.06), in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}

struct MiloGreetingCard: View {
    @Environment(TutorSettings.self) private var settings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var greetingIndex = 0
    private let tips: [LocalizedStringResource] = [
        "Lite italienska i taget. Vi tar nästa steg tillsammans.",
        "Fastnar du? Be mig om en ledtråd, så provar vi igen.",
        "Ordkorten hjälper dig att minnas. Prova några efter lektionen.",
        "Säg gärna att du inte vet. Då hittar vi en bra plats att börja."
    ]
    private var greeting: LocalizedStringResource {
        let name = settings.learnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Ciao! Milo här." : "Ciao, \(name)!"
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    mascot.frame(maxWidth: .infinity)
                    words
                }
            } else {
                HStack(spacing: 12) {
                    mascot
                    words.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ItaLearn.purple.opacity(0.07), in: .rect(cornerRadius: 28))
    }

    private var mascot: some View {
        Button {
            greetingIndex = (greetingIndex + 1) % tips.count
        } label: {
            MiloView(size: 104, wanders: true, trigger: greetingIndex)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hälsa på Milo")
        .accessibilityHint("Visar ett nytt studietips")
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MILO · DIN ITALIENSKALÄRARE")
                .font(.caption2.bold()).foregroundStyle(ItaLearn.purple)
            Text(greeting).font(.title2.bold())
            Text(tips[greetingIndex]).font(.callout).fixedSize(horizontal: false, vertical: true)
            Text("Tryck på Milo för ett tips")
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
    .italearnCanvas()
    .environment(TutorSettings(store: UserDefaults(suiteName: "ItaLearn.milo-preview")!))
}

#Preview("Milo med större text") {
    ScrollView { MiloGreetingCard().padding(20) }
        .italearnCanvas()
        .environment(TutorSettings(store: UserDefaults(suiteName: "ItaLearn.milo-preview")!))
        .environment(\.dynamicTypeSize, .accessibility3)
}
