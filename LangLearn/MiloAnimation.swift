import Foundation
import simd

nonisolated enum MiloMood: String, CaseIterable, Sendable {
    case still, idle, greeting, thinking, listening, speaking, encouraging, celebrating
}

nonisolated struct MiloDebugControls: Equatable, Sendable {
    var clipName: String?
    var gaze = SIMD2<Float>.zero
    var forcesBlink = false
    var face: [String: Float] = [:]
}

/// Immutable output for one rendered frame. Animation state lives in MiloAnimator.
nonisolated struct MiloPose: Sendable {
    let joints: [String: simd_quatf]
    let face: [String: Float]
    let hipsOffset: SIMD3<Float>
    let stageOffset: SIMD3<Float>

    static let neutral = Self(joints: [:], face: [:], hipsOffset: .zero, stageOffset: .zero)
}

/// Owns clip selection, transitions and all procedural facial overlays.
nonisolated struct MiloAnimator: Sendable {
    private let library: MiloClipLibrary
    private(set) var mood: MiloMood = .idle
    private var elapsed: Double = 0
    private var previousClip: String?
    private var activeClip = "Idle_Watching"
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
        if requested != activeClip || restart {
            previousClip = restart ? nil : activeClip
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
        elapsed += min(0.1, max(0, delta))
        transitionElapsed += min(0.1, max(0, delta))
        guard let clip = library.clips[activeClip] ?? library.clips.values.first else { return .neutral }
        var body = clip.sample(time: elapsed)
        if let previousClip, transitionElapsed < 0.28, let previous = library.clips[previousClip] {
            let old = previous.sample(time: elapsed)
            let amount = Float(transitionElapsed / 0.28)
            body.rotations = zip(old.rotations, body.rotations).map { simd_slerp($0, $1, amount) }
            body.hipsOffset = old.hipsOffset + (body.hipsOffset - old.hipsOffset) * amount
        }
        var joints = Dictionary(uniqueKeysWithValues: zip(library.jointNames, body.rotations))
        let t = Float(elapsed)
        let gaze = debug?.gaze ?? SIMD2<Float>(0.13 * sin(t * 0.37), 0.08 * sin(t * 0.29))
        joints["eye_L"] = simd_quatf(angle: gaze.x, axis: [0, 0, 1]) * simd_quatf(angle: gaze.y, axis: [1, 0, 0])
        joints["eye_R"] = joints["eye_L"]
        let headOverlay: simd_quatf
        switch mood {
        case .thinking: headOverlay = simd_quatf(angle: 0.11, axis: [0, 0, 1]) * simd_quatf(angle: 0.06, axis: [0, 1, 0])
        case .listening: headOverlay = simd_quatf(angle: -0.09, axis: [0, 0, 1])
        default: headOverlay = simd_quatf(angle: 0.018 * sin(t * 0.9), axis: [0, 1, 0])
        }
        joints["head"] = (joints["head"] ?? simd_quatf(angle: 0, axis: [0, 1, 0])) * headOverlay
        joints["jaw"] = simd_quatf(angle: -0.30 * (mood == .speaking ? mouth : 0), axis: [1, 0, 0])

        let blinkPhase = t.truncatingRemainder(dividingBy: 4.7)
        let blink = debug?.forcesBlink == true ? 1 : max(0, 1 - abs(blinkPhase - 4.34) / 0.10)
        var face: [String: Float] = [
            "blinkL": blink, "blinkR": blink,
            "browRaiseL": mood == .listening ? 0.42 : 0.10,
            "browRaiseR": mood == .listening ? 0.30 : 0.10,
            "browDownL": mood == .thinking ? 0.18 : 0,
            "browDownR": mood == .thinking ? 0.08 : 0,
            "smileL": mood == .celebrating || mood == .encouraging ? 0.75 : 0.28,
            "smileR": mood == .celebrating || mood == .encouraging ? 0.66 : 0.25,
            "cheekRaiseL": mood == .celebrating ? 0.45 : 0.08,
            "cheekRaiseR": mood == .celebrating ? 0.38 : 0.08,
            "mouthWide": mood == .speaking ? mouth * 0.28 : 0,
            "mouthNarrow": mood == .speaking ? mouth * 0.12 : 0,
            "mouthPucker": mood == .speaking ? max(0, sin(t * 7)) * mouth * 0.22 : 0,
            "mouthFV": mood == .speaking ? max(0, sin(t * 5 + 1)) * mouth * 0.18 : 0,
        ]
        for (name, value) in debug?.face ?? [:] { face[name] = min(1, max(0, value)) }
        var stageOffset = SIMD3<Float>.zero
        if wanders {
            let cycle = max(0, t - 4).truncatingRemainder(dividingBy: 14)
            if t > 4, cycle < 2 { stageOffset.x = 0.08 * sin(cycle * .pi) }
        }
        return MiloPose(joints: joints, face: face, hipsOffset: body.hipsOffset, stageOffset: stageOffset)
    }

    private static func clipName(for mood: MiloMood) -> String {
        switch mood {
        case .greeting, .encouraging: "Idle_Chatting"
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
