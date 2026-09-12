import RealityKit
import SwiftUI

/// Loads the two heavy Milo assets once per process instead of once per avatar.
/// The 14 MB rig and the 3 MB clip binary used to be read inline in every
/// `MiloScene.load()`, which stalled the main thread during launch.
@MainActor
enum MiloAssets {
    private static var model: Task<Entity, Error>?
    private static var clips: Task<MiloClipLibrary, Error>?
    private static var modelIsLoaded = false
    private static var clipsAreLoaded = false
    /// True once both assets are cached, so later avatars can skip the launch delay.
    static var isWarm: Bool { modelIsLoaded && clipsAreLoaded }

    static func modelTemplate() async throws -> Entity {
        if let model { return try await model.value }
        // Detached so a disappearing avatar cannot cancel the shared load.
        let task = Task.detached { @MainActor in
            guard let url = Bundle.main.url(forResource: "Milo", withExtension: "usdz") else {
                throw MiloAssetError.missingModel
            }
            return try await Entity(contentsOf: url)
        }
        model = task
        do {
            let entity = try await task.value
            modelIsLoaded = true
            return entity
        } catch {
            model = nil
            throw error
        }
    }

    static func clipLibrary() async throws -> MiloClipLibrary {
        if let clips { return try await clips.value }
        let task = Task.detached(priority: .userInitiated) { try MiloClipLibrary.bundled() }
        clips = task
        do {
            let library = try await task.value
            clipsAreLoaded = true
            return library
        } catch {
            clips = nil
            throw error
        }
    }
}

nonisolated enum MiloAssetError: Error { case missingModel, missingRig, clipRigMismatch }

@MainActor
final class MiloScene {
    var subscription: EventSubscription?
    var onAnimationCompleted: (() -> Void)?
    private var models: [RiggedModel] = []
    private var animator: MiloAnimator?
    private var clipCount = 0
    private let stage = Entity()
    private var characterPivot: Entity?
    private var baseScale: Float = 1
    private var zoom: Float = 1
    private var faceFocus = SIMD3<Float>(0, 0.8, 0)

    var rigSummary: String {
        let joints = Set(models.flatMap { $0.jointIndices.keys }).count
        let shapes = Set(models.flatMap { $0.faceNames }).count
        return "Snow · \(joints) leder · \(shapes) ansiktsformer · \(clipCount) klipp"
    }

    func load() async throws -> Entity {
        // Parse the clips off the main thread while the rig streams in.
        async let clipLoad = MiloAssets.clipLibrary()
        let template: Entity
        do {
            template = try await MiloAssets.modelTemplate()
        } catch {
            _ = try? await clipLoad
            throw error
        }
        let library = try await clipLoad
        try Task.checkCancellation()
        let asset = template.clone(recursive: true)
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
        baseScale = 2.2 / max(bounds.extents.y, 0.001)
        pivot.scale = SIMD3(repeating: baseScale)
        characterPivot = pivot
        stage.addChild(pivot)
        if let rig = models.first, let eye = rig.jointIndices["eye_L"] {
            // Skinned visualBounds can describe the whole skeleton, even for
            // the eye mesh. Derive the focus from the actual eye bind joint.
            let eyePath = rig.entity.jointNames[eye]
            let ancestors = rig.entity.jointNames.indices.filter {
                let path = rig.entity.jointNames[$0]
                return eyePath == path || eyePath.hasPrefix(path + "/")
            }.sorted { rig.entity.jointNames[$0].count < rig.entity.jointNames[$1].count }
            var bind = matrix_identity_float4x4
            for index in ancestors { bind *= rig.rest[index].matrix }
            let point = SIMD3<Float>(bind.columns.3.x, bind.columns.3.y, bind.columns.3.z)
            faceFocus = rig.entity.convert(position: point, to: pivot) * baseScale
            faceFocus.x = 0
        }

        let scene = Entity()
        scene.addChild(stage)
        let camera = Entity()
        var optics = OrthographicCameraComponent()
        optics.scale = 1.4
        camera.components.set(optics)
        camera.look(at: .zero, from: [0.12, 0.06, 4], relativeTo: nil)
        scene.addChild(camera)
        let key = DirectionalLight()
        key.light.intensity = 1800
        key.light.color = .init(red: 1, green: 0.95, blue: 0.89, alpha: 1)
        key.look(at: .zero, from: [-3, 4, 5], relativeTo: nil)
        scene.addChild(key)
        let fill = DirectionalLight()
        fill.light.intensity = 1800
        fill.light.color = .init(red: 0.90, green: 0.94, blue: 1, alpha: 1)
        fill.look(at: .zero, from: [2, 2, 5], relativeTo: nil)
        scene.addChild(fill)
        let rim = DirectionalLight()
        rim.light.intensity = 1000
        rim.look(at: .zero, from: [1, 3, -3], relativeTo: nil)
        scene.addChild(rim)
        return scene
    }

    func configure(
        mood: MiloMood, mouth: Float, wanders: Bool,
        debug: MiloDebugControls? = nil, restart: Bool = false, zoom: Float = 1
    ) {
        animator?.configure(mood: mood, mouth: mouth, wanders: wanders, debug: debug, restart: restart)
        let clampedZoom = min(4.5, max(1, zoom.isFinite ? zoom : 1))
        self.zoom = clampedZoom
        characterPivot?.scale = SIMD3(repeating: baseScale * clampedZoom)
        // Keep the face near the camera's optical center while the body grows.
        let focusAmount = min(1, (clampedZoom - 1) / 1.5)
        characterPivot?.position = -faceFocus * clampedZoom * focusAmount
        // Apply slider-driven face/gaze changes immediately instead of waiting
        // for the next SceneEvents.Update callback.
        if var animator {
            let pose = animator.sample(delta: 0)
            self.animator = animator
            apply(pose: pose, smoothingDelta: 1)
        }
    }

    func update(delta: Double) {
        guard var animator else { return }
        let hadCompleted = animator.completedReaction
        let pose = animator.sample(delta: delta)
        self.animator = animator
        apply(pose: pose, smoothingDelta: delta)
        if !hadCompleted && animator.completedReaction { onAnimationCompleted?() }
    }

    func apply(pose: MiloPose, smoothingDelta: Double) {
        let smoothing = Float(1 - exp(-max(0, smoothingDelta) * 12))
        stage.position += (pose.stageOffset - stage.position) * smoothing
        stage.scale += (SIMD3(repeating: pose.stageScale) - stage.scale) * smoothing
        stage.orientation = simd_slerp(stage.orientation, simd_quatf(angle: pose.stageYaw, axis: [0, 1, 0]), smoothing)
        for model in models {
            var joints = model.rest
            let current = model.entity.jointTransforms
            for (name, index) in model.jointIndices where index < joints.count {
                joints[index].rotation = pose.jointRotation(for: name, resting: model.rest[index].rotation)
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

    func stop() {
        subscription?.cancel()
        subscription = nil
        onAnimationCompleted = nil
    }

    private func collectModels(in entity: Entity) {
        if let model = entity as? ModelEntity, !model.jointNames.isEmpty {
            if var mesh = model.model {
                mesh.materials = mesh.materials.map { material in
                    guard var physical = material as? PhysicallyBasedMaterial else { return material }
                    // Snow's recessed pupil is authored as a double-sided
                    // surface. Preserve this when RealityKit imports the skin.
                    physical.faceCulling = .none
                    return physical
                }
                model.model = mesh
            }
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
}

struct MiloRealityView: View {
    let mood: MiloMood
    let mouth: Float
    let wanders: Bool
    let trigger: Int
    let zoom: Float
    var debug: MiloDebugControls? = nil
    var onRigStatus: ((String) -> Void)? = nil
    var onAnimationCompleted: ((Int) -> Void)? = nil
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
                        scene.configure(mood: mood, mouth: mouth, wanders: wanders, debug: debug, zoom: zoom)
                        scene.onAnimationCompleted = { [onAnimationCompleted, trigger] in onAnimationCompleted?(trigger) }
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
                    scene.onAnimationCompleted = { [onAnimationCompleted, trigger] in onAnimationCompleted?(trigger) }
                    scene.configure(mood: mood, mouth: mouth, wanders: wanders, debug: debug, zoom: zoom)
                } placeholder: {
                    Image("Milo").resizable().scaledToFit()
                }
            }
        }
        .onChange(of: trigger) {
            scene.configure(mood: mood, mouth: mouth, wanders: wanders, debug: debug, restart: true, zoom: zoom)
        }
        .onDisappear { scene.stop() }
        .allowsHitTesting(false)
    }
}
