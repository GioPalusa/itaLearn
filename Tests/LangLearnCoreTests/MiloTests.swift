import AVFoundation
import Foundation
import RealityKit
import simd
import Testing
@testable import LangLearnCore

@Suite("Milo animation and speech lifecycle")
struct MiloTests {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test func audioWriterFlushesAndCancellationRemovesTemporarySpeech() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1))
        let chunk = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128))
        chunk.frameLength = 128
        for index in 0..<128 { chunk.floatChannelData?[0][index] = sin(Float(index) / 8) * 0.2 }
        let end = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
        end.frameLength = 0
        let writer = SpeechAudioWriter()
        #expect(writer.append(chunk) == nil)
        let result = try #require(writer.append(end))
        let url = try result.get()
        #expect(try AVAudioFile(forReading: url).length == 128)
        writer.cancel()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func cancelledAndReplacedSpeechCannotRestart() {
        var state = SpeechPlaybackState()
        let old = state.begin()
        state.cancel()
        let cancelledStart = state.start(old)
        #expect(!cancelledStart)
        let current = state.begin()
        let replacedStart = state.start(old)
        #expect(!replacedStart)
        let currentStart = state.start(current)
        #expect(currentStart)
        state.meter(decibels: -15, token: current)
        #expect(state.mouth > 0)
        let oldFinish = state.finish(old)
        #expect(!oldFinish)
        let currentFinish = state.finish(current)
        #expect(currentFinish)
        #expect(state.mouth == 0)
    }

    @Test func clipHeaderSamplingAndRootOwnershipAreValid() throws {
        let library = try MiloClipLibrary(contentsOf: root.appendingPathComponent("LangLearn/Resources/MiloClips.bin"))
        #expect(library.fps == 30)
        #expect(library.jointNames.count == 33)
        #expect(Set(library.clips.keys) == Set(["Idle_Neutral_A", "Idle_LookAround", "Idle_LookAround02", "Idle_Chatting", "Idle_Chatting02", "Idle_Watching"]))
        let rootIndex = try #require(library.jointNames.firstIndex(of: "root"))
        for clip in library.clips.values {
            #expect(clip.duration > 3)
            #expect(clip.loops)
            for (first, last) in zip(clip.frames.first ?? [], clip.frames.last ?? []) {
                #expect(abs(simd_dot(first.vector, last.vector)) > 0.9999)
            }
            #expect(clip.hipsOffsets.allSatisfy { abs($0.x) < 0.0001 && abs($0.z) < 0.0001 })
            #expect(clip.frames.allSatisfy { abs($0[rootIndex].angle) < 0.0001 })
            let first = clip.sample(time: 0)
            let repeated = clip.sample(time: 0)
            #expect(first.rotations[rootIndex].vector == repeated.rotations[rootIndex].vector)
        }
    }

    @Test func invalidClipMagicIsRejected() {
        #expect(throws: MiloClipError.invalidMagic) { try MiloClipLibrary(data: Data("NOPE".utf8)) }
    }

    @Test func animatorKeepsFaceIndependentFromBodyAndBoundsHomeMovement() throws {
        let library = try MiloClipLibrary(contentsOf: root.appendingPathComponent("LangLearn/Resources/MiloClips.bin"))
        var quiet = MiloAnimator(library: library)
        quiet.configure(mood: .speaking, mouth: 0, wanders: true)
        var talking = MiloAnimator(library: library)
        talking.configure(mood: .speaking, mouth: 0.8, wanders: true)
        for _ in 0..<600 {
            let quietPose = quiet.sample(delta: 1 / 30)
            let talkingPose = talking.sample(delta: 1 / 30)
            #expect(quietPose.joints["spine"]?.vector == talkingPose.joints["spine"]?.vector)
            #expect(abs(quietPose.stageOffset.x) <= 0.081)
            #expect(abs(talkingPose.stageOffset.x) <= 0.081)
        }
        #expect(talking.sample(delta: 0).face["mouthWide", default: 0] > quiet.sample(delta: 0).face["mouthWide", default: 0])
    }

    @Test func manifestMatchesSnowRuntimeContract() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("LangLearn/Resources/MiloRigManifest.json"))
        let manifest = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(manifest["version"] as? Int == 2)
        #expect(manifest["jointCount"] as? Int == 33)
        #expect(manifest["triangles"] as? Int ?? .max <= 62_000)
        #expect(Set(manifest["meshes"] as? [String] ?? []) == Set(["Milo_Body", "Milo_Head", "Milo_Eyes", "Milo_Hair"]))
        #expect((manifest["blendShapes"] as? [String] ?? []).count == 14)
        #expect((manifest["textures"] as? [String] ?? []).contains("head_base.png"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("LangLearn/Resources/clips.json").path))
    }

    @MainActor @Test func bundledModelContainsTheManifestRigAndFace() async throws {
        let entity = try await Entity(contentsOf: root.appendingPathComponent("LangLearn/Resources/Milo.usdz"))
        var models: [ModelEntity] = []
        func visit(_ item: Entity) {
            if let model = item as? ModelEntity { models.append(model) }
            for child in item.children { visit(child) }
        }
        visit(entity)
        let jointNames = Set(models.flatMap(\.jointNames).map { $0.split(separator: "/").last.map(String.init) ?? "" })
        #expect(Set(["root", "hips", "head", "jaw", "eye_L", "eye_R", "upper_arm_L", "forearm_R"]).isSubset(of: jointNames))
        #expect(!jointNames.contains { name in
            ["DEF-", "MCH-", "ORG-", "FK-", "IK-", "STR-", "mixamorig:"].contains { name.hasPrefix($0) }
        })
        let shapes = Set(models.flatMap { $0.components[BlendShapeWeightsComponent.self]?.weightSet.flatMap(\.weightNames) ?? [] })
        #expect(Set(["blinkL", "blinkR", "smileL", "smileR", "mouthWide", "mouthFV"]).isSubset(of: shapes))
        for model in models where !model.jointNames.isEmpty {
            #expect(model.jointTransforms.count == model.jointNames.count)
        }
    }
}
