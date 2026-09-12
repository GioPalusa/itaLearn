import RealityKit
import SwiftUI

/// Loads the two heavy Milo assets once per process instead of once per avatar.
/// The 14 MB rig and the 3 MB clip binary used to be read inline in every
/// `MiloScene.load()`, which stalled the main thread during launch.
@MainActor
enum MiloAssets {
    private static var model: Task<Entity, Error>?
    private static var clips: Task<MiloClipLibrary, Error>?
    private static var environment: EnvironmentResource?

    static func studioEnvironment() async throws -> EnvironmentResource {
        if let environment { return environment }
        guard let url = Bundle.main.url(forResource: "MiloSurface_studio", withExtension: "png"),
              let image = UIImage(contentsOfFile: url.path)?.cgImage else {
            throw CocoaError(.fileNoSuchFile)
        }
        let resource = try await EnvironmentResource(equirectangular: image)
        environment = resource
        return resource
    }
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
            let entity = try await Entity(contentsOf: url)
            try await MiloSurfaceMaterials.apply(to: entity)
            return entity
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
        let studio = Entity()
        studio.components.set(ImageBasedLightComponent(source: .single(try await MiloAssets.studioEnvironment()), intensityExponent: 6.3))
        scene.addChild(studio)
        for model in models {
            model.entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: studio))
        }
        let camera = Entity()
        var optics = OrthographicCameraComponent()
        optics.scale = 1.4
        camera.components.set(optics)
        camera.look(at: .zero, from: [0.12, 0.06, 4], relativeTo: nil)
        scene.addChild(camera)
        let key = DirectionalLight()
        key.light.intensity = 2400
        key.light.color = .init(red: 1, green: 0.95, blue: 0.89, alpha: 1)
        key.look(at: .zero, from: [-3, 4, 5], relativeTo: nil)
        scene.addChild(key)
        let fill = DirectionalLight()
        fill.light.intensity = 800
        fill.light.color = .init(red: 0.90, green: 0.94, blue: 1, alpha: 1)
        fill.look(at: .zero, from: [2, 2, 5], relativeTo: nil)
        scene.addChild(fill)
        let rim = DirectionalLight()
        rim.light.intensity = 450
        rim.look(at: .zero, from: [1, 3, -3], relativeTo: nil)
        scene.addChild(rim)
        return scene
    }

    func configure(
        mood: MiloMood, mouth: Float, wanders: Bool,
        debug: MiloDebugControls? = nil, restart: Bool = false, zoom: Float = 1, pinsFaceFocus: Bool = false
    ) {
        animator?.configure(mood: mood, mouth: mouth, wanders: wanders, debug: debug, restart: restart)
        let clampedZoom = min(4.5, max(1, zoom.isFinite ? zoom : 1))
        self.zoom = clampedZoom
        characterPivot?.scale = SIMD3(repeating: baseScale * clampedZoom)
        // Keep the face near the camera's optical center while the body grows.
        let focusAmount: Float = pinsFaceFocus ? 1 : min(1, (clampedZoom - 1) / 1.5)
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
            // Clip sampling and the animator already blend poses. A second low-pass
            // filter shortens fast hand travel and destroys authored palm contacts.
            let bodySmoothing: Float = pose.preservesBodyContacts ? 1 : smoothing
            for index in joints.indices where index < current.count {
                // Gaze is already eased with the eyelids/brows in the animator.
                // Filtering the eyes again makes them lag behind the expression.
                let isEye = index == model.jointIndices["eye_L"] || index == model.jointIndices["eye_R"]
                joints[index].rotation = simd_slerp(current[index].rotation, joints[index].rotation, isEye ? 1 : bodySmoothing)
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
    var pinsFaceFocus = false
    var placeholderSize: CGFloat? = nil
    var debug: MiloDebugControls? = nil
    var onRigStatus: ((String) -> Void)? = nil
    var onAnimationCompleted: ((Int) -> Void)? = nil
    @State private var scene = MiloScene()
    @State private var failed = false

    var body: some View {
        Group {
            if failed {
                Image("Milo").resizable().scaledToFit().frame(width: placeholderSize)
            } else {
                RealityView { content in
                    content.camera = .virtual
                    do {
                        let entity = try await scene.load()
                        try Task.checkCancellation()
                        content.add(entity)
                        scene.configure(mood: mood, mouth: mouth, wanders: wanders, debug: debug, zoom: zoom, pinsFaceFocus: pinsFaceFocus)
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
                    scene.configure(mood: mood, mouth: mouth, wanders: wanders, debug: debug, zoom: zoom, pinsFaceFocus: pinsFaceFocus)
                } placeholder: {
                    Image("Milo").resizable().scaledToFit().frame(width: placeholderSize)
                }
            }
        }
        .onChange(of: trigger) {
            scene.configure(mood: mood, mouth: mouth, wanders: wanders, debug: debug, restart: true, zoom: zoom, pinsFaceFocus: pinsFaceFocus)
        }
        .onDisappear { scene.stop() }
        .allowsHitTesting(false)
    }
}


/// Applied once to the cached template; cloned avatars share the GPU textures.
/// Snow's original UVs remain unchanged. Scalar/normal maps must not use sRGB.
@MainActor
private enum MiloSurfaceMaterials {
    static func apply(to entity: Entity) async throws {
        var maps: [String: TextureResource] = [:]
        let names = ["head_roughness", "body_roughness", "head_sss_color", "body_sss_color",
                     "head_sss_value", "body_sss_value", "hair_roughness", "shirt_roughness",
                     "pants_roughness", "shoes_roughness", "shirt_normal", "pants_normal", "shoes_normal"]
        for name in names {
            guard let url = Bundle.main.url(forResource: "MiloSurface_" + name, withExtension: "png") else {
                throw CocoaError(.fileNoSuchFile)
            }
            let semantic: TextureResource.Semantic = name.hasSuffix("normal") ? .normal :
                (name.hasSuffix("color") ? .color : .scalar)
            maps[name] = try await TextureResource(contentsOf: url, options: .init(semantic: semantic))
        }
        func texture(_ name: String) -> MaterialParameters.Texture? {
            maps[name].map { MaterialParameters.Texture($0) }
        }
        func visit(_ node: Entity) {
            if var model = node.components[ModelComponent.self] {
                model.materials = model.materials.map { material in
                    guard var pbr = material as? PhysicallyBasedMaterial else { return material }
                    let name = pbr.name ?? ""
                    let part = ["head", "body", "shirt", "pants", "shoes", "eyes", "hair"].first {
                        name.localizedCaseInsensitiveContains($0)
                    }
                    pbr.metallic = .init(floatLiteral: 0)
                    pbr.clearcoat = .init(floatLiteral: 0)
                    switch part {
                    case "head", "body":
                        let prefix = part!
                        pbr.roughness = .init(scale: 1, texture: texture(prefix + "_roughness"))
                        pbr.specular = 0.12
                        // Small scattering radius in the rig's metre scale; avoid waxy skin.
                        if #available(iOS 27.0, *) {
                            pbr.subsurfaceWeight = .init(scale: 0.18, texture: texture(prefix + "_sss_value"))
                            pbr.subsurfaceColor = .init(texture: texture(prefix + "_sss_color"))
                            pbr.subsurfaceRadius = 0.0015
                        }
                    case "shirt", "pants", "shoes":
                        let prefix = part!
                        pbr.roughness = .init(texture: texture(prefix + "_roughness"))
                        pbr.normal = .init(texture: texture(prefix + "_normal"))
                        pbr.specular = 0.18
                    case "hair":
                        pbr.roughness = .init(texture: texture("hair_roughness"))
                        pbr.specular = 0.10
                    case "eyes":
                        pbr.roughness = 0.25
                        pbr.specular = 0.35
                    default: break
                    }
                    return pbr
                }
                node.components.set(model)
            }
            for child in node.children { visit(child) }
        }
        visit(entity)
    }
}
