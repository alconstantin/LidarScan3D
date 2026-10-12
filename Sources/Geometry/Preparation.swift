import Foundation
import simd

/// Saved instructions always start from the original mesh; no edited mesh replaces it.
struct Preparation: Codable, Equatable, Sendable {
    var version = 1
    var rotation = SIMD4<Float>(0, 0, 0, 1)
    var scalePercent: Double = 100
    var removeSupport = false
    var removeFragments = false
    var smoothing: MeshSmoothingLevel = .off
    var fillHoles = false
    var flatBase = false
    var trimFraction: Double = 0

    init(version: Int = 1, rotation: SIMD4<Float> = SIMD4(0, 0, 0, 1), scalePercent: Double = 100,
         removeSupport: Bool = false, removeFragments: Bool = false, smoothing: MeshSmoothingLevel = .off,
         fillHoles: Bool = false, flatBase: Bool = false, trimFraction: Double = 0) {
        self.version = version
        self.rotation = rotation
        self.scalePercent = scalePercent
        self.removeSupport = removeSupport
        self.removeFragments = removeFragments
        self.smoothing = smoothing
        self.fillHoles = fillHoles
        self.flatBase = flatBase
        self.trimFraction = trimFraction
    }

    /// Steps added after version 1 are optional in the file, so recipes saved by an
    /// earlier build still open, with the new step off.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        rotation = try c.decode(SIMD4<Float>.self, forKey: .rotation)
        scalePercent = try c.decode(Double.self, forKey: .scalePercent)
        removeSupport = try c.decode(Bool.self, forKey: .removeSupport)
        removeFragments = try c.decode(Bool.self, forKey: .removeFragments)
        smoothing = try c.decode(MeshSmoothingLevel.self, forKey: .smoothing)
        fillHoles = try c.decodeIfPresent(Bool.self, forKey: .fillHoles) ?? false
        flatBase = try c.decode(Bool.self, forKey: .flatBase)
        trimFraction = try c.decode(Double.self, forKey: .trimFraction)
    }

    var quaternion: simd_quatf { simd_normalize(simd_quatf(vector: rotation)) }
    var isValid: Bool {
        version == 1 && (0..<4).allSatisfy { rotation[$0].isFinite }
            && simd_length(rotation) > 0.0001 && scalePercent.isFinite
            && (10...500).contains(scalePercent) && trimFraction.isFinite
            && (0...0.2).contains(trimFraction)
    }
    func save(to url: URL) throws {
        guard isValid else { throw CocoaError(.fileWriteInvalidFileName) }
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
    static func load(from url: URL) throws -> Preparation {
        guard FileManager.default.fileExists(atPath: url.path) else { return Preparation() }
        let value = try JSONDecoder().decode(Preparation.self, from: Data(contentsOf: url))
        guard value.isValid else { throw CocoaError(.fileReadCorruptFile) }
        return value
    }
    static func calibrationPercent(realMM: Double, scannedMM: Double) -> Double? {
        guard realMM.isFinite, scannedMM.isFinite, realMM > 0, scannedMM > 0 else { return nil }
        let percent = realMM / scannedMM * 100
        return (10...500).contains(percent) ? percent : nil
    }
}

struct PreparedMesh: Sendable {
    let oriented: MeshData
    let support: SupportSurfaceRemoval?
    let fragments: SmallComponentCleanup?
    let smoothed: MeshData?
    let filled: HoleFill?
    let cut: MeshData?
    let report: PrintReport
    var beforeCut: MeshData { filled?.mesh ?? smoothed ?? fragments?.mesh ?? support?.mesh ?? oriented }
    var mesh: MeshData { cut ?? beforeCut }
}

/// One pipeline at a time, with cached prefixes for unchanged preparation stages.
actor MeshPreparationWorker {
    private let original: MeshData
    private var previous: Preparation?
    private var cached: PreparedMesh?
    init(_ original: MeshData) { self.original = original }

    func prepare(_ recipe: Preparation) throws -> PreparedMesh {
        try Task.checkCancellation()
        guard recipe.isValid else { throw CocoaError(.fileReadCorruptFile) }
        let sameRotation = previous?.rotation == recipe.rotation
        let sameSupport = sameRotation && previous?.removeSupport == recipe.removeSupport
        let sameFragments = sameSupport && previous?.removeFragments == recipe.removeFragments
        let sameSmoothing = sameFragments && previous?.smoothing == recipe.smoothing
        let sameFill = sameSmoothing && previous?.fillHoles == recipe.fillHoles
        let sameCut = sameFill && previous?.flatBase == recipe.flatBase && previous?.trimFraction == recipe.trimFraction
        if sameCut, let cached { return cached }
        let oriented = sameRotation ? (cached?.oriented ?? original) : original.rotated(by: recipe.quaternion)
        try Task.checkCancellation()
        let support = sameSupport ? cached?.support : (recipe.removeSupport ? oriented.removingSupportSurface() : nil)
        try Task.checkCancellation()
        let supported = support?.mesh ?? oriented
        let fragments = sameFragments ? cached?.fragments : (recipe.removeFragments ? supported.removingSmallComponents() : nil)
        try Task.checkCancellation()
        let cleaned = fragments?.mesh ?? supported
        let smoothed = sameSmoothing ? cached?.smoothed : (recipe.smoothing == .off ? nil : cleaned.smoothed(level: recipe.smoothing))
        try Task.checkCancellation()
        let finish = smoothed ?? cleaned
        let filled = sameFill ? cached?.filled : (recipe.fillHoles ? finish.fillingHoles() : nil)
        try Task.checkCancellation()
        let finished = filled?.mesh ?? finish
        let cut = recipe.flatBase && recipe.trimFraction > 0 ? finished.flatBase(trimMM: finished.sizeMM.z * Float(recipe.trimFraction)) : nil
        try Task.checkCancellation()
        let report = (cut ?? finished).printReport()
        try Task.checkCancellation()
        let result = PreparedMesh(oriented: oriented, support: support, fragments: fragments, smoothed: smoothed, filled: filled, cut: cut, report: report)
        previous = recipe
        cached = result
        return result
    }
}
