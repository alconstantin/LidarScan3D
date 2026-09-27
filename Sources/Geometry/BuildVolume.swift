import Foundation

/// The box a printer can print inside, in millimetres.
struct BuildVolume: Sendable, Equatable {
    var width: Float
    var depth: Float
    var height: Float

    func fits(_ sizeMM: SIMD3<Float>) -> Bool {
        largestScale(for: sizeMM) >= 1
    }

    /// The largest uniform scale at which a model of `sizeMM` fits. A slicer will turn
    /// a model a quarter about Z to fit a rectangular plate, so that counts as fitting.
    func largestScale(for sizeMM: SIMD3<Float>) -> Float {
        let straight = min(width / sizeMM.x, depth / sizeMM.y)
        let turned = min(depth / sizeMM.x, width / sizeMM.y)
        return min(max(straight, turned), height / sizeMM.z)
    }
}

/// Printers the app knows the build volume of. Bambu Lab's, since that is where most
/// people slicing a phone scan are sending it.
enum Printer: String, CaseIterable, Identifiable, Sendable {
    case bambuA1Mini
    case bambuA1
    case bambuP1X1
    case bambuH2D
    case other

    var id: String { rawValue }

    var name: String {
        switch self {
        case .bambuA1Mini: "Bambu Lab A1 mini"
        case .bambuA1: "Bambu Lab A1"
        case .bambuP1X1: "Bambu Lab P1 / P2 / X1"
        case .bambuH2D: "Bambu Lab H2D"
        case .other: "Other printer"
        }
    }

    var buildVolume: BuildVolume? {
        switch self {
        case .bambuA1Mini: BuildVolume(width: 180, depth: 180, height: 180)
        case .bambuA1, .bambuP1X1: BuildVolume(width: 256, depth: 256, height: 256)
        case .bambuH2D: BuildVolume(width: 350, depth: 320, height: 325)
        case .other: nil
        }
    }
}
