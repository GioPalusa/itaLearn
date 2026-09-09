import SwiftUI

/// One live speaker above the content; historical message avatars remain still.
struct MiloSpeechView: View {
    let narrator: SpeechNarrator
    var listening = false
    var thinking = false
    var encouraging = false
    @Environment(TutorSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    private var mood: MiloMood {
        if narrator.isSpeaking { return .speaking }
        if narrator.isPreparing || thinking { return .thinking }
        if listening { return .listening }
        return encouraging ? .encouraging : .idle
    }
    var body: some View {
        HStack(spacing: 14) {
            MiloView(mood: mood, size: 88, mouthOpening: narrator.mouthOpening)
            VStack(alignment: .leading, spacing: 6) {
                Text("Milo").font(.headline)
                if narrator.isPreparing {
                    ProgressView("Förbereder uppläsning…").font(.caption)
                } else if narrator.isSpeaking {
                    Text("Lyssna på \(settings.targetLanguage.displayName.lowercased())").font(.caption).foregroundStyle(.secondary)
                } else if listening {
                    Text("Jag lyssnar. Ta det i din takt.").font(.caption).foregroundStyle(.secondary)
                } else if encouraging {
                    Text("Vi provar en gång till tillsammans.").font(.caption).foregroundStyle(.secondary)
                }
                if let error = narrator.errorMessage {
                    Text(error).font(.caption).foregroundStyle(LangLearn.red)
                    Button("Försök läsa upp igen") { narrator.retry() }.font(.caption)
                }
                if narrator.isPreparing || narrator.isSpeaking {
                    Button("Stoppa uppläsningen", systemImage: "stop.fill") { narrator.stop() }.font(.caption)
                }
            }
            Spacer(minLength: 0)
        }
        .onDisappear { narrator.stop() }
        .onChange(of: scenePhase) { if scenePhase != .active { narrator.stop() } }
    }
}

#Preview("Milo talar — lokal röst") {
    MiloSpeechPreview()
        .environment(TutorSettings(store: UserDefaults(suiteName: "LangLearn.preview")!))
}
private struct MiloSpeechPreview: View {
    @State private var narrator = SpeechNarrator()
    var body: some View {
        VStack(spacing: 20) {
            MiloSpeechView(narrator: narrator)
            Button("Lyssna") { narrator.speak("Ciao! Mi chiamo Milo. Come stai? Io sto bene. Proviamo insieme, un passo alla volta.") }
        }.padding(24).langlearnCanvas()
    }
}
