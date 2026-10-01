import XCTest
import simd
@testable import Geometry

final class MeshSmoothingTests: XCTestCase {
    func testSmoothingReducesGentleNoiseAndKeepsOpenRimFixed() {
        var vertices: [SIMD3<Float>] = []
        for y in 0...2 {
            for x in 0...2 {
                vertices.append(SIMD3(Float(x * 10), Float(y * 10), x == 1 && y == 1 ? 2 : 0))
            }
        }
        let mesh = MeshData.seated(
            vertices: vertices,
            indices: [0, 1, 4, 0, 4, 3, 1, 2, 5, 1, 5, 4, 3, 4, 7, 3, 7, 6, 4, 5, 8, 4, 8, 7]
        )

        let smoothed = mesh.smoothed(level: .light)

        XCTAssertLessThan(smoothed.vertices[4].z, mesh.vertices[4].z)
        for index in [0, 1, 2, 3, 5, 6, 7, 8] {
            XCTAssertEqual(smoothed.vertices[index], mesh.vertices[index], "rim vertex \(index)")
        }
        XCTAssertEqual(smoothed.indices, mesh.indices)
    }

    func testSmoothingPreservesSharpCubeAndItsTopology() {
        let cube = Solids.cube(side: 20)
        let smoothed = cube.smoothed(level: .strong)

        XCTAssertEqual(smoothed.vertices, cube.vertices)
        XCTAssertEqual(smoothed.indices, cube.indices)
        XCTAssertTrue(smoothed.printReport().isWatertight)
    }
}
