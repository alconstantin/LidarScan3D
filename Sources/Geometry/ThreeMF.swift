import Compression
import Foundation
import simd

/// 3MF: a ZIP package holding the mesh as XML, with its units stated rather than
/// assumed. It is Bambu Studio's native format, and PrusaSlicer, Cura and OrcaSlicer
/// all open it.
extension MeshData {
    /// `plateCentreMM` places the model on the build plate, whose origin is its front
    /// left corner: slicers keep a 3MF's placement, where an STL is centred for you.
    func write3MF(to url: URL, scale: Float, title: String, plateCentreMM: SIMD2<Float> = .zero) throws {
        var model = """
            <?xml version="1.0" encoding="UTF-8"?>
            <model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
             <metadata name="Title">\(Self.xmlEscaped(title))</metadata>
             <metadata name="Application">LiDAR Scan 3D</metadata>
             <resources>
              <object id="1" type="model">
               <mesh>
                <vertices>

            """
        model.reserveCapacity(model.utf8.count + vertices.count * 64 + triangleCount * 48)
        for v in vertices {
            let s = v * scale
            model += "     <vertex x=\"\(s.x)\" y=\"\(s.y)\" z=\"\(s.z)\"/>\n"
        }
        model += "    </vertices>\n    <triangles>\n"
        for t in 0..<triangleCount {
            let a = indices[t * 3], b = indices[t * 3 + 1], c = indices[t * 3 + 2]
            // The format forbids a triangle naming one vertex twice.
            guard a != b, b != c, a != c else { continue }
            model += "     <triangle v1=\"\(a)\" v2=\"\(b)\" v3=\"\(c)\"/>\n"
        }
        model += """
                </triangles>
               </mesh>
              </object>
             </resources>
             <build>
              <item objectid="1" transform="1 0 0 0 1 0 0 0 1 \(plateCentreMM.x) \(plateCentreMM.y) 0"/>
             </build>
            </model>

            """

        let contentTypes = """
            <?xml version="1.0" encoding="UTF-8"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
             <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
             <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
            </Types>

            """
        let relationships = """
            <?xml version="1.0" encoding="UTF-8"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
             <Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
            </Relationships>

            """

        let package = ZipWriter.archive([
            ZipWriter.Entry(path: "[Content_Types].xml", data: Data(contentTypes.utf8)),
            ZipWriter.Entry(path: "_rels/.rels", data: Data(relationships.utf8)),
            ZipWriter.Entry(path: "3D/3dmodel.model", data: Data(model.utf8)),
        ])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try package.write(to: url, options: .atomic)
    }

    static func xmlEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// The smallest ZIP writer a 3MF package needs: flat entries, deflated where that
/// helps, no ZIP64. iOS has no public ZIP API; Compression supplies the deflate.
enum ZipWriter {
    struct Entry {
        let path: String
        let data: Data
    }

    static func archive(_ entries: [Entry]) -> Data {
        var archive = Data()
        var directory = Data()

        for entry in entries {
            let name = Data(entry.path.utf8)
            let crc = crc32(entry.data)
            let deflated = deflate(entry.data)
            let method: UInt16 = deflated == nil ? 0 : 8
            let body = deflated ?? entry.data
            let offset = UInt32(archive.count)

            archive.appendLittleEndian(UInt32(0x0403_4B50))  // local file header
            archive.appendLittleEndian(UInt16(20))           // version needed: 2.0
            archive.appendLittleEndian(UInt16(0))            // flags
            archive.appendLittleEndian(method)
            archive.appendLittleEndian(UInt16(0))            // time
            archive.appendLittleEndian(dosDate)
            archive.appendLittleEndian(crc)
            archive.appendLittleEndian(UInt32(body.count))
            archive.appendLittleEndian(UInt32(entry.data.count))
            archive.appendLittleEndian(UInt16(name.count))
            archive.appendLittleEndian(UInt16(0))            // extra field length
            archive.append(name)
            archive.append(body)

            directory.appendLittleEndian(UInt32(0x0201_4B50)) // central directory header
            directory.appendLittleEndian(UInt16(20))          // version made by
            directory.appendLittleEndian(UInt16(20))          // version needed
            directory.appendLittleEndian(UInt16(0))           // flags
            directory.appendLittleEndian(method)
            directory.appendLittleEndian(UInt16(0))           // time
            directory.appendLittleEndian(dosDate)
            directory.appendLittleEndian(crc)
            directory.appendLittleEndian(UInt32(body.count))
            directory.appendLittleEndian(UInt32(entry.data.count))
            directory.appendLittleEndian(UInt16(name.count))
            directory.appendLittleEndian(UInt16(0))           // extra field length
            directory.appendLittleEndian(UInt16(0))           // comment length
            directory.appendLittleEndian(UInt16(0))           // disk number
            directory.appendLittleEndian(UInt16(0))           // internal attributes
            directory.appendLittleEndian(UInt32(0))           // external attributes
            directory.appendLittleEndian(offset)
            directory.append(name)
        }

        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        archive.appendLittleEndian(UInt32(0x0605_4B50))      // end of central directory
        archive.appendLittleEndian(UInt16(0))                // this disk
        archive.appendLittleEndian(UInt16(0))                // disk with the directory
        archive.appendLittleEndian(UInt16(entries.count))    // entries on this disk
        archive.appendLittleEndian(UInt16(entries.count))    // entries in total
        archive.appendLittleEndian(UInt32(directory.count))
        archive.appendLittleEndian(directoryOffset)
        archive.appendLittleEndian(UInt16(0))                // comment length
        return archive
    }

    /// 1 January 1980, ZIP's epoch. A fixed date keeps two exports of the same model
    /// byte-identical.
    private static let dosDate: UInt16 = (0 << 9) | (1 << 5) | 1

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 {
            c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { bytes in
            for byte in bytes {
                crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    /// Raw DEFLATE, which is what COMPRESSION_ZLIB produces and what ZIP's method 8
    /// expects. Nil when it would not make the entry smaller, so it is stored instead.
    static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        var out = Data(count: data.count)
        let written = out.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_encode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                          source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        out.count = written
        return out
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
