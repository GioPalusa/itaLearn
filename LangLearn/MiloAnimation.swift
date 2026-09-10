import Foundation
import simd

nonisolated enum MiloMood: String, CaseIterable, Sendable {
    case still, idle, greeting, thinking, listening, speaking, encouraging, celebrating, walking
}

nonisolated struct MiloDebugControls: Equatable, Sendable {
    var clipName: String?
    var gaze = SIMD2<Float>.zero
    var forcesBlink = false
    var face: [String: Float] = [:]
    var mouthOpening: Float?
    var pausesBody = false
    var walksAcrossStage = false
}

/// Immutable output for one rendered frame. Animation state lives in MiloAnimator.
nonisolated struct MiloPose: Sendable {
    let joints: [String: simd_quatf]
    let face: [String: Float]
    let hipsOffset: SIMD3<Float>
    let stageOffset: SIMD3<Float>
    let stageYaw: Float

    static let neutral = Self(joints: [:], face: [:], hipsOffset: .zero, stageOffset: .zero, stageYaw: 0)

    func jointRotation(for name: String, resting: simd_quatf) -> simd_quatf {
        guard let delta = joints[name] else { return resting }
        // Eye deltas use the common head space. Other deltas are bone-local.
        return name == "eye_L" || name == "eye_R" ? delta * resting : resting * delta
    }
}

/// Owns clip selection, transitions and all procedural facial overlays.
nonisolated struct MiloAnimator: Sendable {
    private let library: MiloClipLibrary
    private(set) var mood: MiloMood = .idle
    private var elapsed: Double = 0
    private var previousBody: [simd_quatf]?
    private var lastBody: [simd_quatf]?
    private var clock: Double = 0
    private var gazePosition = SIMD2<Float>.zero
    private var activeClip = "Idle_Watching"
    private var configuredClip = "Idle_Watching"
    private var transitionElapsed: Double = 1
    private var mouth: Float = 0
    private var wanders = false
    private var debug: MiloDebugControls?

    init(library: MiloClipLibrary) { self.library = library }

    mutating func configure(
        mood: MiloMood, mouth: Float, wanders: Bool,
        debug: MiloDebugControls? = nil, restart: Bool = false
    ) {
        let requested = debug?.clipName ?? Self.clipName(for: mood)
        if requested != configuredClip || restart {
            previousBody = lastBody
            configuredClip = requested
            activeClip = library.clips[requested] == nil ? "Idle_Neutral_A" : requested
            elapsed = 0
            transitionElapsed = 0
        }
        self.mood = mood
        self.mouth = mouth.isFinite ? min(1, max(0, mouth)) : 0
        self.wanders = wanders
        self.debug = debug
    }

    mutating func sample(delta: Double) -> MiloPose {
        guard mood != .still else { return .neutral }
        let dt = delta.isFinite ? min(0.1, max(0, delta)) : 0
        clock += dt
        if debug?.pausesBody != true { elapsed += dt }
        transitionElapsed += dt
        let strollPhase = clock.truncatingRemainder(dividingBy: 32) - 14
        let strolling = debug == nil && wanders && [.idle, .greeting].contains(mood) && strollPhase >= 0 && strollPhase < 8
        if strolling && activeClip != "Walk" || (!strolling && activeClip == "Walk" && mood != .walking && debug?.clipName != "Walk") {
            previousBody = lastBody
            activeClip = strolling ? "Walk" : "Idle_Watching"
            elapsed = 0
            transitionElapsed = 0
        }
        if let clip = library.clips[activeClip], !clip.loops, elapsed >= clip.duration, debug?.clipName == nil {
            previousBody = lastBody
            activeClip = "Idle_Watching"
            elapsed = 0
            transitionElapsed = 0
        }
        guard let clip = library.clips[activeClip] ?? library.clips.values.first else { return .neutral }
        var body = clip.sample(time: elapsed)
        if let previousBody, transitionElapsed < 0.4 {
            let t = Float(transitionElapsed / 0.4)
            let amount = t * t * (3 - 2 * t)
            body.rotations = zip(previousBody, body.rotations).map { simd_slerp($0, $1, amount) }
        }
        lastBody = body.rotations
        var joints = Dictionary(uniqueKeysWithValues: zip(library.jointNames, body.rotations))
        let t = Float(clock)
        let gazeTargets: [SIMD2<Float>] = [.zero, [0.09, 0.02], .zero, [-0.07, -0.03], .zero]
        let target = debug?.gaze ?? gazeTargets[Int(clock / 2.3) % gazeTargets.count]
        if debug != nil { gazePosition = target } else { gazePosition += (target - gazePosition) * Float(1 - exp(-dt * 16)) }
        let gaze = gazePosition
        // Both eyes share head-space yaw/pitch; their bind rolls differ.
        joints["eye_L"] = simd_quatf(angle: gaze.x, axis: [0, 1, 0]) * simd_quatf(angle: -gaze.y, axis: [1, 0, 0])
        joints["eye_R"] = joints["eye_L"]
        let headOverlay: simd_quatf
        switch mood {
        case .thinking: headOverlay = simd_quatf(angle: 0.11, axis: [0, 0, 1]) * simd_quatf(angle: 0.06, axis: [0, 1, 0])
        case .listening: headOverlay = simd_quatf(angle: -0.09, axis: [0, 0, 1])
        default: headOverlay = simd_quatf(angle: 0.018 * sin(t * 0.9), axis: [0, 1, 0])
        }
        joints["head"] = (joints["head"] ?? simd_quatf(angle: 0, axis: [0, 1, 0])) * headOverlay
        // Full jaw/lip/teeth deformation is baked from Snow into mouthOpen.
        // Applying the old jaw bone as well would deform the mouth twice.
        let opening = debug?.mouthOpening ?? (mood == .speaking ? mouth : 0)

        let blinkPhase = t.truncatingRemainder(dividingBy: 17)
        let blink = [Float(3.1), 7.8, 10.4, 16.2].map { max(0, 1 - abs(blinkPhase - $0) / 0.12) }.max() ?? 0
        var face: [String: Float] = [
            "mouthOpen": opening.isFinite ? min(1, max(0, opening)) : 0,
            "blinkL": blink, "blinkR": blink,
            "browRaiseL": mood == .listening ? 0.15 : 0.02,
            "browRaiseR": mood == .listening ? 0.12 : 0.02,
            "browDownL": mood == .thinking ? 0.18 : 0,
            "browDownR": mood == .thinking ? 0.08 : 0,
            "smileL": mood == .celebrating || mood == .encouraging ? 0.45 : 0.10,
            "smileR": mood == .celebrating || mood == .encouraging ? 0.40 : 0.10,
            "cheekRaiseL": mood == .celebrating ? 0.45 : 0.08,
            "cheekRaiseR": mood == .celebrating ? 0.38 : 0.08,
            "mouthWide": mood == .speaking ? mouth * 0.28 : 0,
            "mouthNarrow": mood == .speaking ? mouth * 0.12 : 0,
            "mouthPucker": mood == .speaking ? max(0, sin(t * 7)) * mouth * 0.22 : 0,
            "mouthFV": mood == .speaking ? max(0, sin(t * 5 + 1)) * mouth * 0.18 : 0,
        ]
        for (name, value) in debug?.face ?? [:] { face[name] = value.isFinite ? min(1, max(0, value)) : 0 }
        if debug?.forcesBlink == true { face["blinkL"] = 1; face["blinkR"] = 1 }
        var stageOffset = SIMD3<Float>.zero
        var stageYaw: Float = 0
        if strolling || (mood == .walking && wanders) || debug?.walksAcrossStage == true {
            let cycle = Float(elapsed).truncatingRemainder(dividingBy: 8)
            // Feet and stage motion use the same clock. Turn gently at each end.
            stageOffset.x = 0.42 * sin(cycle * .pi / 4)
            stageYaw = .pi / 2 * tanh(5 * cos(cycle * .pi / 4))
        }
        return MiloPose(joints: joints, face: face, hipsOffset: body.hipsOffset, stageOffset: stageOffset, stageYaw: stageYaw)
    }

    private static func clipName(for mood: MiloMood) -> String {
        switch mood {
        case .greeting: "Wave"
        case .walking: "Walk"
        case .encouraging: "Idle_Chatting"
        case .celebrating: "Idle_Chatting02"
        case .thinking: "Idle_LookAround02"
        case .listening: "Idle_LookAround"
        case .speaking: "Idle_Neutral_A"
        case .still, .idle: "Idle_Watching"
        }
    }
}

/// A generation token prevents old synthesis/playback callbacks reviving cancelled speech.
nonisolated struct SpeechPlaybackState: Sendable {
    enum Phase: Equatable, Sendable { case idle, preparing, playing }
    private(set) var generation = UUID()
    private(set) var phase: Phase = .idle
    private(set) var mouth: Float = 0
    mutating func begin() -> UUID { generation = UUID(); phase = .preparing; mouth = 0; return generation }
    @discardableResult mutating func start(_ token: UUID) -> Bool {
        guard token == generation, phase == .preparing else { return false }
        phase = .playing; return true
    }
    mutating func meter(decibels: Float, token: UUID) {
        guard token == generation, phase == .playing else { return }
        guard decibels.isFinite, decibels > -48 else { mouth = 0; return }
        let target = min(1, max(0, (decibels + 48) / 38))
        mouth += (target - mouth) * (target > mouth ? 0.65 : 0.4)
    }
    @discardableResult mutating func finish(_ token: UUID) -> Bool {
        guard token == generation, phase != .idle else { return false }
        phase = .idle; mouth = 0; return true
    }
    mutating func cancel() { generation = UUID(); phase = .idle; mouth = 0 }
}
