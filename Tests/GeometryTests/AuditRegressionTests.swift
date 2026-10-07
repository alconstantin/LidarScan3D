import XCTest
import simd
@testable import Geometry

final class AuditRegressionTests: XCTestCase {
    func combine(_ main: MeshData, side: Float, at origin: SIMD3<Float>) -> MeshData {
        let part = Solids.box(origin, origin + SIMD3(repeating: side))
        return MeshData.seated(vertices: main.vertices + part.vertices,
            indices: main.indices + part.indices.map { $0 + UInt32(main.vertices.count) })
    }
    func testCleanupRequiresBothAbsoluteAndRelativeLimits() {
        XCTAssertNil(combine(Solids.cube(side: 100), side: 4, at: SIMD3(100, 0, 0)).removingSmallComponents())
        XCTAssertNil(combine(Solids.cube(side: 20), side: 2, at: SIMD3(40, 0, 0)).removingSmallComponents())
        XCTAssertNotNil(combine(Solids.cube(side: 20), side: 1, at: SIMD3(40, 0, 0)).removingSmallComponents())
    }
    func testUnusedVerticesCannotChangeDimensionsOrBedPosition() {
        let cube = Solids.cube(side: 20)
        let result = MeshData.welded(vertices: cube.vertices + [SIMD3(500, 500, -500)], indices: cube.indices)
        XCTAssertEqual(result.sizeMM, cube.sizeMM)
        XCTAssertEqual(result.vertices, cube.vertices)
        let empty = MeshData.welded(vertices: [SIMD3(500, 500, -500)], indices: [0, 0, 0])
        XCTAssertTrue(empty.vertices.isEmpty)
        XCTAssertEqual(empty.sizeMM, .zero)
    }
    func testIntersectingClosedSolidsFailSurfaceChecks() {
        let mesh = combine(Solids.cube(side: 20), side: 20, at: SIMD3(0, 0, 0))
        let report = mesh.printReport()
        XCTAssertGreaterThan(report.intersectingTriangles, 0)
        XCTAssertFalse(report.isWatertight)
    }
    func testSeparateInsideOutShellCannotHideBehindLargerVolume() {
        var mesh = combine(Solids.cube(side: 100), side: 4, at: SIMD3(150, 0, 0))
        for t in 12..<mesh.triangleCount { mesh.indices.swapAt(t * 3, t * 3 + 1) }
        let report = mesh.printReport()
        XCTAssertGreaterThan(report.volumeMM3, 0)
        XCTAssertEqual(report.inwardShells, 1)
        XCTAssertFalse(report.isWatertight)
    }
    func testDisjointOutwardShellsAndCoplanarNonOverlappingTrianglesPass() {
        XCTAssertTrue(combine(Solids.cube(side: 20), side: 4, at: SIMD3(150, 0, 0)).printReport().isWatertight)
        let flat = MeshData.seated(vertices: [SIMD3(0,0,0), SIMD3(1,0,0), SIMD3(0,1,0),
                                             SIMD3(2,0,0), SIMD3(3,0,0), SIMD3(2,1,0)], indices: [0,1,2,3,4,5])
        XCTAssertEqual(flat.printReport().intersectingTriangles, 0)
    }
    func testCoplanarOverlappingTrianglesAreDetected() {
        let mesh = MeshData.seated(vertices: [SIMD3(0,0,0), SIMD3(4,0,0), SIMD3(0,4,0),
                                             SIMD3(1,1,0), SIMD3(5,1,0), SIMD3(1,5,0)], indices: [0,1,2,3,4,5])
        XCTAssertGreaterThan(mesh.printReport().intersectingTriangles, 0)
    }
    func testPreparationRoundTripsWithoutChangingOriginal() async throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = Solids.cube(side: 20)
        let recipe = Preparation(rotation: MeshData.quarterTurn(about: SIMD3(1,0,0), clockwise: true).vector,
                                 scalePercent: 137.5, smoothing: .light, flatBase: true, trimFraction: 0.1)
        let url = folder.appendingPathComponent("preparation.json")
        try recipe.save(to: url)
        let restored = try Preparation.load(from: url)
        XCTAssertEqual(restored, recipe)
        let worker = MeshPreparationWorker(original)
        let prepared = try await worker.prepare(restored)
        XCTAssertEqual(prepared.mesh.sizeMM.z, 18, accuracy: 0.001)
        XCTAssertEqual(original.sizeMM.z, 20)
        let reset = try await worker.prepare(Preparation())
        XCTAssertEqual(reset.mesh.vertices, original.vertices)
        XCTAssertEqual(reset.mesh.indices, original.indices)
    }
    func testInvalidPreparationAndCalibrationAreRejected() throws {
        XCTAssertNil(Preparation.calibrationPercent(realMM: .infinity, scannedMM: 20))
        XCTAssertNil(Preparation.calibrationPercent(realMM: 200, scannedMM: 20))
        XCTAssertNil(Preparation.calibrationPercent(realMM: 20, scannedMM: 0))
        XCTAssertEqual(Preparation.calibrationPercent(realMM: 40, scannedMM: 20), 200)
        XCTAssertFalse(Preparation(version: 9).isValid)
        XCTAssertFalse(Preparation(rotation: .zero).isValid)
    }
    func testCancellationBeforeSessionInitializationIsRemembered() {
        let gate = CancellationGate()
        gate.cancel()
        var called = 0
        gate.attach { called += 1 }
        XCTAssertTrue(gate.isCancelled)
        XCTAssertEqual(called, 1)
    }
    func testCancellationAfterAttachmentIsReentrantAndOnlyDeliveredOnce() {
        let gate = CancellationGate()
        var called = 0
        gate.attach { called += 1; XCTAssertTrue(gate.isCancelled); gate.cancel() }
        gate.cancel()
        gate.cancel()
        XCTAssertEqual(called, 1)
    }
    func testCancelledPreparationDoesNotPublishOrPoisonWorkerCache() async throws {
        let worker = MeshPreparationWorker(Solids.cube(side: 20))
        let task = Task {
            try await Task.sleep(for: .seconds(1))
            return try await worker.prepare(Preparation(flatBase: true, trimFraction: 0.1))
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled job should throw") }
        catch is CancellationError {} 
        let result = try await worker.prepare(Preparation())
        XCTAssertEqual(result.mesh.sizeMM.z, 20)
    }
    func testZeroPhotoStallAndFlipPassCounting() {
        let date = Date(timeIntervalSince1970: 1000)
        var state = CaptureProgress()
        state.start(at: date)
        state.update(shots: 0, at: date.addingTimeInterval(16), paused: false)
        XCTAssertTrue(state.isStalled(at: date.addingTimeInterval(16)))
        state.newPass(at: date.addingTimeInterval(20))
        state.start(at: date.addingTimeInterval(21))
        XCTAssertEqual(state.passes, 2)
        state.update(shots: 0, at: date.addingTimeInterval(40), paused: true)
        XCTAssertFalse(state.isStalled(at: date.addingTimeInterval(40)))
        state.update(shots: 1, at: date.addingTimeInterval(50), paused: false)
        XCTAssertFalse(state.isStalled(at: date.addingTimeInterval(50)))
    }
    func testRenamingAndPhotoCleanupPreserveModelAndPreparation() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let scan = ScanFolder(url: folder)
        try FileManager.default.createDirectory(at: scan.imagesURL, withIntermediateDirectories: true)
        defer { try? scan.delete() }
        try Data([1, 2, 3]).write(to: scan.imagesURL.appendingPathComponent("photo.heic"))
        XCTAssertThrowsError(try scan.deleteSourcePhotos(), "Interrupted scans must keep their reconstruction input")
        try Data([4]).write(to: scan.modelURL)
        try Preparation(scalePercent: 125).save(to: scan.preparationURL)
        try scan.rename("Bracket / left")
        XCTAssertEqual(scan.name, "Bracket / left")
        XCTAssertEqual(scan.exportName, "Bracket - left")
        XCTAssertEqual(scan.id, folder, "A display-name edit must not break navigation or saved URLs")
        XCTAssertThrowsError(try scan.rename(" "))
        XCTAssertGreaterThan(scan.storageBytes, 3)
        try scan.deleteSourcePhotos()
        XCTAssertEqual(scan.imageCount, 0)
        XCTAssertTrue(scan.hasModel)
        XCTAssertEqual(try Preparation.load(from: scan.preparationURL).scalePercent, 125)
    }

    func testInterruptedScanKeepsPhotosAndPreparationOnDisk() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let scan = ScanFolder(url: folder)
        try FileManager.default.createDirectory(at: scan.imagesURL, withIntermediateDirectories: true)
        defer { try? scan.delete() }
        for i in 0..<CaptureProgress.minimumPhotos { try Data([1]).write(to: scan.imagesURL.appendingPathComponent("\(i).heic")) }
        XCTAssertTrue(scan.canRetry)
        XCTAssertFalse(scan.hasModel)
        try Preparation(scalePercent: 150).save(to: scan.preparationURL)
        XCTAssertEqual(try Preparation.load(from: scan.preparationURL).scalePercent, 150)
    }
}
