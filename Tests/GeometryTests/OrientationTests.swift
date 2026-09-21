import XCTest
import simd
@testable import Geometry

final class OrientationTests: XCTestCase {
    /// Everything that moves geometry ends in seated(), so exports always rest on the bed.
    func testSeatedRestsOnZeroAndCentresOnXY() {
        let mesh = Solids.sphere(radius: 30).rotated(by: MeshData.quarterTurn(about: SIMD3(1, 0, 0), clockwise: true))
        var lo = mesh.vertices[0], hi = mesh.vertices[0]
        for v in mesh.vertices {
            lo = simd_min(lo, v)
            hi = simd_max(hi, v)
        }
        XCTAssertEqual(lo.z, 0, accuracy: 0.001)
        XCTAssertEqual(lo.x + hi.x, 0, accuracy: 0.001)
        XCTAssertEqual(lo.y + hi.y, 0, accuracy: 0.001)
    }

    func testFourQuarterTurnsReturnToTheStart() {
        let original = Solids.twoLegged()
        var rotation = MeshData.noRotation
        for _ in 0..<4 { rotation = MeshData.quarterTurn(about: SIMD3(1, 0, 0), clockwise: true) * rotation }
        XCTAssertEqual(simd_length(original.rotated(by: rotation).sizeMM - original.sizeMM), 0, accuracy: 0.001)
    }

    func testQuarterTurnSwapsTheAxesItTurnsAbout() {
        let turned = Solids.twoLegged().rotated(by: MeshData.quarterTurn(about: SIMD3(1, 0, 0), clockwise: true))
        XCTAssertEqual(turned.sizeMM.y, 20, accuracy: 0.001, "the 20mm height is now the depth")
        XCTAssertEqual(turned.sizeMM.z, 8, accuracy: 0.001)
    }

    func testIdentityRotationIsANoOp() {
        let original = Solids.cube(side: 20)
        XCTAssertEqual(original.rotated(by: MeshData.noRotation).vertices, original.vertices)
    }

    /// Repeated turns must re-apply to the untouched original, not pile up on the mesh.
    func testTurningThenCuttingPreservesVolume() {
        let tipped = Solids.twoLegged().rotated(by: MeshData.quarterTurn(about: SIMD3(1, 0, 0), clockwise: true))
        let report = SurfaceReport(tipped.flatBase(trimMM: 2))
        XCTAssertTrue(report.isWatertight)
        XCTAssertEqual(report.volumeMM3, 2 * 3 * 6 * 20, accuracy: 0.01)
    }
}
