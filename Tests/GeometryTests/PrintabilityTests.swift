import XCTest
import simd
@testable import Geometry

final class PrintabilityTests: XCTestCase {
    /// The app's report and the independent one the other tests use must agree exactly.
    private func assertMatchesReference(_ mesh: MeshData, file: StaticString = #filePath, line: UInt = #line) {
        let app = mesh.printReport(), reference = SurfaceReport(mesh)
        XCTAssertEqual(app.holeEdges, reference.boundaryEdges, "holes", file: file, line: line)
        XCTAssertEqual(app.nonManifoldEdges, reference.overUsedEdges, "non-manifold", file: file, line: line)
        XCTAssertEqual(app.flippedEdges, reference.flippedEdges, "flipped", file: file, line: line)
        XCTAssertEqual(app.degenerateTriangles, reference.degenerateTriangles, "degenerate", file: file, line: line)
        XCTAssertEqual(app.volumeMM3, reference.volumeMM3, accuracy: 1e-6 * max(1, abs(reference.volumeMM3)), file: file, line: line)
        XCTAssertEqual(app.isWatertight, reference.isWatertight, file: file, line: line)
    }

    func testReportMatchesTheReferenceChecks() {
        assertMatchesReference(Solids.sphere(radius: 30))
        assertMatchesReference(Solids.holedSphere(radius: 30))
        assertMatchesReference(Solids.twoLegged().flatBase(trimMM: 5))
        assertMatchesReference(Solids.torus(major: 30, minor: 10).flatBase(trimMM: 5))
        assertMatchesReference(Solids.uBlock(height: 20))
    }

    func testReportFindsHolesAndFlippedFaces() {
        XCTAssertGreaterThan(Solids.holedSphere(radius: 30).printReport().holeEdges, 0)

        var cube = Solids.cube(side: 20)
        cube.indices.swapAt(0, 1) // turn one triangle inside out
        let report = cube.printReport()
        XCTAssertGreaterThan(report.flippedEdges, 0)
        XCTAssertFalse(report.isWatertight)
    }

    /// Object Capture splits vertices along texture seams. A cube given as a triangle
    /// soup, every corner its own vertex, is the extreme case.
    func testWeldingFusesSplitVertices() {
        let cube = Solids.cube(side: 20)
        let soup = cube.indices.map { cube.vertices[Int($0)] }
        let welded = MeshData.welded(vertices: soup, indices: (0..<UInt32(soup.count)).map { $0 })

        XCTAssertEqual(welded.vertices.count, 8)
        XCTAssertEqual(welded.triangleCount, 12)
        XCTAssertTrue(welded.printReport().isWatertight)
        XCTAssertEqual(welded.sizeMM, cube.sizeMM)
    }

    func testWeldingDropsTrianglesThatCollapse() {
        let p = SIMD3<Float>(0, 0, 0)
        let welded = MeshData.welded(vertices: [p, SIMD3(10, 0, 0), SIMD3(0, 10, 0), p + SIMD3(0.0001, 0, 0)],
                                     indices: [0, 1, 2, 0, 3, 1])
        XCTAssertEqual(welded.triangleCount, 1, "corners 0 and 3 are the same point at micron precision")
    }

    // MARK: Build volume

    func testFitsAndLargestScale() {
        let plate = BuildVolume(width: 300, depth: 200, height: 100)
        XCTAssertTrue(plate.fits(SIMD3(300, 200, 100)), "exactly the build volume fits")
        XCTAssertFalse(plate.fits(SIMD3(301, 10, 10)))
        XCTAssertFalse(plate.fits(SIMD3(10, 10, 101)))

        XCTAssertTrue(plate.fits(SIMD3(150, 250, 50)), "fits once turned a quarter on the plate")
        XCTAssertEqual(plate.largestScale(for: SIMD3(600, 100, 10)), 0.5, accuracy: 1e-6)
        XCTAssertEqual(plate.largestScale(for: SIMD3(10, 10, 400)), 0.25, accuracy: 1e-6, "height limits too")
    }

    func testScaleToFitActuallyFits() {
        for printer in Printer.allCases {
            guard let volume = printer.buildVolume else { continue }
            let size = SIMD3<Float>(412, 97, 305)
            let percent = (volume.largestScale(for: size) * 100).rounded(.down)
            XCTAssertTrue(volume.fits(size * percent / 100), printer.name)
            XCTAssertFalse(volume.fits(size * (percent + 1) / 100), "\(printer.name): the fit is the largest")
        }
    }

    // MARK: The bundled sample

    func testSampleLoadsAtRealSizeAndIsWatertight() throws {
        let sample = try Solids.sampleVase()
        XCTAssertEqual(sample.sizeMM.x, 77, accuracy: 0.05)
        XCTAssertEqual(sample.sizeMM.y, 77, accuracy: 0.05)
        XCTAssertEqual(sample.sizeMM.z, 90.8, accuracy: 0.05, "metres, Y up, came in as millimetres, Z up")
        XCTAssertTrue(sample.printReport().isWatertight)
    }

    /// The app's default trim cuts through the foot ring. Its cap must leave the
    /// recessed base open, as it is on the real object.
    func testSampleFlatBaseCutsThroughTheFootRing() throws {
        let sample = try Solids.sampleVase()
        let cut = sample.flatBase(trimMM: sample.sizeMM.z * 0.02)
        XCTAssertTrue(cut.printReport().isWatertight, "\(cut.printReport())")

        var capOverRecess = 0
        for t in 0..<cut.triangleCount {
            let p = (0..<3).map { cut.vertices[Int(cut.indices[t * 3 + $0])] }
            guard p.allSatisfy({ abs($0.z) < 1e-4 }) else { continue }
            let centroid = (p[0] + p[1] + p[2]) / 3
            if simd_length(SIMD2(centroid.x, centroid.y)) < 20 { capOverRecess += 1 }
        }
        XCTAssertEqual(capOverRecess, 0)
    }
}
