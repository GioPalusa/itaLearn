import Foundation
import simd

nonisolated enum MiloMood: String, CaseIterable, Sendable {
    case still, idle, greeting, thinking, listening, speaking, encouraging, celebrating, walking, laughing, applauding, curious, enthusiastic, joyful, leanIn, dancing, presenting
}

nonisolated struct MiloDebugControls: Equatable, Sendable {
    var clipName: String?
    /// Nil keeps the natural gaze, including when previewing a body clip.
    var gaze: SIMD2<Float>?
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
    var stageScale: Float = 1
    var preservesBodyContacts = false

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
    private(set) var completedReaction = false
    private var elapsed: Double = 0
    private var previousBody: [simd_quatf]?
    private var lastBody: [simd_quatf]?
    private var clock: Double = 0
    private var reactionTime: Double = 0
    private var gazePosition = SIMD2<Float>.zero
    private var facialGazePosition = SIMD2<Float>.zero
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
        if requested != configuredClip || mood != self.mood || restart {
            previousBody = lastBody
            configuredClip = requested
            activeClip = library.clips[requested] == nil ? "Idle_Neutral_A" : requested
            elapsed = 0
            reactionTime = 0
            transitionElapsed = 0
            completedReaction = false
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
        reactionTime += dt
        let expressive = [.curious, .enthusiastic, .joyful, .leanIn].contains(mood)
        if expressive && reactionTime >= 4.5 { completedReaction = true }
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
            completedReaction = true
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
        let laughing = mood == .laughing && !completedReaction
        let applauding = mood == .applauding && !completedReaction
        let target = Self.boundedGaze(debug?.gaze ?? Self.naturalGaze(at: clock, joints: joints))
        if debug?.gaze != nil { gazePosition = target } else { gazePosition += (target - gazePosition) * Float(1 - exp(-dt * 16)) }
        let gaze = gazePosition
        // Eyes lead a glance; the lids and brows settle a little more slowly.
        if debug?.gaze != nil { facialGazePosition = gaze } else { facialGazePosition += (gaze - facialGazePosition) * Float(1 - exp(-dt * 6)) }
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
        let laughPulse = max(0, sin(Float(elapsed) * 15))
        let speechFace = mood == .speaking ? Self.speechFace(amplitude: mouth, time: t) : [:]
        let opening = debug?.mouthOpening ?? (laughing ? 0.18 + 0.28 * laughPulse : speechFace["mouthOpen", default: 0])

        let blink = Self.idleBlink(at: t)
        let restingFace = Self.restingFace(at: t, gaze: facialGazePosition)
        // Keep a soft, welcoming smile even between idle microexpressions.
        let idleSmileLift: Float = mood == .idle ? 0.18 : 0
        var face: [String: Float] = [
            "mouthOpen": opening.isFinite ? min(1, max(0, opening)) : 0,
            "blinkL": restingFace.lid + (1 - restingFace.lid) * blink,
            "blinkR": restingFace.lid + (1 - restingFace.lid) * blink,
            "browRaiseL": restingFace.browL + (mood == .listening ? 0.10 : 0),
            "browRaiseR": restingFace.browR + (mood == .listening ? 0.08 : 0),
            "browDownL": mood == .thinking ? 0.18 : 0,
            "browDownR": mood == .thinking ? 0.08 : 0,
            "smileL": mood == .celebrating || mood == .encouraging ? 0.45 : restingFace.smileL + idleSmileLift,
            "smileR": mood == .celebrating || mood == .encouraging ? 0.40 : restingFace.smileR + idleSmileLift,
            "cheekRaiseL": mood == .celebrating ? 0.45 : restingFace.smileL * 0.4,
            "cheekRaiseR": mood == .celebrating ? 0.38 : restingFace.smileR * 0.4,
            "mouthWide": speechFace["mouthWide", default: 0],
            "mouthNarrow": speechFace["mouthNarrow", default: 0],
            "mouthPucker": speechFace["mouthPucker", default: 0],
            "mouthFV": speechFace["mouthFV", default: 0],
        ]
        if laughing || applauding {
            face["smileL"] = laughing ? 0.55 : 0.38
            face["smileR"] = laughing ? 0.50 : 0.35
            face["cheekRaiseL"] = 0.12
            face["cheekRaiseR"] = 0.12
        }
        if laughing {
            face["blinkL"] = max(face["blinkL", default: blink], 0.20 + 0.16 * laughPulse)
            face["blinkR"] = face["blinkL"]
        }
        // Ease into and out of authored expressions; blink remains independent.
        let attack = min(1, Float(reactionTime / 0.55))
        let release = min(1, max(0, Float((4.5 - reactionTime) / 0.8)))
        let expression = expressive ? attack * attack * (3 - 2 * attack) * release * release * (3 - 2 * release) : 0
        var lean: Float = 0
        func blend(_ name: String, _ target: Float) {
            face[name] = face[name, default: 0] * (1 - expression) + target * expression
        }
        switch mood {
        case .curious:
            blend("browRaiseL", 0.68); blend("browRaiseR", 0.28)
            blend("smileL", 0.22); blend("smileR", 0.14)
            blend("mouthOpen", 0.07); blend("mouthPucker", 0.12)
            lean = 0.65 * expression
        case .enthusiastic:
            blend("browRaiseL", 0.65); blend("browRaiseR", 0.60)
            blend("smileL", 0.65); blend("smileR", 0.60)
            blend("cheekRaiseL", 0.22); blend("cheekRaiseR", 0.22)
            blend("mouthOpen", 0.16 + 0.05 * sin(Float(reactionTime) * 5))
            lean = 0.35 * expression
        case .joyful:
            blend("smileL", 0.72); blend("smileR", 0.65)
            blend("cheekRaiseL", 0.3); blend("cheekRaiseR", 0.28)
            blend("browRaiseL", 0.25); blend("browRaiseR", 0.2)
            blend("mouthOpen", 0.12)
        case .leanIn: lean = expression
        default: break
        }
        if expression > 0 {
            // Small additive poses keep the motion readable without extreme bends.
            let nod = mood == .enthusiastic ? 0.06 * sin(Float(reactionTime) * 5) : 0
            joints["head"] = simd_quatf(angle: (mood == .curious ? 0.14 : nod) * expression, axis: [0, 0, 1]) * joints["head", default: simd_quatf()]
            joints["spine"] = simd_quatf(angle: 0.12 * lean, axis: [1, 0, 0]) * joints["spine", default: simd_quatf()]
            joints["chest"] = simd_quatf(angle: 0.08 * lean, axis: [1, 0, 0]) * joints["chest", default: simd_quatf()]
        }
        for (name, value) in debug?.face ?? [:] { face[name] = value.isFinite ? min(1, max(0, value)) : 0 }
        if debug?.forcesBlink == true { face["blinkL"] = 1; face["blinkR"] = 1 }
        var stageOffset = SIMD3<Float>(0, 0, 0.12 * lean)
        var stageYaw: Float = 0
        if strolling || (mood == .walking && wanders) || debug?.walksAcrossStage == true {
            let cycle = Float(elapsed).truncatingRemainder(dividingBy: 8)
            // Feet and stage motion use the same clock. Turn gently at each end.
            stageOffset.x = 0.42 * sin(cycle * .pi / 4)
            stageYaw = .pi / 2 * tanh(5 * cos(cycle * .pi / 4))
        }
        return MiloPose(joints: joints, face: face, hipsOffset: body.hipsOffset, stageOffset: stageOffset, stageYaw: stageYaw, stageScale: 1 + 0.08 * lean, preservesBodyContacts: activeClip == "Applaud")
    }

    private static func boundedGaze(_ gaze: SIMD2<Float>) -> SIMD2<Float> {
        [gaze.x.isFinite ? min(0.32, max(-0.32, gaze.x)) : 0,
         gaze.y.isFinite ? min(0.22, max(-0.22, gaze.y)) : 0]
    }

    private static func naturalGaze(at time: Double, joints: [String: simd_quatf]) -> SIMD2<Float> {
        // Uneven holds give him time to meet the learner's eyes between glances.
        let glances: [(end: Double, direction: SIMD2<Float>)] = [
            (1.7, .zero), (3.1, [-0.20, 0.03]), (5.8, .zero),
            (7.2, [0.18, 0.16]), (8.5, [0.05, -0.10]), (11.4, .zero),
            (12.8, [-0.16, -0.04]), (15.1, .zero), (16.3, [0.17, 0.04]), (18.7, .zero),
        ]
        let phase = time.truncatingRemainder(dividingBy: 18.7)
        let glance = glances.first { phase < $0.end }?.direction ?? .zero
        // The source clips turn the neck/head but contain neutral eye tracks.
        // Add a restrained gaze in the same direction instead of leaving the
        // pupils fixed while he looks around. Snow's head-local forward is +Z.
        let direction = ((joints["neck"] ?? simd_quatf()) * (joints["head"] ?? simd_quatf())).act([0, 0, 1])
        let headGaze = SIMD2<Float>(atan2(direction.x, direction.z), asin(min(1, max(-1, direction.y))))
        return glance + headGaze * SIMD2<Float>(0.45, 0.35)
    }

    private static func restingFace(at time: Float, gaze: SIMD2<Float>) -> (lid: Float, browL: Float, browR: Float, smileL: Float, smileR: Float) {
        // Small, separated gestures, with a little asymmetry and quiet holds.
        // Closed-mouth smiles never touch the speech/jaw channels.
        func gesture(center: Float, halfWidth: Float, period: Float, delay: Float = 0) -> Float {
            let phase = max(0, time - delay).truncatingRemainder(dividingBy: period)
            let amount = max(0, 1 - abs(phase - center) / halfWidth)
            return amount * amount * (3 - 2 * amount)
        }
        let smile = gesture(center: 4.2, halfWidth: 1.7, period: 17.3)
        let secondSmile = gesture(center: 12.1, halfWidth: 2.1, period: 17.3)
        let brow = gesture(center: 6.7, halfWidth: 1.2, period: 19.1)
        let otherBrow = gesture(center: 14.4, halfWidth: 1.5, period: 19.1)
        let up = min(1, max(0, gaze.y / 0.20))
        let down = min(1, max(0, -gaze.y / 0.20))
        return (
            lid: 0.20 + 0.015 * sin(time * 0.73) + 0.09 * down - 0.035 * up,
            browL: 0.025 + 0.24 * up + 0.10 * brow + 0.035 * otherBrow,
            browR: 0.025 + 0.22 * up + 0.065 * brow + 0.09 * otherBrow,
            smileL: 0.075 + 0.10 * smile + 0.045 * secondSmile,
            smileR: 0.075 + 0.075 * gesture(center: 4.2, halfWidth: 1.7, period: 17.3, delay: 0.18) + 0.065 * secondSmile
        )
    }

    /// Turns the speech meter into a smooth sequence of distinct lip shapes.
    /// The audio amplitude controls emphasis while time supplies articulation;
    /// this keeps speech readable even though AVSpeechSynthesizer has no phoneme API.
    private static func speechFace(amplitude: Float, time: Float) -> [String: Float] {
        guard amplitude.isFinite, amplitude > 0.025 else { return [:] }
        let strength = min(1, max(0, amplitude))
        let shapes: [(open: Float, wide: Float, narrow: Float, pucker: Float, fv: Float)] = [
            (0.86, 0.62, 0, 0, 0),
            (1.00, 0.12, 0, 0, 0),
            (0.42, 0, 0.60, 0, 0),
            (0.78, 0.35, 0, 0, 0),
            (0.30, 0, 0.08, 0.72, 0),
            (0.70, 0.52, 0, 0, 0),
            (0.18, 0, 0, 0, 0.70),
            (0.92, 0.18, 0, 0, 0),
        ]
        let position = max(0, time) * 5.2
        let lower = Int(floor(position)) % shapes.count
        let upper = (lower + 1) % shapes.count
        let fraction = position - floor(position)
        let blend = fraction * fraction * (3 - 2 * fraction)
        func interpolate(_ value: KeyPath<(open: Float, wide: Float, narrow: Float, pucker: Float, fv: Float), Float>) -> Float {
            let start = shapes[lower][keyPath: value]
            return (start + (shapes[upper][keyPath: value] - start) * blend) * strength
        }
        return [
            "mouthOpen": interpolate(\.open) * 0.68,
            "mouthWide": interpolate(\.wide),
            "mouthNarrow": interpolate(\.narrow),
            "mouthPucker": interpolate(\.pucker),
            "mouthFV": interpolate(\.fv),
        ]
    }

    /// Three natural blinks per cycle, including an occasional quick double blink.
    private static func idleBlink(at time: Float) -> Float {
        let phase = max(0, time).truncatingRemainder(dividingBy: 9.4)
        func pulse(center: Float) -> Float {
            let offset = phase - center
            let distance = abs(offset)
            if distance <= 0.025 { return 1 }
            let duration: Float = offset < 0 ? 0.085 : 0.14
            let progress = min(1, max(0, (distance - 0.025) / duration))
            let smooth = progress * progress * (3 - 2 * progress)
            return 1 - smooth
        }
        return [pulse(center: 2.55), pulse(center: 6.85), pulse(center: 7.18)].max() ?? 0
    }

    private static func clipName(for mood: MiloMood) -> String {
        switch mood {
        case .curious, .enthusiastic, .joyful, .leanIn: "Idle_Watching"
        case .dancing: "Dance"
        case .presenting: "Present"
        case .greeting: "Wave"
        case .walking: "Walk"
        case .laughing: "Laugh"
        case .applauding: "Applaud"
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
