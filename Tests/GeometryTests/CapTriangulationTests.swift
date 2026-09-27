import XCTest
@testable import Geometry

final class CapTriangulationTests: XCTestCase {
    private typealias Point = CapTriangulation.Point

    private func area(_ triangles: [(Point, Point, Point)]) -> Double {
        triangles.reduce(0) { $0 + CapTriangulation.cross($1.0, $1.1, $1.2) / 2 }
    }

    private func square(_ lo: Double, _ hi: Double) -> [Point] {
        [Point(lo, lo), Point(hi, lo), Point(hi, hi), Point(lo, hi)]
    }

    func testSquareWithAHoleCoversOnlyTheRing() {
        let triangles = CapTriangulation.triangulate([square(0, 10), square(3, 7)])
        XCTAssertEqual(area(triangles), 100 - 16, accuracy: 1e-9)
        XCTAssertTrue(triangles.allSatisfy { CapTriangulation.cross($0.0, $0.1, $0.2) >= 0 }, "all wound up")
    }

    func testLoopDirectionDoesNotDecideWhatIsAHole() {
        let triangles = CapTriangulation.triangulate([Array(square(0, 10).reversed()), Array(square(3, 7).reversed())])
        XCTAssertEqual(area(triangles), 84, accuracy: 1e-9)
    }

    func testTwoHoles() {
        let triangles = CapTriangulation.triangulate([square(0, 10), square(1, 3), square(6, 8)])
        XCTAssertEqual(area(triangles), 100 - 4 - 4, accuracy: 1e-9)
    }

    func testIslandInsideAHoleIsSolidAgain() {
        let triangles = CapTriangulation.triangulate([square(0, 10), square(2, 8), square(4, 6)])
        XCTAssertEqual(area(triangles), 100 - 36 + 4, accuracy: 1e-9)
    }

    /// Random star-shaped outlines: non-convex, but simple, so ear clipping must find
    /// exactly n - 2 triangles summing to the outline's area.
    func testRandomStarPolygons() {
        var generator = SystemRandomNumberGenerator()
        for trial in 0..<200 {
            let n = Int.random(in: 5...60, using: &generator)
            var outline = (0..<n).map { k -> Point in
                let angle = 2 * Double.pi * Double(k) / Double(n)
                let radius = Double.random(in: 3...10, using: &generator)
                return Point(radius * cos(angle), radius * sin(angle))
            }
            if trial.isMultiple(of: 2) { outline.reverse() }

            let triangles = CapTriangulation.triangulate([outline])
            XCTAssertEqual(triangles.count, n - 2, "trial \(trial)")
            XCTAssertEqual(area(triangles), abs(CapTriangulation.signedArea(outline)), accuracy: 1e-6, "trial \(trial)")
        }
    }
}
