import XCTest
import simd
@testable import Geometry

/// The plane cut is what makes a scan printable, and a slicer only tells you it is
/// broken after you have waited for the export. These pin it down instead.
final class FlatBaseTests: XCTestCase {
    func testUncutSphereIsWatertight() {
        let report = SurfaceReport(Solids.sphere(radius: 30))
        XCTAssertTrue(report.isWatertight, "the test solid itself must be closed")
        // A 40x48 sphere inscribes the true one, so it comes in slightly under.
        XCTAssertEqual(report.volumeMM3, 4.0 / 3.0 * .pi * 27_000, accuracy: 1_000)
    }

    func testCutSphereStaysWatertight() {
        let cut = Solids.sphere(radius: 30).flatBase(trimMM: 8)
        let report = SurfaceReport(cut)
        XCTAssertTrue(report.isWatertight, "the cap must close the opening the cut made")
        XCTAssertEqual(cut.sizeMM.z, 52, accuracy: 0.001)
    }

    /// The case the welding tolerance exists for: a plane landing exactly on a ring of
    /// vertices produces zero-area slivers unless they are dropped.
    func testCutLandingExactlyOnVerticesStaysWatertight() {
        let hemisphere = Solids.sphere(radius: 30).flatBase(trimMM: 30)
        let report = SurfaceReport(hemisphere)
        XCTAssertTrue(report.isWatertight)
        XCTAssertEqual(report.degenerateTriangles, 0)
        XCTAssertEqual(report.volumeMM3, 2.0 / 3.0 * .pi * 27_000, accuracy: 1_000)
    }

    /// Each loop gets its own cap. A single fan spanning both legs would close the gap
    /// between them and add volume that is not there.
    func testDisjointLoopsAreCappedSeparately() {
        let cut = Solids.twoLegged().flatBase(trimMM: 5)
        let report = SurfaceReport(cut)
        XCTAssertTrue(report.isWatertight)
        XCTAssertEqual(report.volumeMM3, 2 * 3 * 8 * 15, accuracy: 0.01, "two legs, 15mm of each left")
    }

    /// A bowl or vase standing on a foot ring cuts into a loop inside a loop. The inner
    /// one is a hole: capping it too fills the ring and leaves the mesh non-manifold.
    func testRingFootKeepsItsHole() {
        let torus = Solids.torus(major: 30, minor: 10)
        XCTAssertTrue(SurfaceReport(torus).isWatertight, "the test solid itself must be closed")

        for trim in [Float(2), 5, 9] {
            let cut = torus.flatBase(trimMM: trim)
            XCTAssertTrue(SurfaceReport(cut).isWatertight, "trim \(trim)mm")

            // Every triangle on the bed must lie in the annulus, none across the hole.
            let z = 10 - trim
            let innerRadius = 30 - (100 - z * z).squareRoot()
            var nearest = Float.greatestFiniteMagnitude
            for t in 0..<cut.triangleCount {
                let p = (0..<3).map { cut.vertices[Int(cut.indices[t * 3 + $0])] }
                guard p.allSatisfy({ abs($0.z) < 1e-4 }) else { continue }
                let centroid = (p[0] + p[1] + p[2]) / 3
                nearest = min(nearest, simd_length(SIMD2(centroid.x, centroid.y)))
            }
            XCTAssertGreaterThan(nearest, innerRadius * 0.95, "trim \(trim)mm: the cap covers the hole")
        }
    }

    /// A footprint whose centre lies outside it. A fan from the centre would reach across
    /// the notch.
    func testNonConvexFootprintIsCappedExactly() {
        let block = Solids.uBlock(height: 20)
        XCTAssertEqual(SurfaceReport(block).volumeMM3, 700 * 20, accuracy: 0.01)

        let report = SurfaceReport(block.flatBase(trimMM: 5))
        XCTAssertTrue(report.isWatertight)
        XCTAssertEqual(report.volumeMM3, 700 * 15, accuracy: 0.01)
    }

    /// Object Capture meshes are not guaranteed closed. The cut cannot repair that, but
    /// it must not make it worse by introducing non-manifold geometry.
    func testCuttingAnOpenMeshAddsNoNonManifoldGeometry() {
        let holed = Solids.holedSphere(radius: 30)
        XCTAssertGreaterThan(SurfaceReport(holed).boundaryEdges, 0, "this solid is meant to be open")

        let report = SurfaceReport(holed.flatBase(trimMM: 8))
        XCTAssertEqual(report.overUsedEdges, 0)
        XCTAssertEqual(report.flippedEdges, 0)
        XCTAssertEqual(report.degenerateTriangles, 0)
    }

    func testTrimIsClampedToNinetyPercentOfHeight() {
        let cube = Solids.cube(side: 20)
        for trim in [Float(20), 100, 10_000] {
            XCTAssertEqual(cube.flatBase(trimMM: trim).sizeMM.z, 2, accuracy: 0.001,
                           "asking for \(trim)mm must still leave a tenth of the object")
        }
    }

    func testNonPositiveTrimIsANoOp() {
        let cube = Solids.cube(side: 20)
        for trim in [Float(0), -5] {
            XCTAssertEqual(cube.flatBase(trimMM: trim).triangleCount, cube.triangleCount)
        }
    }

    func testDegenerateInputsDoNotCrash() {
        let flat = MeshData(vertices: [SIMD3(0, 0, 0), SIMD3(10, 0, 0), SIMD3(0, 10, 0)],
                            indices: [0, 1, 2], sizeMM: SIMD3(10, 10, 0))
        XCTAssertEqual(flat.flatBase(trimMM: 5).triangleCount, 1, "no height to cut")
        XCTAssertEqual(MeshData(vertices: [], indices: [], sizeMM: .zero).flatBase(trimMM: 5).triangleCount, 0)
    }
}
