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

    /// The device test: a 40 mm cube scanned at 34° read as 57.9 × 56.8 mm.
    func testSquaringUpMeasuresATurnedCubeByItsFaces() {
        let turned = Solids.cube(side: 40).rotated(by: simd_quatf(angle: 34 * .pi / 180, axis: SIMD3(0, 0, 1)))
        XCTAssertGreaterThan(turned.sizeMM.x, 55)
        let squared = turned.squaredUp()
        XCTAssertEqual(squared.sizeMM.x, 40, accuracy: 0.01)
        XCTAssertEqual(squared.sizeMM.y, 40, accuracy: 0.01)
        XCTAssertEqual(squared.sizeMM.z, 40, accuracy: 0.01)
    }

    /// The smallest turn back is taken, so a long box keeps its long side on X.
    func testSquaringUpTakesTheSmallestTurn() {
        let b = Solids.box(SIMD3(-30, -10, 0), SIMD3(30, 10, 15))
        let box = MeshData.seated(vertices: b.vertices, indices: b.indices)
        let squared = box.rotated(by: simd_quatf(angle: -25 * .pi / 180, axis: SIMD3(0, 0, 1))).squaredUp()
        XCTAssertEqual(squared.sizeMM.x, 60, accuracy: 0.01)
        XCTAssertEqual(squared.sizeMM.y, 20, accuracy: 0.01)
    }

    /// A round footprint has no heading to square to; noise must not spin it.
    func testSquaringUpLeavesRoundAndAlignedModelsAlone() {
        let sphere = Solids.sphere(radius: 30)
        XCTAssertEqual(sphere.squaredUp().vertices, sphere.vertices)
        let legs = Solids.twoLegged()
        XCTAssertEqual(legs.squaredUp().vertices, legs.vertices)
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
