import XCTest
import simd
@testable import Geometry

final class SmallComponentTests: XCTestCase {
    func testDropsTinyDisconnectedFragmentButKeepsMainObject() throws {
        let main = Solids.box(SIMD3(-10, -10, 0), SIMD3(10, 10, 20))
        let speck = Solids.box(SIMD3(30, 30, 0), SIMD3(31, 31, 1))
        let offset = UInt32(main.vertices.count)
        let mesh = MeshData.seated(
            vertices: main.vertices + speck.vertices,
            indices: main.indices + speck.indices.map { $0 + offset }
        )

        let result = try XCTUnwrap(mesh.removingSmallComponents())
        XCTAssertEqual(result.removedComponents, 1)
        XCTAssertEqual(result.removedTriangles, speck.indices.count / 3)
        XCTAssertEqual(result.mesh.triangleCount, main.indices.count / 3)
        XCTAssertEqual(result.mesh.sizeMM.x, 20, accuracy: 0.001)
        XCTAssertEqual(result.mesh.sizeMM.y, 20, accuracy: 0.001)
        XCTAssertEqual(result.mesh.sizeMM.z, 20, accuracy: 0.001)
    }

    func testKeepsIntentionalSeparatePartsThatAreNotTiny() {
        XCTAssertNil(Solids.twoLegged().removingSmallComponents())
    }
}
