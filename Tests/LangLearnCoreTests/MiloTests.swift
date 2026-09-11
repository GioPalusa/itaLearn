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
        #expect(Set(library.clips.keys) == Set(["Idle_Neutral_A", "Idle_LookAround", "Idle_LookAround02", "Idle_Chatting", "Idle_Chatting02", "Idle_Watching", "Walk", "Wave", "Laugh", "Applaud"]))
        let rootIndex = try #require(library.jointNames.firstIndex(of: "root"))
        for clip in library.clips.values {
            #expect(clip.duration > 1)
            for frame in clip.frames {
                #expect(frame.allSatisfy { abs(simd_length($0.vector) - 1) < 0.0001 })
            }
            if clip.loops {
                for (first, last) in zip(clip.frames.first ?? [], clip.frames.last ?? []) {
                    #expect(abs(simd_dot(first.vector, last.vector)) > 0.9999)
                }
            }
            #expect(clip.hipsOffsets.allSatisfy { abs($0.x) < 0.0001 && abs($0.z) < 0.0001 })
            #expect(clip.frames.allSatisfy { abs($0[rootIndex].angle) < 0.0001 })
            let first = clip.sample(time: 0)
            let repeated = clip.sample(time: 0)
            #expect(first.rotations[rootIndex].vector == repeated.rotations[rootIndex].vector)
        }
        #expect(library.clips["Walk"]?.loops == true)
        #expect(library.clips["Wave"]?.loops == false)
        let restingArm = try #require(library.jointNames.firstIndex(of: "upper_arm_R"))
        for (name, clip) in library.clips where name.hasPrefix("Idle_") || name == "Wave" {
            #expect(try #require(clip.frames.first)[restingArm].angle > 1, "Free arm must not inherit the source T-pose: \(name)")
        }
    }

    @Test func invalidClipMagicIsRejected() {
        #expect(throws: MiloClipError.invalidMagic) { try MiloClipLibrary(data: Data("NOPE".utf8)) }
    }

    @MainActor @Test func avatarCommandsReplaceReplayAndIgnoreStaleCompletions() throws {
        let milo = MiloController()
        milo.laugh()
        let first = milo.trigger
        milo.laugh()
        #expect(milo.trigger != first)
        milo.animationCompleted(trigger: first)
        #expect(milo.mood == .laughing)
        milo.applaud()
        let applause = milo.trigger
        #expect(milo.mood == .applauding)
        milo.animationCompleted(trigger: applause)
        #expect(milo.mood == .idle)
        milo.wave()
        milo.stop()
        #expect(milo.mood == .idle)
        #expect(!milo.narrator.isSpeaking && !milo.narrator.isPreparing)
    }

    @MainActor @Test func malformedCommandsDoNotInterruptTheAvatar() throws {
        let milo = MiloController()
        try milo.perform(json: Data(#"{"action":"applaud"}"#.utf8))
        let trigger = milo.trigger
        #expect(throws: MiloCommandError.missingSpeechText) {
            try milo.perform(MiloCommand(action: .speak, text: "  ", language: "it"))
        }
        #expect(throws: MiloCommandError.unsupportedLanguage) {
            try milo.perform(MiloCommand(action: .speak, text: "Ciao!", language: "unknown"))
        }
        #expect(throws: DecodingError.self) {
            try milo.perform(json: Data(#"{"action":"invented"}"#.utf8))
        }
        #expect(milo.mood == .applauding && milo.trigger == trigger)
        let speech = MiloCommand(action: .speak, text: "Ciao!", language: "it")
        #expect(try JSONDecoder().decode(MiloCommand.self, from: JSONEncoder().encode(speech)) == speech)
    }

    @Test func reactionsAnimateThenReleaseTheirFacesAndCanReplay() throws {
        let library = try MiloClipLibrary(contentsOf: root.appendingPathComponent("LangLearn/Resources/MiloClips.bin"))
        for (mood, name) in [(MiloMood.laughing, "Laugh"), (.applauding, "Applaud")] {
            let clip = try #require(library.clips[name])
            #expect(!clip.loops)
            let hand = try #require(library.jointNames.firstIndex(of: "hand_L"))
            let handMotion = clip.frames.map { simd_distance($0[hand].vector, clip.frames[0][hand].vector) }.max() ?? 0
            #expect(handMotion > 0.1)
            var animator = MiloAnimator(library: library)
            animator.configure(mood: mood, mouth: 0, wanders: false)
            #expect(!animator.completedReaction)
            let start = animator.sample(delta: 0.1)
            #expect(start.face["smileL", default: 0] > 0.3)
            if mood == .laughing { #expect(start.face["mouthOpen", default: 0] > 0.2) }
            for _ in 0..<Int((clip.duration + 1) * 30) { _ = animator.sample(delta: 1 / 30) }
            #expect(animator.completedReaction)
            let finished = animator.sample(delta: 0)
            #expect(finished.face["mouthOpen"] == 0)
            #expect(finished.face["smileL", default: 0] < 0.2)
            animator.configure(mood: mood, mouth: 0, wanders: false)
            #expect(animator.completedReaction)
            animator.configure(mood: mood, mouth: 0, wanders: false, restart: true)
            #expect(!animator.completedReaction)
        }
    }

    @Test func studioFaceControlsWorkWithPausedIdleAndResetToNeutral() throws {
        let library = try MiloClipLibrary(contentsOf: root.appendingPathComponent("LangLearn/Resources/MiloClips.bin"))
        var animator = MiloAnimator(library: library)
        var controls = MiloDebugControls(mouthOpening: 0, pausesBody: true)
        animator.configure(mood: .idle, mouth: 0, wanders: false, debug: controls)
        let neutral = animator.sample(delta: 0)
        controls.mouthOpening = 1
        controls.gaze = [0.2, -0.15]
        controls.forcesBlink = true
        animator.configure(mood: .idle, mouth: 0, wanders: false, debug: controls)
        let adjusted = animator.sample(delta: 0)
        #expect(adjusted.face["mouthOpen"] == 1)
        #expect(adjusted.face["blinkL"] == 1 && adjusted.face["blinkR"] == 1)
        #expect(adjusted.joints["eye_L"]?.vector != neutral.joints["eye_L"]?.vector)
        #expect(adjusted.joints["eye_R"]?.vector == adjusted.joints["eye_L"]?.vector)
        #expect(adjusted.joints["spine"]?.vector == neutral.joints["spine"]?.vector)
        controls.mouthOpening = 0
        controls.forcesBlink = false
        controls.gaze = .zero
        controls.face = ["blinkL": 0, "blinkR": 0, "smileL": 0]
        animator.configure(mood: .idle, mouth: 0, wanders: false, debug: controls)
        let reset = animator.sample(delta: 0)
        #expect(reset.face["mouthOpen"] == 0 && reset.face["blinkL"] == 0 && reset.face["smileL"] == 0)
        #expect(reset.joints["eye_L"]?.vector == neutral.joints["eye_L"]?.vector)
    }

    @Test func switchingClipsStartsFromLastBodyPoseAndGreetingDoesNotRestartOnRefresh() throws {
        let library = try MiloClipLibrary(contentsOf: root.appendingPathComponent("LangLearn/Resources/MiloClips.bin"))
        var animator = MiloAnimator(library: library)
        animator.configure(mood: .walking, mouth: 0, wanders: false)
        for _ in 0..<20 { _ = animator.sample(delta: 1 / 30) }
        let before = animator.sample(delta: 0)
        animator.configure(mood: .greeting, mouth: 0, wanders: false)
        let beginning = animator.sample(delta: 0)
        #expect(abs(simd_dot(try #require(before.joints["upper_arm_L"]).vector, try #require(beginning.joints["upper_arm_L"]).vector)) > 0.99999)
        for _ in 0..<150 { _ = animator.sample(delta: 1 / 30) }
        let settled = animator.sample(delta: 0)
        animator.configure(mood: .greeting, mouth: 0.2, wanders: false)
        let refreshed = animator.sample(delta: 0)
        #expect(settled.joints["upper_arm_L"]?.vector == refreshed.joints["upper_arm_L"]?.vector)
    }

    @Test func walkingMovesBothLegsAndStaysOnStage() throws {
        let library = try MiloClipLibrary(contentsOf: root.appendingPathComponent("LangLearn/Resources/MiloClips.bin"))
        var animator = MiloAnimator(library: library)
        animator.configure(mood: .walking, mouth: 0, wanders: true)
        var positions: [Float] = []
        var legs: [SIMD4<Float>] = []
        for _ in 0..<300 {
            let pose = animator.sample(delta: 1 / 30)
            positions.append(pose.stageOffset.x)
            legs.append(try #require(pose.joints["upper_leg_L"]).vector)
            #expect(abs(pose.stageOffset.x) <= 0.42 && pose.stageYaw.isFinite)
        }
        #expect(try #require(positions.min()) < -0.4 && #require(positions.max()) > 0.4)
        #expect(simd_distance(legs[20], legs[40]) > 0.1)
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
        #expect((manifest["blendShapes"] as? [String] ?? []).count == 15)
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
        #expect(Set(["mouthOpen", "blinkL", "blinkR", "smileL", "smileR", "mouthWide", "mouthFV"]).isSubset(of: shapes))
        for model in models where !model.jointNames.isEmpty {
            #expect(model.jointTransforms.count == model.jointNames.count)
            let left = try #require(model.jointNames.firstIndex { $0.hasSuffix("/eye_L") })
            let right = try #require(model.jointNames.firstIndex { $0.hasSuffix("/eye_R") })
            // Snow's two eye bones have opposite rolls. Horizontal gaze must
            // preserve their alignment rather than send one up and one down.
            let library = try MiloClipLibrary(contentsOf: root.appendingPathComponent("LangLearn/Resources/MiloClips.bin"))
            var animator = MiloAnimator(library: library)
            animator.configure(mood: .idle, mouth: 0, wanders: false, debug: MiloDebugControls(gaze: [0.3, 0]))
            let pose = animator.sample(delta: 0)
            let leftDirection = pose.jointRotation(for: "eye_L", resting: model.jointTransforms[left].rotation).act([0, 1, 0])
            let rightDirection = pose.jointRotation(for: "eye_R", resting: model.jointTransforms[right].rotation).act([0, 1, 0])
            #expect(simd_dot(leftDirection, rightDirection) > 0.995)
            #expect(abs(leftDirection.y - rightDirection.y) < 0.01)
        }
    }
}
