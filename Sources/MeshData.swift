import Foundation
import ModelIO
import simd

enum MeshError: LocalizedError {
    case noGeometry

    var errorDescription: String? { "The model file contains no triangle geometry." }
}

/// Triangle mesh prepared for 3D printing: millimetres, Z-up, centred on X/Y and resting on Z = 0.
struct MeshData: Sendable {
    var vertices: [SIMD3<Float>]
    var indices: [UInt32]
    var sizeMM: SIMD3<Float>

    var triangleCount: Int { indices.count / 3 }
    var longestSideMM: Float { sizeMM.max() }

    /// Reads the USDZ produced by Object Capture (Y-up, metres).
    static func load(from url: URL) throws -> MeshData {
        let asset = MDLAsset(url: url)
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        let meshes = asset.childObjects(of: MDLMesh.self).compactMap { $0 as? MDLMesh }
        for mesh in meshes {
            guard let positions = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition, as: .float3) else {
                continue
            }
            let world = MDLTransform.globalTransform(with: mesh, atTime: 0)
            let base = UInt32(vertices.count)

            for i in 0..<mesh.vertexCount {
                let p = positions.dataStart
                    .advanced(by: i * positions.stride)
                    .assumingMemoryBound(to: Float.self)
                let w = world * SIMD4<Float>(p[0], p[1], p[2], 1)
                // Y-up metres -> Z-up millimetres (a proper rotation, so triangle winding is kept).
                vertices.append(SIMD3(w.x, -w.z, w.y) * 1000)
            }

            let submeshes = (mesh.submeshes as? [MDLSubmesh]) ?? []
            for submesh in submeshes where submesh.geometryType == .triangles {
                let map = submesh.indexBuffer(asIndexType: .uInt32).map()
                let submeshIndices = map.bytes.assumingMemoryBound(to: UInt32.self)
                for i in 0..<submesh.indexCount {
                    indices.append(base + submeshIndices[i])
                }
            }
        }
        guard !indices.isEmpty else { throw MeshError.noGeometry }

        var lo = vertices[0]
        var hi = vertices[0]
        for v in vertices {
            lo = simd_min(lo, v)
            hi = simd_max(hi, v)
        }
        let offset = SIMD3<Float>(-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z)
        vertices = vertices.map { $0 + offset }

        return MeshData(vertices: vertices, indices: indices, sizeMM: hi - lo)
    }

    func writeBinarySTL(to url: URL, scale: Float) throws {
        let count = triangleCount
        var data = Data(count: 84 + count * 50) // zero-filled, so attribute bytes are already 0

        data.withUnsafeMutableBytes { raw in
            let header = Array("LiDAR Scan 3D binary STL, units: mm".utf8)
            raw.copyBytes(from: header)
            raw.storeBytes(of: UInt32(count).littleEndian, toByteOffset: 80, as: UInt32.self)

            var offset = 84
            func put(_ v: SIMD3<Float>) {
                raw.storeBytes(of: v.x, toByteOffset: offset, as: Float.self)
                raw.storeBytes(of: v.y, toByteOffset: offset + 4, as: Float.self)
                raw.storeBytes(of: v.z, toByteOffset: offset + 8, as: Float.self)
                offset += 12
            }

            for t in 0..<count {
                let a = vertices[Int(indices[t * 3])] * scale
                let b = vertices[Int(indices[t * 3 + 1])] * scale
                let c = vertices[Int(indices[t * 3 + 2])] * scale
                let n = simd_cross(b - a, c - a)
                let length = simd_length(n)
                put(length > 0 ? n / length : .zero)
                put(a)
                put(b)
                put(c)
                offset += 2
            }
        }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func writeOBJ(to url: URL, scale: Float) throws {
        var text = "# LiDAR Scan 3D export, units: mm\n"
        text.reserveCapacity(vertices.count * 36 + triangleCount * 24)
        for v in vertices {
            let s = v * scale
            text += "v \(s.x) \(s.y) \(s.z)\n"
        }
        for t in 0..<triangleCount {
            text += "f \(indices[t * 3] + 1) \(indices[t * 3 + 1] + 1) \(indices[t * 3 + 2] + 1)\n"
        }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
