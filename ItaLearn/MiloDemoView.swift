import SwiftUI

/// Local acceptance studio for Snow/Milo. It never uses the learner store or calls OpenAI.
struct MiloDemoView: View {
    private static let shapes = [
        "blinkL", "blinkR", "browRaiseL", "browRaiseR", "browDownL", "browDownR",
        "smileL", "smileR", "cheekRaiseL", "cheekRaiseR",
        "mouthWide", "mouthNarrow", "mouthPucker", "mouthFV",
    ]
    @State private var mood: MiloMood = .idle
    @State private var clipName = "Idle_Watching"
    @State private var mouth: Float = 0
    @State private var gazeX: Float = 0
    @State private var gazeY: Float = 0
    @State private var blink = false
    @State private var face = Dictionary(uniqueKeysWithValues: Self.shapes.map { ($0, Float.zero) })
    @State private var trigger = 0
    @State private var narrator = SpeechNarrator()
    @State private var still = false
    @State private var rigStatus = "Laddar Snow…"
    @Environment(\.scenePhase) private var scenePhase

    private var debug: MiloDebugControls {
        MiloDebugControls(
            clipName: clipName,
            gaze: SIMD2(gazeX, gazeY),
            forcesBlink: blink,
            face: face.filter { $0.value > 0 }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                MiloView(
                    mood: still ? .still : narrator.isSpeaking ? .speaking : mood,
                    size: 280, wanders: false,
                    mouthOpening: narrator.isSpeaking ? narrator.mouthOpening : mouth,
                    trigger: trigger, debug: debug,
                    onRigStatus: { rigStatus = $0 }
                )
                Text(rigStatus).font(.caption.monospaced()).foregroundStyle(.secondary)

                GroupBox("Animation") {
                    VStack(spacing: 12) {
                        Picker("Klipp", selection: $clipName) {
                            Text("Väntar lugnt").tag("Idle_Watching")
                            Text("Lugn konversation").tag("Idle_Neutral_A")
                            Text("Tittar omkring").tag("Idle_LookAround")
                            Text("Tittar omkring – variant 2").tag("Idle_LookAround02")
                            Text("Småpratar").tag("Idle_Chatting")
                            Text("Småpratar – variant 2").tag("Idle_Chatting02")
                        }
                        Picker("Humör", selection: $mood) {
                            ForEach(MiloMood.allCases.filter { $0 != .still }, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        Button("Spela klippet från början") { trigger += 1 }
                            .buttonStyle(.borderedProminent).tint(ItaLearn.purple)
                        Toggle("Visa fallback-bilden", isOn: $still)
                    }
                }

                GroupBox("Blick och tal") {
                    VStack(spacing: 12) {
                        valueSlider("Blick åt sidan", value: $gazeX, range: -0.32...0.32)
                        valueSlider("Blick upp och ner", value: $gazeY, range: -0.22...0.22)
                        Toggle("Blunda", isOn: $blink)
                        valueSlider("Munöppning", value: $mouth, range: 0...1)
                        Button(narrator.isSpeaking ? "Stoppa Milo" : "Låt Milo tala") {
                            if narrator.isSpeaking || narrator.isPreparing {
                                narrator.stop()
                            } else {
                                narrator.speak("Ciao! Mi chiamo Milo. Proviamo insieme, un passo alla volta.")
                            }
                        }
                    }
                }

                GroupBox("Ansiktsformer") {
                    VStack(spacing: 10) {
                        ForEach(Self.shapes, id: \.self) { name in
                            valueSlider(name, value: binding(for: name), range: 0...1)
                        }
                        Button("Nollställ ansiktet") {
                            face = Dictionary(uniqueKeysWithValues: Self.shapes.map { ($0, Float.zero) })
                            blink = false
                        }
                    }
                }

                Text("Snow-modell och italiensk systemröst. Studion gör inga API-anrop.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = narrator.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .padding(20)
        }
        .italearnCanvas()
        .navigationTitle("Milos studio")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { narrator.stop() }
        .onChange(of: scenePhase) { if scenePhase != .active { narrator.stop() } }
    }

    private func binding(for name: String) -> Binding<Float> {
        Binding(get: { face[name, default: 0] }, set: { face[name] = $0 })
    }

    private func valueSlider(_ title: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range).accessibilityLabel(title)
        }
    }
}

#Preview("Milo · Snow-studio") {
    NavigationStack { MiloDemoView() }
}
