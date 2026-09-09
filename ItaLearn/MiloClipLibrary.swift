import Foundation
import simd

nonisolated struct MiloClip: Sendable {
    let name: String
    let loops: Bool
    let fps: Float
    let frames: [[simd_quatf]]
    let hipsOffsets: [SIMD3<Float>]

    var duration: Double { Double(max(1, frames.count - 1)) / Double(fps) }

    func sample(time: Double) -> (rotations: [simd_quatf], hipsOffset: SIMD3<Float>) {
        guard !frames.isEmpty else { return ([], .zero) }
        let last = max(0, frames.count - 1)
        let position: Double
        if loops && last > 0 {
            position = (max(0, time) * Double(fps)).truncatingRemainder(dividingBy: Double(last))
        } else {
            position = min(Double(last), max(0, time) * Double(fps))
        }
        let lower = min(last, Int(position.rounded(.down)))
        let upper = min(last, lower + 1)
        let amount = Float(position - Double(lower))
        let rotations = zip(frames[lower], frames[upper]).map { simd_slerp($0, $1, amount) }
        let offset = hipsOffsets[lower] + (hipsOffsets[upper] - hipsOffsets[lower]) * amount
        return (rotations, offset)
    }
}

nonisolated struct MiloClipLibrary: Sendable {
    static let supportedVersion: UInt16 = 1
    let jointNames: [String]
    let fps: UInt16
    let clips: [String: MiloClip]

    init(data: Data) throws {
        var reader = MiloBinaryReader(data: data)
        guard try reader.bytes(count: 4) == Array("MILO".utf8) else { throw MiloClipError.invalidMagic }
        let version = try reader.uint16()
        guard version == Self.supportedVersion else { throw MiloClipError.unsupportedVersion(version) }
        let jointCount = Int(try reader.uint16())
        let clipCount = Int(try reader.uint16())
        fps = try reader.uint16()
        guard jointCount > 0, jointCount <= 40, clipCount > 0, fps > 0 else { throw MiloClipError.invalidHeader }
        jointNames = try (0..<jointCount).map { _ in try reader.string() }
        var loaded: [String: MiloClip] = [:]
        for _ in 0..<clipCount {
            let name = try reader.string()
            let frameCount = Int(try reader.uint16())
            let loops = try reader.uint8() != 0
            _ = try reader.uint8()
            guard frameCount > 1 else { throw MiloClipError.invalidFrameCount(name) }
            var frames: [[simd_quatf]] = []
            frames.reserveCapacity(frameCount)
            for _ in 0..<frameCount {
                frames.append(try (0..<jointCount).map { _ in
                    simd_normalize(simd_quatf(ix: try reader.float(), iy: try reader.float(), iz: try reader.float(), r: try reader.float()))
                })
            }
            let offsets = try (0..<frameCount).map { _ in
                SIMD3<Float>(try reader.float(), try reader.float(), try reader.float())
            }
            loaded[name] = MiloClip(name: name, loops: loops, fps: Float(fps), frames: frames, hipsOffsets: offsets)
        }
        guard reader.isAtEnd else { throw MiloClipError.trailingData }
        clips = loaded
    }

    init(contentsOf url: URL) throws { try self.init(data: Data(contentsOf: url)) }

    static func bundled(in bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(forResource: "MiloClips", withExtension: "bin") else { throw MiloClipError.missingResource }
        return try Self(contentsOf: url)
    }
}

nonisolated enum MiloClipError: Error, Equatable {
    case missingResource, invalidMagic, unsupportedVersion(UInt16), invalidHeader
    case invalidFrameCount(String), truncated, invalidString, trailingData
}

private nonisolated struct MiloBinaryReader {
    let data: Data
    var offset = 0
    var isAtEnd: Bool { offset == data.count }

    mutating func bytes(count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= data.count else { throw MiloClipError.truncated }
        defer { offset += count }
        return Array(data[offset..<(offset + count)])
    }
    mutating func uint8() throws -> UInt8 { try bytes(count: 1)[0] }
    mutating func uint16() throws -> UInt16 {
        let value = try bytes(count: 2)
        return UInt16(value[0]) | UInt16(value[1]) << 8
    }
    mutating func uint32() throws -> UInt32 {
        let value = try bytes(count: 4)
        return UInt32(value[0]) | UInt32(value[1]) << 8 | UInt32(value[2]) << 16 | UInt32(value[3]) << 24
    }
    mutating func float() throws -> Float { Float(bitPattern: try uint32()) }
    mutating func string() throws -> String {
        let value = try bytes(count: Int(try uint16()))
        guard let string = String(bytes: value, encoding: .utf8) else { throw MiloClipError.invalidString }
        return string
    }
}
