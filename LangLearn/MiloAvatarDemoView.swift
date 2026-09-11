import SwiftUI

struct MiloAvatarDemoView: View {
    @State private var milo = MiloController()
    @State private var size: Double = 200
    @State private var rigStatus = ""
    @State private var renderCheck = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                MiloAvatarView(controller: milo, size: size, onRigStatus: { rigStatus = $0 })
                    .frame(height: 240)
                Text("Milo vid din sida").font(.title2.bold())
                Text("Prova ett uttryck eller låt Milo läsa en hälsning.")
                    .foregroundStyle(.secondary)
                ViewThatFits {
                    HStack { reactionButtons }
                    VStack { reactionButtons }
                }
                Button("Låt Milo prata", systemImage: "speaker.wave.2") {
                    milo.speak(LearningLanguage.italian.sampleLine, in: .italian)
                }
                .buttonStyle(.borderedProminent).tint(LanguLearn.purple)
                Button("Stanna", systemImage: "stop.fill") { milo.stop() }
                if let error = milo.narrator.errorMessage {
                    Text(error).foregroundStyle(.red)
                    Button("Försök läsa upp igen") { milo.narrator.retry() }
                }
                VStack(alignment: .leading) {
                    Text("Avatarens storlek")
                    Slider(value: $size, in: 32...240)
                        .accessibilityLabel("Avatarens storlek")
                }
                Text("Ansiktet blir stilla när Minska rörelse är aktiverat. Uppläsningen fungerar ändå.")
                    .font(.footnote).foregroundStyle(.secondary)
#if DEBUG
                if !renderCheck.isEmpty {
                    Text("\(renderCheck) · \(milo.mood.rawValue) · \(milo.narrator.mouthOpening, format: .number.precision(.fractionLength(2)))")
                        .font(.caption.monospaced())
                }
#endif
            }.padding(24)
        }
        .navigationTitle("Milos avatar")
        .navigationBarTitleDisplayMode(.inline)
        .langulearnCanvas()
#if DEBUG
        .task {
            guard ProcessInfo.processInfo.arguments.contains("--milo-avatar-check") else { return }
            for _ in 0..<300 {
                if rigStatus.contains("klipp") { break }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
            guard rigStatus.contains("klipp") else { return }
            for action in [MiloAction.laugh, .applaud, .wave, .speak, .idle] {
                renderCheck = action.rawValue
                try? milo.perform(MiloCommand(action: action, text: "Ciao! Sono Milo. Impariamo insieme, un passo alla volta.", language: "it"))
                do { try await Task.sleep(for: .seconds(action == .speak ? 12 : 7)) } catch { return }
            }
        }
#endif
    }

    private var reactionButtons: some View {
        Group {
            Button("Skratta") { milo.laugh() }
            Button("Applådera") { milo.applaud() }
            Button("Vinka") { milo.wave() }
        }.buttonStyle(.bordered).tint(LanguLearn.purple)
    }
}

#Preview("Rund Milo-avatar") {
    NavigationStack { MiloAvatarDemoView() }
}
