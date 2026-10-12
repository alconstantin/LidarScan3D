import XCTest
import simd
@testable import Geometry

final class HoleFillingTests: XCTestCase {
    /// A cube with `faces` (pairs of triangles, by box face index) left out.
    private func openBox(side: Float, removing faces: Set<Int>) -> MeshData {
        let h = side / 2
        let b = Solids.box(SIMD3(-h, -h, 0), SIMD3(h, h, side))
        var indices: [UInt32] = []
        for face in 0..<6 where !faces.contains(face) { indices += b.indices[(face * 6)..<(face * 6 + 6)] }
        return MeshData.seated(vertices: b.vertices, indices: indices)
    }

    func testClosedMeshHasNothingToFill() {
        XCTAssertNil(Solids.cube(side: 20).fillingHoles())
    }

    func testMissingCubeFaceIsClosedWithMatchingWinding() throws {
        let open = openBox(side: 20, removing: [1])
        XCTAssertFalse(SurfaceReport(open).isWatertight)
        let fill = try XCTUnwrap(open.fillingHoles())
        XCTAssertEqual(fill.filledHoles, 1)
        XCTAssertEqual(fill.addedTriangles, 2)
        let report = SurfaceReport(fill.mesh)
        XCTAssertTrue(report.isWatertight)
        XCTAssertEqual(report.volumeMM3, 8000, accuracy: 0.01)
    }

    /// Two separate holes are found and closed independently.
    func testOppositeHolesAreBothFilled() throws {
        let fill = try XCTUnwrap(openBox(side: 20, removing: [0, 1]).fillingHoles())
        XCTAssertEqual(fill.filledHoles, 2)
        XCTAssertTrue(SurfaceReport(fill.mesh).isWatertight)
        XCTAssertEqual(SurfaceReport(fill.mesh).volumeMM3, 8000, accuracy: 0.01)
    }

    /// The curved gap a real scan leaves: closed, outward-facing, close to the original volume.
    func testCurvedHoleInSphereIsClosed() throws {
        let holed = Solids.holedSphere(radius: 30)
        XCTAssertGreaterThan(SurfaceReport(holed).boundaryEdges, 0)
        let fill = try XCTUnwrap(holed.fillingHoles())
        XCTAssertEqual(fill.filledHoles, 1)
        let report = SurfaceReport(fill.mesh)
        XCTAssertTrue(report.isWatertight)
        let full = SurfaceReport(Solids.sphere(radius: 30)).volumeMM3
        XCTAssertEqual(report.volumeMM3, full, accuracy: full * 0.01)
        XCTAssertEqual(fill.mesh.printReport().intersectingTriangles, 0)
    }

    /// An L-shaped hole: a fan from its centre would overlap, ear clipping must not.
    func testConcaveHoleIsCoveredExactly() throws {
        // A flat 5 × 5 sheet of 10 mm cells with an L of five interior cells removed.
        var vertices: [SIMD3<Float>] = []
        for y in 0...5 { for x in 0...5 { vertices.append(SIMD3(Float(x) * 10, Float(y) * 10, 0)) } }
        func v(_ x: Int, _ y: Int) -> UInt32 { UInt32(y * 6 + x) }
        let open: Set<[Int]> = [[1, 1], [2, 1], [3, 1], [1, 2], [1, 3]]
        var indices: [UInt32] = []
        for y in 0..<5 {
            for x in 0..<5 where !open.contains([x, y]) {
                indices += [v(x, y), v(x + 1, y), v(x + 1, y + 1), v(x, y), v(x + 1, y + 1), v(x, y + 1)]
            }
        }
        let sheet = MeshData(vertices: vertices, indices: indices, sizeMM: SIMD3(50, 50, 0))
        // The sheet's 20-edge outer rim stays open; the 12-edge L is filled.
        let fill = try XCTUnwrap(sheet.fillingHoles(maxEdges: 15))
        XCTAssertEqual(fill.filledHoles, 1)
        XCTAssertEqual(fill.skippedHoles, 1)
        XCTAssertEqual(fill.addedTriangles, 10)
        XCTAssertEqual(fill.mesh.vertices.count, vertices.count, "no centre vertex: the patch was ear-clipped")
        XCTAssertEqual(fill.mesh.printReport().intersectingTriangles, 0)
        // The patch faces the same way as the sheet around it: up.
        for t in sheet.triangleCount..<fill.mesh.triangleCount {
            let a = fill.mesh.vertices[Int(fill.mesh.indices[3 * t])], b = fill.mesh.vertices[Int(fill.mesh.indices[3 * t + 1])], c = fill.mesh.vertices[Int(fill.mesh.indices[3 * t + 2])]
            XCTAssertGreaterThanOrEqual(simd_cross(b - a, c - a).z, 0)
        }
    }

    func testLongLoopsAreLeftOpen() throws {
        let fill = try XCTUnwrap(openBox(side: 20, removing: [1]).fillingHoles(maxEdges: 3))
        XCTAssertEqual(fill.filledHoles, 0)
        XCTAssertEqual(fill.skippedHoles, 1)
        XCTAssertFalse(SurfaceReport(fill.mesh).isWatertight)
    }

    /// Recipes saved before hole filling existed still open, with it off.
    func testOlderRecipesDecodeWithoutFillHoles() throws {
        let json = #"{"version":1,"rotation":[0,0,0,1],"scalePercent":120,"removeSupport":false,"removeFragments":true,"smoothing":"light","flatBase":true,"trimFraction":0.05}"#
        let recipe = try JSONDecoder().decode(Preparation.self, from: Data(json.utf8))
        XCTAssertFalse(recipe.fillHoles)
        XCTAssertEqual(recipe.scalePercent, 120)
        XCTAssertTrue(recipe.isValid)
        let again = try JSONDecoder().decode(Preparation.self, from: JSONEncoder().encode(Preparation(fillHoles: true)))
        XCTAssertTrue(again.fillHoles)
    }

    func testWorkerFillsBeforeCutting() async throws {
        let worker = MeshPreparationWorker(openBox(side: 20, removing: [1]))
        let prepared = try await worker.prepare(Preparation(fillHoles: true, flatBase: true, trimFraction: 0.1))
        XCTAssertEqual(prepared.filled?.filledHoles, 1)
        XCTAssertTrue(SurfaceReport(prepared.mesh).isWatertight)
        XCTAssertEqual(SurfaceReport(prepared.mesh).volumeMM3, 20 * 20 * 18, accuracy: 0.01)
    }
}
