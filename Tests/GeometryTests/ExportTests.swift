import XCTest
import simd
@testable import Geometry

final class ExportTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GeometryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testBinarySTLLayout() throws {
        let cube = Solids.cube(side: 20)
        let url = directory.appendingPathComponent("cube.stl")
        try cube.writeBinarySTL(to: url, scale: 1)
        let data = try Data(contentsOf: url)

        XCTAssertEqual(data.count, 84 + cube.triangleCount * 50, "84-byte header plus 50 bytes a triangle")
        XCTAssertEqual(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 80, as: UInt32.self) },
                       UInt32(cube.triangleCount))
        // A binary STL whose header starts with "solid" is read as ASCII by some tools.
        XCTAssertFalse(String(decoding: data[0..<5], as: UTF8.self).lowercased().hasPrefix("solid"))
    }

    func testSTLScaleMultipliesEveryCoordinate() throws {
        let url = directory.appendingPathComponent("cube2x.stl")
        try Solids.cube(side: 20).writeBinarySTL(to: url, scale: 2)
        let data = try Data(contentsOf: url)

        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        for t in 0..<((data.count - 84) / 50) {
            for corner in 0..<3 {
                let offset = 84 + t * 50 + 12 + corner * 12
                let p = SIMD3<Float>((0..<3).map { axis in
                    data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset + axis * 4, as: Float.self) }
                })
                lo = simd_min(lo, p)
                hi = simd_max(hi, p)
            }
        }
        XCTAssertEqual(simd_length(hi - lo - SIMD3<Float>(40, 40, 40)), 0, accuracy: 0.001)
        XCTAssertEqual(lo.z, 0, accuracy: 0.001, "scaling about the origin keeps it on the bed")
    }

    func testOBJUsesOneBasedIndices() throws {
        let cube = Solids.cube(side: 20)
        let url = directory.appendingPathComponent("cube.obj")
        try cube.writeOBJ(to: url, scale: 1)
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")

        XCTAssertEqual(lines.filter { $0.hasPrefix("v ") }.count, cube.vertices.count)
        let faces = lines.filter { $0.hasPrefix("f ") }
        XCTAssertEqual(faces.count, cube.triangleCount)
        let referenced = faces.flatMap { $0.dropFirst(2).split(separator: " ").compactMap { Int($0) } }
        XCTAssertEqual(referenced.min(), 1, "OBJ indices start at 1, not 0")
        XCTAssertEqual(referenced.max(), cube.vertices.count)
    }

    func testWritersCreateTheExportsDirectory() throws {
        let nested = directory.appendingPathComponent("Exports/deeper/model.stl")
        try Solids.cube(side: 10).writeBinarySTL(to: nested, scale: 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }
}
