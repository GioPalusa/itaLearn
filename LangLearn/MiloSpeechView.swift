import SwiftUI

/// A compact, persistent speaker row. It remains available while the learner types.
/// The still mark costs no rig; speech controls belong to the conversation owner.
struct MiloSpeechView: View {
    let controller: MiloController
    var listening = false
    var thinking = false
    var context: LocalizedStringResource = "Milo"
    @Environment(TutorSettings.self) private var settings

    private var narrator: SpeechNarrator { controller.narrator }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                MiloAvatarView(mood: .still, size: 44, showsFrame: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context).font(.caption.weight(.semibold))
                        .foregroundStyle(LanguLearn.purple)
                    if narrator.isPreparing {
                        Text("Förbereder uppläsning…").font(.caption).foregroundStyle(.secondary)
                    } else if narrator.isSpeaking {
                        Text("Lyssna på \(settings.targetLanguage.displayName.lowercased())")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if listening {
                        Text("Jag lyssnar. Ta det i din takt.").font(.caption).foregroundStyle(.secondary)
                    } else if thinking {
                        Text("Milo funderar…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if narrator.isPreparing || narrator.isSpeaking {
                    Button { narrator.stop() } label: {
                        Image(systemName: "stop.fill")
                            .frame(width: 44, height: 44)
                            .background(LanguLearn.purple.opacity(0.08), in: .circle)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(LanguLearn.purple)
                    .accessibilityLabel("Stoppa uppläsningen")
                } else if thinking {
                    ProgressView().accessibilityLabel("Milo funderar…")
                }
            }
            if let error = narrator.errorMessage {
                Text(error).font(.caption).foregroundStyle(LanguLearn.red)
                Button("Försök läsa upp igen") { narrator.retry() }
                    .font(.callout).frame(minHeight: 44)
            }
        }
    }
}

#Preview("Milo talar — lokal röst") {
    MiloSpeechPreview()
        .environment(TutorSettings(store: UserDefaults(suiteName: "LangLearn.preview")!))
}
private struct MiloSpeechPreview: View {
    @State private var milo = MiloController()
    var body: some View {
        VStack(spacing: 20) {
            MiloSpeechView(controller: milo)
            Button("Lyssna") { milo.speak(LearningLanguage.italian.sampleLine, in: .italian) }
            Button("Applådera") { milo.applaud() }
        }.padding(24).langulearnCanvas().miloLifetime(milo)
    }
}
