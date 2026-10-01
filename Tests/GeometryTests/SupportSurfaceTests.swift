import XCTest
import simd
@testable import Geometry

final class SupportSurfaceTests: XCTestCase {
    func testRemovesBroadLowerPlaneButKeepsObject() throws {
        let cube = Solids.box(SIMD3(-5, -5, 0), SIMD3(5, 5, 20))
        var vertices = cube.vertices
        let tableBase = UInt32(vertices.count)
        vertices += [SIMD3(-50, -50, 0), SIMD3(50, -50, 0),
                     SIMD3(50, 50, 0), SIMD3(-50, 50, 0)]
        let table: [UInt32] = [tableBase, tableBase + 1, tableBase + 2,
                               tableBase, tableBase + 2, tableBase + 3]
        let mesh = MeshData.seated(vertices: vertices, indices: cube.indices + table)

        let result = try XCTUnwrap(mesh.removingSupportSurface())
        XCTAssertEqual(result.removedTriangles, 2)
        XCTAssertEqual(result.mesh.triangleCount, cube.indices.count / 3)
        XCTAssertEqual(result.mesh.sizeMM.x, 10, accuracy: 0.001)
        XCTAssertEqual(result.mesh.sizeMM.y, 10, accuracy: 0.001)
        XCTAssertEqual(result.mesh.sizeMM.z, 20, accuracy: 0.001)
    }

    func testDoesNotMistakeCleanFlatBaseForSupport() {
        XCTAssertNil(Solids.cube(side: 20).removingSupportSurface())
    }
}
