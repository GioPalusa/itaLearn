import RealityKit
import SwiftUI

@MainActor
final class MiloScene {
    var subscription: EventSubscription?
    private var models: [RiggedModel] = []
    private var animator: MiloAnimator?
    private var clipCount = 0
    private let stage = Entity()
    private static var template: Entity?

    var rigSummary: String {
        let joints = Set(models.flatMap { $0.jointIndices.keys }).count
        let shapes = Set(models.flatMap { $0.faceNames }).count
        return "Snow · \(joints) leder · \(shapes) ansiktsformer · \(clipCount) klipp"
    }

    func load() async throws -> Entity {
        let asset: Entity
        if let template = Self.template {
            asset = template.clone(recursive: true)
        } else {
            guard let url = Bundle.main.url(forResource: "Milo", withExtension: "usdz") else { throw MiloAssetError.missingModel }
            let loaded = try await Entity(contentsOf: url)
            try Task.checkCancellation()
            Self.template = loaded
            asset = loaded.clone(recursive: true)
        }
        let library = try MiloClipLibrary.bundled()
        clipCount = library.clips.count
        collectModels(in: asset)
        guard !models.isEmpty else { throw MiloAssetError.missingRig }
        let modelJoints = Set(models.flatMap { $0.jointIndices.keys })
        guard Set(library.jointNames).isSubset(of: modelJoints) else { throw MiloAssetError.clipRigMismatch }
        animator = MiloAnimator(library: library)

        let bounds = asset.visualBounds(relativeTo: nil)
        let pivot = Entity()
        pivot.addChild(asset)
        asset.position -= bounds.center
        pivot.scale = SIMD3(repeating: 2.2 / max(bounds.extents.y, 0.001))
        stage.addChild(pivot)

        let scene = Entity()
        scene.addChild(stage)
        let camera = Entity()
        var optics = OrthographicCameraComponent()
        optics.scale = 1.4
        camera.components.set(optics)
        camera.look(at: .zero, from: [0.12, 0.06, 4], relativeTo: nil)
        scene.addChild(camera)
        let key = DirectionalLight()
        key.light.intensity = 2200
        key.look(at: .zero, from: [-3, 4, 5], relativeTo: nil)
        scene.addChild(key)
        let fill = DirectionalLight()
        fill.light.intensity = 900
        fill.look(at: .zero, from: [3, 1, 2], relativeTo: nil)
        scene.addChild(fill)
        return scene
    }

    func configure(
        mood: MiloMood, mouth: Float, wanders: Bool,
        debug: MiloDebugControls? = nil, restart: Bool = false
    ) {
        animator?.configure(mood: mood, mouth: mouth, wanders: wanders, debug: debug, restart: restart)
    }

    func update(delta: Double) {
        guard var animator else { return }
        let pose = animator.sample(delta: delta)
        self.animator = animator
        apply(pose: pose, smoothingDelta: delta)
    }

    func apply(pose: MiloPose, smoothingDelta: Double) {
        let smoothing = Float(1 - exp(-max(0, smoothingDelta) * 12))
        stage.position += (pose.stageOffset - stage.position) * smoothing
        for model in models {
            var joints = model.rest
            let current = model.entity.jointTransforms
            for (name, index) in model.jointIndices where index < joints.count {
                if let rotation = pose.joints[name] {
                    joints[index].rotation = model.rest[index].rotation * rotation
                }
                if name == "hips" { joints[index].translation += pose.hipsOffset }
            }
            for index in joints.indices where index < current.count {
                joints[index].rotation = simd_slerp(current[index].rotation, joints[index].rotation, smoothing)
                joints[index].translation += (current[index].translation - joints[index].translation) * (1 - smoothing)
            }
            model.entity.jointTransforms = joints
            if var component = model.entity.components[BlendShapeWeightsComponent.self] {
                for index in component.weightSet.indices {
                    var data = component.weightSet[index]
                    data.weights = BlendShapeWeights(data.weightNames.map { pose.face[$0] ?? 0 })
                    component.weightSet[index] = data
                }
                model.entity.components.set(component)
            }
        }
    }

    func stop() { subscription?.cancel(); subscription = nil }

    private func collectModels(in entity: Entity) {
        if let model = entity as? ModelEntity, !model.jointNames.isEmpty {
            let indices = Dictionary(uniqueKeysWithValues: model.jointNames.enumerated().map { index, path in
                (path.split(separator: "/").last.map(String.init) ?? path, index)
            })
            let faceNames = model.components[BlendShapeWeightsComponent.self]?.weightSet.flatMap(\.weightNames) ?? []
            models.append(RiggedModel(entity: model, rest: model.jointTransforms, jointIndices: indices, faceNames: faceNames))
        }
        for child in entity.children { collectModels(in: child) }
    }

    private struct RiggedModel {
        let entity: ModelEntity
        let rest: [Transform]
        let jointIndices: [String: Int]
        let faceNames: [String]
    }
    private enum MiloAssetError: Error { case missingModel, missingRig, clipRigMismatch }
}

struct MiloRealityView: View {
    let mood: MiloMood
    let mouth: Float
    let wanders: Bool
    let trigger: Int
    var debug: MiloDebugControls? = nil
    var onRigStatus: ((String) -> Void)? = nil
    @State private var scene = MiloScene()
    @State private var failed = false

    var body: some View {
        Group {
            if failed {
                Image("Milo").resizable().scaledToFit()
            } else {
                RealityView { content in
                    content.camera = .virtual
                    do {
                        let entity = try await scene.load()
                        try Task.checkCancellation()
                        content.add(entity)
                        scene.configure(mood: mood, mouth: mouth, wanders: wanders, debug: debug)
                        onRigStatus?(scene.rigSummary)
                        scene.subscription = content.subscribe(to: SceneEvents.Update.self) { event in
                            scene.update(delta: event.deltaTime)
                        }
                    } catch is CancellationError {
                        scene.stop()
                    } catch {
                        failed = true
                        onRigStatus?("Fallback: \(error)")
                    }
                } update: { _ in
                    scene.configure(mood: mood, mouth: mouth, wanders: wanders, debug: debug)
                } placeholder: {
                    Image("Milo").resizable().scaledToFit()
                }
            }
        }
        .onChange(of: trigger) {
            scene.configure(mood: mood, mouth: mouth, wanders: wanders, debug: debug, restart: true)
        }
        .onDisappear { scene.stop() }
        .allowsHitTesting(false)
    }
}
