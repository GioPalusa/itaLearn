import SwiftUI

struct MiloAvatarDemoView: View {
    @State private var milo = MiloController()
    @State private var size: Double = 200
    @State private var rigStatus = ""
    @State private var renderCheck = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                MiloAvatarView(controller: milo, size: size, showsFrame: true, onRigStatus: { rigStatus = $0 })
                    .frame(height: 240)
                Text("Milo vid din sida").font(.title2.bold())
                Text("Prova ett uttryck eller låt Milo läsa en hälsning.")
                    .foregroundStyle(.secondary)
                ViewThatFits {
                    HStack { reactionButtons }
                    VStack { reactionButtons }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))]) {
                    Button("Nyfiken") { milo.curious() }
                    Button("Entusiastisk") { milo.enthusiastic() }
                    Button("Glad") { milo.joyful() }
                    Button("Kom närmare") { milo.leanIn() }
                    Button("Dans") { milo.dance() }
                    Button("Visa något") { milo.present() }
                }.buttonStyle(.bordered).tint(LanguLearn.purple)
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
        .miloLifetime(milo)
#if DEBUG
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            let expressionCheck = arguments.contains("--milo-expression-check")
            guard expressionCheck || arguments.contains("--milo-avatar-check") else { return }
            for _ in 0..<300 {
                if rigStatus.contains("klipp") { break }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
            guard rigStatus.contains("klipp") else { return }
            let actions: [MiloAction] = expressionCheck
                ? [.idle, .curious, .enthusiastic, .joyful, .leanIn, .dance, .present]
                : [.laugh, .applaud, .wave, .speak, .idle]
            for action in actions {
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
