import Foundation
import ModelIO
import SceneKit
import UIKit
import simd

enum MeshError: LocalizedError {
    case noGeometry

    var errorDescription: String? { "The model file contains no triangle geometry." }
}

/// Vertices are matched at micron precision, which is far finer than a printer
/// resolves and coarse enough to fuse the duplicates a plane cut produces.
private struct VertexKey: Hashable {
    let x: Int32, y: Int32, z: Int32

    init(_ p: SIMD3<Float>) {
        x = Int32((p.x * 1000).rounded())
        y = Int32((p.y * 1000).rounded())
        z = Int32((p.z * 1000).rounded())
    }
}

/// The same idea for points known to share one Z, used to chain the cut rim into loops.
private struct PlanarKey: Hashable {
    let x: Int32, y: Int32

    init(_ p: SIMD3<Float>) {
        x = Int32((p.x * 1000).rounded())
        y = Int32((p.y * 1000).rounded())
    }
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

    /// Slices everything below `trimMM` off the bottom and closes the opening with a
    /// flat face, so the print meets the bed on a solid surface instead of on whatever
    /// ragged geometry the scanner reconstructed underneath the object. The result is
    /// re-seated on Z = 0 and re-centred, so it stays ready to export.
    func flatBase(trimMM: Float) -> MeshData {
        // Leave a sane amount of the object behind even if the caller asks for more.
        let cut = min(max(trimMM, 0), sizeMM.z * 0.9)
        guard cut > 0 else { return self }

        var outVertices: [SIMD3<Float>] = []
        var outIndices: [UInt32] = []
        var lookup: [VertexKey: UInt32] = [:]

        func index(of p: SIMD3<Float>) -> UInt32 {
            let key = VertexKey(p)
            if let existing = lookup[key] { return existing }
            let index = UInt32(outVertices.count)
            lookup[key] = index
            outVertices.append(p)
            return index
        }

        func emit(_ p: SIMD3<Float>, _ q: SIMD3<Float>, _ r: SIMD3<Float>) {
            let i = index(of: p), j = index(of: q), k = index(of: r)
            // A plane passing through an existing vertex collapses a triangle onto a line
            // or a point. Those slivers carry no volume but do break watertightness, so
            // they never make it into the output.
            guard i != j, j != k, i != k else { return }
            outIndices.append(i)
            outIndices.append(j)
            outIndices.append(k)
        }

        /// Where edge p->q meets the cut plane. `p` is on or above it, `q` strictly below,
        /// so the denominator is always positive.
        func crossing(_ p: SIMD3<Float>, _ q: SIMD3<Float>) -> SIMD3<Float> {
            var point = q + (p - q) * ((cut - q.z) / (p.z - q.z))
            point.z = cut
            return point
        }

        // Directed edges left along the cut plane, in the winding order of the kept surface.
        var rim: [(from: SIMD3<Float>, to: SIMD3<Float>)] = []

        // Scans run to hundreds of thousands of triangles, so this loop stays free of
        // per-triangle allocations.
        for t in 0..<triangleCount {
            let v0 = vertices[Int(indices[t * 3])]
            let v1 = vertices[Int(indices[t * 3 + 1])]
            let v2 = vertices[Int(indices[t * 3 + 2])]
            let above0 = v0.z >= cut, above1 = v1.z >= cut, above2 = v2.z >= cut

            switch (above0 ? 1 : 0) + (above1 ? 1 : 0) + (above2 ? 1 : 0) {
            case 3:
                emit(v0, v1, v2)

            case 2:
                // Rotate so the single dropped vertex lands last; a cyclic shift keeps winding.
                let a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>
                if !above0 { (a, b, c) = (v1, v2, v0) }
                else if !above1 { (a, b, c) = (v2, v0, v1) }
                else { (a, b, c) = (v0, v1, v2) }

                let bc = crossing(b, c), ca = crossing(a, c)
                emit(a, b, bc)
                emit(a, bc, ca)
                if PlanarKey(bc) != PlanarKey(ca) { rim.append((bc, ca)) }

            case 1:
                let a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>
                if above0 { (a, b, c) = (v0, v1, v2) }
                else if above1 { (a, b, c) = (v1, v2, v0) }
                else { (a, b, c) = (v2, v0, v1) }

                let ab = crossing(a, b), ca = crossing(a, c)
                emit(a, ab, ca)
                if PlanarKey(ab) != PlanarKey(ca) { rim.append((ab, ca)) }

            default:
                continue // entirely below the cut
            }
        }

        guard !outIndices.isEmpty else { return self }

        // Chain the rim into closed loops and fan each one from its own centre. Scanned
        // cross-sections are near-convex, and a per-loop fan keeps objects that cut into
        // several pieces (a handle, two legs) capped separately rather than bridged.
        var startingAt: [PlanarKey: [Int]] = [:]
        for (i, edge) in rim.enumerated() {
            startingAt[PlanarKey(edge.from), default: []].append(i)
        }
        var used = [Bool](repeating: false, count: rim.count)

        for seed in rim.indices where !used[seed] {
            var loop: [SIMD3<Float>] = []
            var current = seed
            while !used[current] {
                used[current] = true
                loop.append(rim[current].from)
                guard let candidates = startingAt[PlanarKey(rim[current].to)],
                      let next = candidates.first(where: { !used[$0] }) else { break }
                current = next
            }
            guard loop.count >= 3 else { continue }

            var centre = loop.reduce(SIMD3<Float>.zero, +) / Float(loop.count)
            centre.z = cut

            for i in loop.indices {
                let p = loop[i], q = loop[(i + 1) % loop.count]
                // This cap is the underside of the print, so force every triangle to face
                // down rather than trusting the rim's direction.
                if simd_cross(q - p, centre - p).z < 0 {
                    emit(p, q, centre)
                } else {
                    emit(q, p, centre)
                }
            }
        }

        var lo = outVertices[0], hi = outVertices[0]
        for v in outVertices {
            lo = simd_min(lo, v)
            hi = simd_max(hi, v)
        }
        let offset = SIMD3<Float>(-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z)

        return MeshData(vertices: outVertices.map { $0 + offset }, indices: outIndices, sizeMM: hi - lo)
    }

    /// Untextured preview geometry. Stays Z-up, so the displaying node has to be rotated.
    func makeGeometry() -> SCNGeometry {
        var normals = [SIMD3<Float>](repeating: .zero, count: vertices.count)
        for t in 0..<triangleCount {
            let i = (Int(indices[t * 3]), Int(indices[t * 3 + 1]), Int(indices[t * 3 + 2]))
            // Un-normalised, so each face contributes in proportion to its area.
            let n = simd_cross(vertices[i.1] - vertices[i.0], vertices[i.2] - vertices[i.0])
            normals[i.0] += n
            normals[i.1] += n
            normals[i.2] += n
        }

        let positions = SCNGeometrySource(vertices: vertices.map { SCNVector3($0.x, $0.y, $0.z) })
        let shading = SCNGeometrySource(normals: normals.map { n -> SCNVector3 in
            let length = simd_length(n)
            let unit = length > 0 ? n / length : SIMD3<Float>(0, 0, 1)
            return SCNVector3(unit.x, unit.y, unit.z)
        })
        let geometry = SCNGeometry(sources: [positions, shading],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])

        let material = SCNMaterial()
        material.diffuse.contents = UIColor.systemGray2
        material.lightingModel = .blinn
        material.isDoubleSided = true
        geometry.materials = [material]
        return geometry
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
