import XCTest
import simd
@testable import Geometry

final class WallThicknessTests: XCTestCase {
    func testSolidCubeIsAsThickAsItIsWide() throws {
        let walls = Solids.cube(side: 40).wallThickness()
        XCTAssertEqual(walls.faces.count, 12)
        XCTAssertEqual(try XCTUnwrap(walls.thinnestMM(scale: 1)), 40, accuracy: 0.01)
        XCTAssertEqual(walls.thinAreaFraction(below: 0.8, scale: 1), 0)
        XCTAssertFalse(walls.isSampled)
    }

    /// A 0.5 mm sheet prints as at most one line from a 0.4 mm nozzle.
    func testThinSheetIsFlaggedUntilScaledUp() throws {
        let b = Solids.box(SIMD3(-30, -30, 0), SIMD3(30, 30, 0.5))
        let sheet = MeshData.seated(vertices: b.vertices, indices: b.indices)
        let walls = sheet.wallThickness()
        XCTAssertEqual(try XCTUnwrap(walls.thinnestMM(scale: 1)), 0.5, accuracy: 0.01)
        XCTAssertGreaterThan(walls.thinAreaFraction(below: 0.8, scale: 1), 0.95)
        XCTAssertFalse(walls.thinFaces(below: 0.8, scale: 1).isEmpty)
        XCTAssertTrue(walls.thinFaces(below: 0.8, scale: 2).isEmpty, "1 mm at 200 % is thick enough")
    }

    /// A hollow box: the wall is the gap to the cavity, not the box's width.
    func testCavityWallIsMeasuredToTheCavity() throws {
        let outer = Solids.box(SIMD3(-10, -10, 0), SIMD3(10, 10, 20))
        let inner = Solids.box(SIMD3(-9, -9, 1), SIMD3(9, 9, 19))
        var indices = outer.indices
        let base = UInt32(outer.vertices.count)
        for t in 0..<(inner.indices.count / 3) {
            // Reversed winding: the cavity's surface faces into the cavity.
            indices += [inner.indices[3 * t], inner.indices[3 * t + 2], inner.indices[3 * t + 1]].map { $0 + base }
        }
        let hollow = MeshData.seated(vertices: outer.vertices + inner.vertices, indices: indices)
        let walls = hollow.wallThickness()
        XCTAssertEqual(walls.faces.count, 24, "every face, inside and out, finds the other side of the wall")
        for value in walls.thicknessMM { XCTAssertEqual(value, 1, accuracy: 0.01) }
        XCTAssertEqual(walls.thinAreaFraction(below: 1.2, scale: 1), 1, accuracy: 0.001)
        XCTAssertEqual(walls.thinAreaFraction(below: 0.8, scale: 1), 0)
    }

    func testSphereIsMeasuredAcrossItsDiameter() throws {
        let walls = Solids.sphere(radius: 30).wallThickness()
        XCTAssertGreaterThan(try XCTUnwrap(walls.thinnestMM(scale: 1)), 55)
    }

    /// Rays escaping through a hole measure nothing rather than inventing a wall.
    func testOpenSurfaceDoesNotInventWalls() {
        let b = Solids.box(SIMD3(-10, -10, 0), SIMD3(10, 10, 0))
        let quad = MeshData(vertices: Array(b.vertices[0..<4]), indices: [0, 2, 1, 0, 3, 2], sizeMM: SIMD3(20, 20, 0))
        let walls = quad.wallThickness()
        XCTAssertEqual(walls.sampledTriangles, 2)
        XCTAssertFalse(walls.hasMeasurements)
        XCTAssertNil(walls.thinnestMM(scale: 1))
    }

    func testLargeMeshesAreSampled() {
        let sphere = Solids.sphere(radius: 30)
        let walls = sphere.wallThickness(maxSamples: 100)
        XCTAssertTrue(walls.isSampled)
        XCTAssertLessThanOrEqual(walls.sampledTriangles, 100)
        XCTAssertEqual(walls.totalTriangles, sphere.triangleCount)
    }

    func testReportCarriesWallThickness() {
        XCTAssertEqual(Solids.cube(side: 20).printReport().walls.thinnestMM(scale: 1) ?? 0, 20, accuracy: 0.01)
    }
}
