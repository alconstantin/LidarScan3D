import Compression
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

    // MARK: 3MF

    func test3MFPackageReadsBack() throws {
        let cube = Solids.cube(side: 20)
        let url = directory.appendingPathComponent("cube.3mf")
        try cube.write3MF(to: url, scale: 2, title: "Cube & <co>", plateCentreMM: SIMD2(128, 128))

        let entries = try unzip(Data(contentsOf: url))
        XCTAssertEqual(Set(entries.keys), ["[Content_Types].xml", "_rels/.rels", "3D/3dmodel.model"])

        let model = try XMLDocument(data: XCTUnwrap(entries["3D/3dmodel.model"]), options: [])
        XCTAssertEqual(model.rootElement()?.attribute(forName: "unit")?.stringValue, "millimeter")
        let vertices = try model.nodes(forXPath: "//*[local-name()='vertex']").compactMap { $0 as? XMLElement }
        XCTAssertEqual(vertices.count, cube.vertices.count)
        XCTAssertEqual(try model.nodes(forXPath: "//*[local-name()='triangle']").count, cube.triangleCount)

        let heights = vertices.compactMap { $0.attribute(forName: "z")?.stringValue.flatMap(Float.init) }
        XCTAssertEqual(heights.min() ?? -1, 0, accuracy: 1e-4, "still on the bed")
        XCTAssertEqual(heights.max() ?? -1, 40, accuracy: 1e-4, "scaled 2x")

        let title = try model.nodes(forXPath: "//*[local-name()='metadata'][@name='Title']").first?.stringValue
        XCTAssertEqual(title, "Cube & <co>", "escaped in the XML, intact once read")
        let item = try model.nodes(forXPath: "//*[local-name()='item']").first as? XMLElement
        XCTAssertEqual(item?.attribute(forName: "transform")?.stringValue, "1 0 0 0 1 0 0 0 1 128.0 128.0 0",
                       "placed at the plate centre")
    }

    func testZipStoresWhatDeflateCannotShrink() throws {
        let tiny = Data("ab".utf8)
        XCTAssertNil(ZipWriter.deflate(tiny))
        let entries = try unzip(ZipWriter.archive([ZipWriter.Entry(path: "a.txt", data: tiny)]))
        XCTAssertEqual(entries["a.txt"], tiny)
    }

    /// Writes the sample, cut the way the app cuts it by default, as STL and 3MF.
    /// With EXPORT_SAMPLES_DIR set, CI then audits the files with tools/check_stl.py,
    /// which reads them with Python's own zipfile and XML parser rather than ours.
    func testWritesAuditableExports() throws {
        let sample = try Solids.sampleVase()
        let cut = sample.flatBase(trimMM: sample.sizeMM.z * 0.02)
        let target = ProcessInfo.processInfo.environment["EXPORT_SAMPLES_DIR"].map { URL(fileURLWithPath: $0) } ?? directory
        try cut.writeBinarySTL(to: target.appendingPathComponent("sample-vase-flat.stl"), scale: 1)
        try cut.write3MF(to: target.appendingPathComponent("sample-vase-flat.3mf"), scale: 1,
                         title: "Sample vase", plateCentreMM: SIMD2(128, 128))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("sample-vase-flat.3mf").path))
    }

    /// Reads a ZIP by its central directory, as unzip tools do.
    private func unzip(_ zip: Data) throws -> [String: Data] {
        func u16(_ offset: Int) -> Int {
            Int(UInt16(littleEndian: zip.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }))
        }
        func u32(_ offset: Int) -> Int {
            Int(UInt32(littleEndian: zip.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }))
        }

        let end = zip.count - 22
        XCTAssertEqual(u32(end), 0x0605_4B50, "end of central directory")
        var entries: [String: Data] = [:]
        var p = u32(end + 16)
        for _ in 0..<u16(end + 10) {
            XCTAssertEqual(u32(p), 0x0201_4B50, "central directory header")
            let method = u16(p + 10), crc = u32(p + 16), packed = u32(p + 20), size = u32(p + 24)
            let nameLength = u16(p + 28), extraLength = u16(p + 30), commentLength = u16(p + 32)
            let local = u32(p + 42)
            let name = String(decoding: zip[(p + 46)..<(p + 46 + nameLength)], as: UTF8.self)

            XCTAssertEqual(u32(local), 0x0403_4B50, "local header for \(name)")
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            let body = Data(zip[start..<(start + packed)])
            let data = method == 8 ? inflate(body, size: size) : body
            XCTAssertEqual(data.count, size, name)
            XCTAssertEqual(Int(ZipWriter.crc32(data)), crc, name)
            entries[name] = data
            p += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    private func inflate(_ data: Data, size: Int) -> Data {
        var out = Data(count: size)
        let written = out.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_decode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, size,
                                          source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        out.count = written
        return out
    }
}
