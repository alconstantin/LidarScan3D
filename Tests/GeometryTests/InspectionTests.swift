import XCTest
import simd
@testable import Geometry

final class InspectionTests: XCTestCase {
    func testClosedCubeHasNoProblemHighlights() {
        let report = Solids.cube(side: 20).printReport()
        XCTAssertTrue(report.isWatertight)
        XCTAssertTrue(report.problemEdges.isEmpty)
        XCTAssertTrue(report.problemFaces.isEmpty)
    }

    func testEveryHighlightedHoleEdgeReferencesActualSurfaceVertices() {
        var cube = Solids.cube(side: 20)
        cube.indices.removeFirst(3)
        let report = cube.printReport()
        XCTAssertEqual(report.holeEdges, 3)
        XCTAssertEqual(report.problemEdges.count, 3)
        for edge in report.problemEdges {
            XCTAssertLessThan(Int(edge.x), cube.vertices.count)
            XCTAssertLessThan(Int(edge.y), cube.vertices.count)
            XCTAssertNotEqual(cube.vertices[Int(edge.x)], cube.vertices[Int(edge.y)])
        }
    }

    func testWeldedTextureSeamsDoNotCreateFalseHighlights() {
        let cube = Solids.cube(side: 20)
        let soup = MeshData(vertices: cube.indices.map { cube.vertices[Int($0)] },
                            indices: Array(0..<UInt32(cube.indices.count)), sizeMM: cube.sizeMM)
        XCTAssertTrue(soup.printReport().problemEdges.isEmpty)
    }

    func testFlippedFaceHighlightsItsEdges() {
        var cube = Solids.cube(side: 20)
        cube.indices.swapAt(0, 1)
        let report = cube.printReport()
        XCTAssertGreaterThan(report.flippedEdges, 0)
        XCTAssertEqual(report.problemEdges.count, 3)
    }

    func testIntersectionsHighlightBothInvolvedFaces() {
        let mesh = MeshData.seated(vertices: [SIMD3(0,0,0), SIMD3(4,0,0), SIMD3(0,4,0),
                                             SIMD3(1,1,0), SIMD3(5,1,0), SIMD3(1,5,0)], indices: [0,1,2,3,4,5])
        let report = mesh.printReport()
        XCTAssertEqual(report.problemFaces, [0, 1])
        XCTAssertGreaterThan(report.intersectingTriangles, 0)
    }

    func testInwardShellHighlightsItsFaces() {
        var cube = Solids.cube(side: 20)
        for face in 0..<cube.triangleCount { cube.indices.swapAt(face * 3, face * 3 + 1) }
        let report = cube.printReport()
        XCTAssertEqual(report.inwardShells, 1)
        XCTAssertEqual(report.problemFaces.count, cube.triangleCount)
    }

    func testWorkerRejectsInvalidRecipeWithoutChangingCachedResult() async throws {
        let worker = MeshPreparationWorker(Solids.cube(side: 20))
        _ = try await worker.prepare(Preparation())
        do {
            _ = try await worker.prepare(Preparation(rotation: .zero))
            XCTFail("Invalid recipes must not reach rotation or destroy the cached result")
        } catch {}
        let restored = try await worker.prepare(Preparation())
        XCTAssertEqual(restored.mesh.sizeMM, SIMD3(20, 20, 20))
    }
}
