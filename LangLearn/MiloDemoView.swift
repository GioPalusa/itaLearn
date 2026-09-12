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
    @State private var manualFace = false
    @State private var gazeX: Float = 0
    @State private var gazeY: Float = 0
    @State private var zoom: Float = 1
    @State private var pausesBody = false
    @State private var walksAcrossStage = false
    @State private var blink = false
    @State private var face: [String: Float] = [:]
    @State private var trigger = 0
    @State private var narrator = SpeechNarrator()
    @State private var still = false
    @State private var rigStatus = "Laddar Snow…"
    @State private var renderCheck = ""
    @Environment(\.scenePhase) private var scenePhase

    private var debug: MiloDebugControls {
        MiloDebugControls(
            clipName: clipName,
            gaze: SIMD2(gazeX, gazeY),
            forcesBlink: blink,
            face: manualFace ? face : [:], mouthOpening: narrator.isSpeaking || !manualFace ? nil : mouth,
            pausesBody: pausesBody, walksAcrossStage: walksAcrossStage && clipName == "Walk"
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                MiloView(
                    mood: still ? .still : narrator.isSpeaking ? .speaking : mood,
                    size: 280, wanders: false,
                    mouthOpening: narrator.isSpeaking ? narrator.mouthOpening : mouth,
                    trigger: trigger,
                    zoom: zoom, debug: debug,
                    onRigStatus: { rigStatus = $0 }
                )
                Text(rigStatus).font(.caption.monospaced()).foregroundStyle(.secondary)
                if !renderCheck.isEmpty { Text(renderCheck).font(.caption.monospaced()) }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
            ScrollView {
              VStack(spacing: 18) {
                NavigationLink("Prova den runda avataren") { MiloAvatarDemoView() }
                    .buttonStyle(.borderedProminent).tint(LanguLearn.purple)
                Toggle("Styr ansiktet manuellt", isOn: $manualFace)
                GroupBox("Kamerafokus") {
                    valueSlider("Zoom mot ansiktet", value: $zoom, range: 1...4.5)
                    HStack {
                        Button("Hela Milo") { zoom = 1 }
                        Spacer()
                        Button("Ansiktet") { zoom = 3.8; pausesBody = true }
                    }
                        .font(.subheadline)
                }

                GroupBox("Animation") {
                    VStack(spacing: 12) {
                        Picker("Klipp", selection: $clipName) {
                            Text("Dansar").tag("Dance")
                            Text("Visar något").tag("Present")
                            Text("Går").tag("Walk")
                            Text("Vinkar").tag("Wave")
                            Text("Skrattar").tag("Laugh")
                            Text("Applåderar").tag("Applaud")
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
                            .buttonStyle(.borderedProminent).tint(LanguLearn.purple)
                        Toggle("Visa fallback-bilden", isOn: $still)
                        Toggle("Pausa kroppen", isOn: $pausesBody)
                        if clipName == "Walk" { Toggle("Gå över scenen", isOn: $walksAcrossStage) }
                    }
                }

                GroupBox("Blick och tal") {
                    VStack(spacing: 12) {
                        valueSlider("Blick åt sidan", value: $gazeX, range: -0.32...0.32)
                        valueSlider("Blick upp och ner", value: $gazeY, range: -0.22...0.22)
                        Toggle("Blunda", isOn: $blink)
                        valueSlider("Munöppning", value: Binding(get: { mouth }, set: { mouth = $0; manualFace = true }), range: 0...1)
                        Button(narrator.isSpeaking ? "Stoppa Milo" : "Låt Milo tala") {
                            if narrator.isSpeaking || narrator.isPreparing {
                                narrator.stop()
                            } else {
                                // The studio is about the mascot, not the course, so it
                                // stays independent of the learner's chosen language.
                                narrator.speak(LearningLanguage.english.sampleLine, in: .english)
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
                            face = [:]
                            manualFace = false
                            blink = false
                            mouth = 0
                            gazeX = 0
                            gazeY = 0
                        }
                    }
                }

                Text("Snow-modell och lokal systemröst. Studion gör inga API-anrop.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = narrator.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .padding(20)
            }
        }
        .langulearnCanvas()
        .navigationTitle("Milos studio")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { narrator.stop() }
        .onChange(of: scenePhase) { if scenePhase != .active { narrator.stop() } }
#if DEBUG
        .task {
            // Reproducible render checks use the same @State bindings as the
            // sliders, after the live view has loaded; no learner data changes.
            guard ProcessInfo.processInfo.arguments.contains("--milo-face-check") else { return }
            zoom = 3.8
            manualFace = true
            pausesBody = true
            guard await waitForLiveRig() else { return }
            for step in 0..<8 {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                renderCheck = ["Neutral", "Munöppning 1", "Blunda", "Blick vänster", "Blick höger", "Blick ned", "Blick upp", "Nollställd"][step]
                mouth = step == 1 ? 1 : 0
                blink = step == 2
                gazeX = step == 3 ? -0.3 : step == 4 ? 0.3 : 0
                gazeY = step == 5 ? -0.2 : step == 6 ? 0.2 : 0
            }
        }
        .task {
            guard ProcessInfo.processInfo.arguments.contains("--milo-motion-check") else { return }
            guard await waitForLiveRig() else { return }
            clipName = "Wave"
            do {
                try await Task.sleep(for: .seconds(5))
                clipName = "Walk"
                try await Task.sleep(for: .seconds(5))
                walksAcrossStage = true
                try await Task.sleep(for: .seconds(10))
                walksAcrossStage = false
                clipName = "Idle_Watching"
            } catch { return }
        }
#endif
    }

#if DEBUG
    private func waitForLiveRig() async -> Bool {
        for _ in 0..<200 {
            if rigStatus.contains("klipp") { return true }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return false }
        }
        return false
    }
#endif

    private func binding(for name: String) -> Binding<Float> {
        Binding(get: { face[name, default: 0] }, set: { manualFace = true; face[name] = $0 })
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
