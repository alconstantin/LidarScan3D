import Foundation
import ModelIO
import simd

enum MeshError: LocalizedError {
    case noGeometry

    var errorDescription: String? { "The model file contains no triangle geometry." }
}

/// Vertices are matched at micron precision, which is far finer than a printer
/// resolves and coarse enough to fuse the duplicates a plane cut produces.
struct VertexKey: Hashable {
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

/// An undirected mesh edge. Support-plane triangles are joined only through shared
/// edges, never merely through a corner, so two nearby surfaces stay independent.
private struct EdgeKey: Hashable {
    let low: UInt32
    let high: UInt32

    init(_ a: UInt32, _ b: UInt32) {
        low = min(a, b)
        high = max(a, b)
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
        return welded(vertices: vertices, indices: indices)
    }

    /// Fuses vertices that share a position, then seats the result.
    ///
    /// Object Capture splits a vertex wherever a texture seam runs through it, so one
    /// point on the surface can appear several times under different indices. The
    /// triangles either side of a seam then share no edge, and the mesh reads as full
    /// of holes to anything that counts edges -- the printability report included.
    /// Triangles that collapse when their corners fuse are dropped.
    static func welded(vertices: [SIMD3<Float>], indices: [UInt32]) -> MeshData {
        var lookup: [VertexKey: UInt32] = [:]
        lookup.reserveCapacity(vertices.count)
        var unique: [SIMD3<Float>] = []
        var remap = [UInt32](repeating: 0, count: vertices.count)
        for (i, v) in vertices.enumerated() {
            let key = VertexKey(v)
            if let existing = lookup[key] {
                remap[i] = existing
            } else {
                remap[i] = UInt32(unique.count)
                lookup[key] = remap[i]
                unique.append(v)
            }
        }

        var fused: [UInt32] = []
        fused.reserveCapacity(indices.count)
        for t in 0..<indices.count / 3 {
            let a = remap[Int(indices[t * 3])], b = remap[Int(indices[t * 3 + 1])], c = remap[Int(indices[t * 3 + 2])]
            guard a != b, b != c, a != c else { continue }
            fused.append(a)
            fused.append(b)
            fused.append(c)
        }
        return seated(vertices: unique, indices: fused)
    }

    /// Re-centres on X/Y, seats the lowest point on Z = 0 and recomputes the print size.
    /// Everything that moves geometry ends here, so exports always rest on the bed.
    static func seated(vertices: [SIMD3<Float>], indices: [UInt32]) -> MeshData {
        guard let first = vertices.first else {
            return MeshData(vertices: [], indices: [], sizeMM: .zero)
        }
        var lo = first, hi = first
        for v in vertices {
            lo = simd_min(lo, v)
            hi = simd_max(hi, v)
        }
        let offset = SIMD3<Float>(-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z)
        return MeshData(vertices: vertices.map { $0 + offset }, indices: indices, sizeMM: hi - lo)
    }

    /// The same mesh turned by `rotation` and re-seated on the bed.
    func rotated(by rotation: simd_quatf) -> MeshData {
        // An identity quaternion has no imaginary part; skip the pass entirely.
        guard simd_length(rotation.imag) > 1e-6 else { return self }
        return MeshData.seated(vertices: vertices.map { rotation.act($0) }, indices: indices)
    }

    /// The same mesh turned about Z so its footprint lines up with X and Y.
    ///
    /// Object Capture leaves the model at whatever heading the capture happened to
    /// start from, so a box scanned at an angle reads as its diagonal: a 40 mm cube
    /// turned 34° measured 57.9 × 56.8 mm. Every size the app shows, and the
    /// calibration built on them, is only meaningful once the model is squared up.
    func squaredUp() -> MeshData {
        let angle = MeshData.squaringAngle(vertices.map { SIMD2($0.x, $0.y) })
        guard angle != 0 else { return self }
        return rotated(by: simd_quatf(angle: angle, axis: SIMD3(0, 0, 1)))
    }

    /// The turn about Z, within ±45°, that gives `points` the smallest bounding
    /// rectangle, or 0 when no turn helps.
    ///
    /// The smallest rectangle around a convex polygon has one side along one of its
    /// edges, so only the hull's edge directions need trying. A round footprint has no
    /// heading worth squaring to, so a turn that saves less than 1 % of the area is
    /// not made: a vase is left as it was rather than spun by noise.
    static func squaringAngle(_ points: [SIMD2<Float>]) -> Float {
        let hull = convexHull(points)
        guard hull.count >= 3 else { return 0 }

        func footprint(turnedBy angle: Float) -> Float {
            let c = cos(angle), s = sin(angle)
            var lo = SIMD2<Float>(repeating: .infinity), hi = -lo
            for p in hull {
                let q = SIMD2(c * p.x - s * p.y, s * p.x + c * p.y)
                lo = simd_min(lo, q)
                hi = simd_max(hi, q)
            }
            let extent = hi - lo
            return extent.x * extent.y
        }

        let unturned = footprint(turnedBy: 0)
        var best = (area: unturned, angle: Float(0))
        for i in hull.indices {
            let edge = hull[(i + 1) % hull.count] - hull[i]
            let angle = -atan2(edge.y, edge.x) // lays this edge along X
            let area = footprint(turnedBy: angle)
            if area < best.area { best = (area, angle) }
        }
        guard best.area < unturned * 0.99 else { return 0 }

        // A rectangle looks the same after every quarter turn; make the smallest one.
        let quarter = Float.pi / 2
        var angle = best.angle.truncatingRemainder(dividingBy: quarter)
        if angle > quarter / 2 { angle -= quarter } else if angle < -quarter / 2 { angle += quarter }
        return angle
    }

    /// Andrew's monotone chain, counter-clockwise, collinear points dropped.
    static func convexHull(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        let sorted = points.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        guard sorted.count >= 3 else { return sorted }
        func turn(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [SIMD2<Float>] = []
        for p in sorted {
            while lower.count >= 2, turn(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        var upper: [SIMD2<Float>] = []
        for p in sorted.reversed() {
            while upper.count >= 2, turn(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }

    /// A quarter turn about `axis`, for choosing which side of the scan faces the bed.
    /// Quarter turns about X and Y reach all 24 axis-aligned orientations between them.
    static func quarterTurn(about axis: SIMD3<Float>, clockwise: Bool) -> simd_quatf {
        simd_quatf(angle: clockwise ? -.pi / 2 : .pi / 2, axis: axis)
    }

    static let noRotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1))

    /// Removes the largest connected, nearly-horizontal patch close to the bottom of
    /// the scan. Object Capture commonly includes the table or turntable as a broad
    /// flat sheet; a cylinder's base is a separate patch, so it is not joined to that
    /// sheet through this planar-only graph.
    ///
    /// This is deliberately opt-in. A clean object can itself have a broad flat base,
    /// and only the person looking at the preview can safely distinguish that from a
    /// captured support surface. The caller can follow this with `flatBase(trimMM:)`
    /// to cap the opening left by the removed sheet.
    func removingSupportSurface() -> SupportSurfaceRemoval? {
        guard triangleCount >= 3, sizeMM.z > 0 else { return nil }

        // Depth reconstruction is noisy at the contact patch. Keep the band tight
        // enough not to catch a low shelf, but never below one millimetre.
        let bottomBand = min(max(sizeMM.z * 0.03, 1), 8)
        let minimumArea = max(sizeMM.x * sizeMM.y * 0.05, 25)
        let nearlyHorizontal: Float = 0.94 // within about 20 degrees of horizontal

        var parent = [Int](repeating: -1, count: triangleCount)
        var area = [Float](repeating: 0, count: triangleCount)
        var edgeOwner: [EdgeKey: Int] = [:]

        func root(_ value: Int) -> Int {
            var node = value
            while parent[node] != node { node = parent[node] }
            return node
        }

        func join(_ lhs: Int, _ rhs: Int) {
            let a = root(lhs), b = root(rhs)
            guard a != b else { return }
            parent[b] = a
        }

        for t in 0..<triangleCount {
            let i = t * 3
            let a = vertices[Int(indices[i])]
            let b = vertices[Int(indices[i + 1])]
            let c = vertices[Int(indices[i + 2])]
            let normal = simd_cross(b - a, c - a)
            let doubleArea = simd_length(normal)
            guard doubleArea > 1e-5 else { continue }

            let centroidZ = (a.z + b.z + c.z) / 3
            guard centroidZ <= bottomBand,
                  abs(normal.z) / doubleArea >= nearlyHorizontal else { continue }

            parent[t] = t
            area[t] = doubleArea / 2
            for edge in [EdgeKey(indices[i], indices[i + 1]),
                         EdgeKey(indices[i + 1], indices[i + 2]),
                         EdgeKey(indices[i + 2], indices[i])] {
                if let neighbour = edgeOwner[edge] { join(t, neighbour) }
                else { edgeOwner[edge] = t }
            }
        }

        var componentArea: [Int: Float] = [:]
        for t in 0..<triangleCount where parent[t] >= 0 {
            componentArea[root(t), default: 0] += area[t]
        }
        guard let support = componentArea.max(by: { $0.value < $1.value }),
              support.value >= minimumArea else { return nil }

        // A clean box or cylinder has a flat bottom too. A captured table earns its
        // name only when it extends visibly beyond the rest of the object in X or Y.
        var supportLow = SIMD2<Float>(repeating: .infinity)
        var supportHigh = -supportLow
        var objectLow = SIMD2<Float>(repeating: .infinity)
        var objectHigh = -objectLow
        for t in 0..<triangleCount {
            let targetIsSupport = parent[t] >= 0 && root(t) == support.key
            let i = t * 3
            for index in indices[i..<(i + 3)] {
                let xy = SIMD2(vertices[Int(index)].x, vertices[Int(index)].y)
                if targetIsSupport {
                    supportLow = simd_min(supportLow, xy)
                    supportHigh = simd_max(supportHigh, xy)
                } else {
                    objectLow = simd_min(objectLow, xy)
                    objectHigh = simd_max(objectHigh, xy)
                }
            }
        }
        let supportSpan = supportHigh - supportLow
        let objectSpan = objectHigh - objectLow
        guard supportSpan.x > objectSpan.x * 1.1 || supportSpan.y > objectSpan.y * 1.1 else { return nil }

        var kept: [UInt32] = []
        kept.reserveCapacity(indices.count)
        var removed = 0
        for t in 0..<triangleCount {
            if parent[t] >= 0, root(t) == support.key {
                removed += 1
                continue
            }
            let i = t * 3
            kept.append(indices[i])
            kept.append(indices[i + 1])
            kept.append(indices[i + 2])
        }
        guard removed > 0, !kept.isEmpty else { return nil }

        // `seated` intentionally looks at every supplied vertex. Compact first so
        // the removed table cannot keep affecting the exported bounding box.
        var remap: [UInt32: UInt32] = [:]
        var compactVertices: [SIMD3<Float>] = []
        var compactIndices: [UInt32] = []
        compactIndices.reserveCapacity(kept.count)
        for index in kept {
            if let mapped = remap[index] {
                compactIndices.append(mapped)
            } else {
                let mapped = UInt32(compactVertices.count)
                remap[index] = mapped
                compactVertices.append(vertices[Int(index)])
                compactIndices.append(mapped)
            }
        }
        return SupportSurfaceRemoval(
            mesh: MeshData.seated(vertices: compactVertices, indices: compactIndices),
            removedTriangles: removed
        )
    }

    /// Drops disconnected fragments that are tiny beside the main reconstruction.
    /// These are commonly bits of the background or a noisy LiDAR reflection. It
    /// deliberately keeps every substantial component: a scanned object may really
    /// have separate legs, a lid, or several parts placed together.
    func removingSmallComponents() -> SmallComponentCleanup? {
        guard triangleCount >= 2 else { return nil }

        var parent = Array(0..<triangleCount)
        var triangleArea = [Float](repeating: 0, count: triangleCount)
        var edgeOwner: [EdgeKey: Int] = [:]

        func root(_ value: Int) -> Int {
            var node = value
            while parent[node] != node { node = parent[node] }
            return node
        }

        func join(_ lhs: Int, _ rhs: Int) {
            let a = root(lhs), b = root(rhs)
            guard a != b else { return }
            parent[b] = a
        }

        for t in 0..<triangleCount {
            let i = t * 3
            let a = vertices[Int(indices[i])]
            let b = vertices[Int(indices[i + 1])]
            let c = vertices[Int(indices[i + 2])]
            triangleArea[t] = simd_length(simd_cross(b - a, c - a)) / 2
            for edge in [EdgeKey(indices[i], indices[i + 1]),
                         EdgeKey(indices[i + 1], indices[i + 2]),
                         EdgeKey(indices[i + 2], indices[i])] {
                if let neighbour = edgeOwner[edge] { join(t, neighbour) }
                else { edgeOwner[edge] = t }
            }
        }

        var componentArea: [Int: Float] = [:]
        for t in 0..<triangleCount {
            componentArea[root(t), default: 0] += triangleArea[t]
        }
        guard componentArea.count > 1,
              let largest = componentArea.values.max() else { return nil }

        // At most half a percent of the main surface, and never discard a component
        // with 25 mm² or more: that is large enough to be intentional on small models.
        let minimumArea = max(largest * 0.005, 25)
        let discarded = Set(componentArea.compactMap { $0.value < minimumArea ? $0.key : nil })
        guard !discarded.isEmpty else { return nil }

        var kept: [UInt32] = []
        kept.reserveCapacity(indices.count)
        var removedTriangles = 0
        for t in 0..<triangleCount {
            if discarded.contains(root(t)) {
                removedTriangles += 1
            } else {
                let i = t * 3
                kept.append(contentsOf: indices[i..<(i + 3)])
            }
        }
        guard !kept.isEmpty else { return nil }

        var remap: [UInt32: UInt32] = [:]
        var compactVertices: [SIMD3<Float>] = []
        var compactIndices: [UInt32] = []
        compactIndices.reserveCapacity(kept.count)
        for index in kept {
            if let mapped = remap[index] {
                compactIndices.append(mapped)
            } else {
                let mapped = UInt32(compactVertices.count)
                remap[index] = mapped
                compactVertices.append(vertices[Int(index)])
                compactIndices.append(mapped)
            }
        }
        return SmallComponentCleanup(
            mesh: MeshData.seated(vertices: compactVertices, indices: compactIndices),
            removedTriangles: removedTriangles,
            removedComponents: discarded.count
        )
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

        // Chain the rim into closed loops. An object that cuts into several pieces (a
        // handle, two legs) gives several loops, and a hollow or ring-footed one (a bowl,
        // a vase) gives loops inside loops; the cap has to respect both.
        var startingAt: [PlanarKey: [Int]] = [:]
        for (i, edge) in rim.enumerated() {
            startingAt[PlanarKey(edge.from), default: []].append(i)
        }
        var used = [Bool](repeating: false, count: rim.count)
        var loops: [[CapTriangulation.Point]] = []

        for seed in rim.indices where !used[seed] {
            var loop: [CapTriangulation.Point] = []
            var current = seed
            while !used[current] {
                used[current] = true
                let from = rim[current].from
                loop.append(CapTriangulation.Point(Double(from.x), Double(from.y)))
                guard let candidates = startingAt[PlanarKey(rim[current].to)],
                      let next = candidates.first(where: { !used[$0] }) else { break }
                current = next
            }
            if loop.count >= 3 { loops.append(loop) }
        }

        // The triangulation winds counter-clockwise seen from above. This cap is the
        // underside of the print, so every triangle is emitted reversed to face the bed,
        // whatever direction the rim happened to run in.
        func onPlane(_ p: CapTriangulation.Point) -> SIMD3<Float> {
            SIMD3(Float(p.x), Float(p.y), cut)
        }
        for (p, q, r) in CapTriangulation.triangulate(loops) {
            emit(onPlane(p), onPlane(r), onPlane(q))
        }

        return MeshData.seated(vertices: outVertices, indices: outIndices)
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

/// The result of removing a broad horizontal patch at the bottom of a scan.
/// The triangle count is shown in the UI so the operation is never invisible.
struct SupportSurfaceRemoval: Sendable {
    let mesh: MeshData
    let removedTriangles: Int
}

/// The result of discarding isolated reconstruction fragments.
struct SmallComponentCleanup: Sendable {
    let mesh: MeshData
    let removedTriangles: Int
    let removedComponents: Int
}

/// A deliberately small set of finishing strengths. They smooth reconstruction noise,
/// not the object's shape; sharp creases and open edges are left alone.
enum MeshSmoothingLevel: String, CaseIterable, Identifiable, Sendable {
    case off, light, medium, strong

    var id: Self { self }

    var label: String {
        switch self {
        case .off: "Off"
        case .light: "Light"
        case .medium: "Medium"
        case .strong: "Strong"
        }
    }

    fileprivate var iterations: Int {
        switch self {
        case .off: 0
        case .light: 2
        case .medium: 4
        case .strong: 7
        }
    }
}

private struct SmoothingEdge: Hashable {
    let low: UInt32
    let high: UInt32

    init(_ a: UInt32, _ b: UInt32) {
        low = min(a, b)
        high = max(a, b)
    }
}

private struct SmoothingEdgeFaces {
    var first: Int
    var second: Int?
}

extension MeshData {
    /// Smooths gentle photogrammetry noise with a Taubin pass, without changing the
    /// mesh topology. Neighbours across a sharp crease are not joined, and vertices
    /// touching an open or non-manifold edge stay fixed so smoothing cannot enlarge a
    /// hole or round its rim.
    func smoothed(level: MeshSmoothingLevel) -> MeshData {
        guard level.iterations > 0, triangleCount > 0 else { return self }

        var edgeFaces: [SmoothingEdge: SmoothingEdgeFaces] = [:]
        edgeFaces.reserveCapacity(indices.count)

        for face in 0..<triangleCount {
            let start = face * 3
            let triangle = [indices[start], indices[start + 1], indices[start + 2]]
            guard triangle.allSatisfy({ Int($0) < vertices.count }) else { return self }
            for (a, b) in [(triangle[0], triangle[1]), (triangle[1], triangle[2]), (triangle[2], triangle[0])] {
                let edge = SmoothingEdge(a, b)
                if var faces = edgeFaces[edge] {
                    if faces.second == nil { faces.second = face }
                    else { faces.second = -1 } // Three or more faces: do not smooth through it.
                    edgeFaces[edge] = faces
                } else {
                    edgeFaces[edge] = SmoothingEdgeFaces(first: face, second: nil)
                }
            }
        }

        var faceNormals = [SIMD3<Float>](repeating: .zero, count: triangleCount)
        for face in 0..<triangleCount {
            let start = face * 3
            let a = vertices[Int(indices[start])]
            let b = vertices[Int(indices[start + 1])]
            let c = vertices[Int(indices[start + 2])]
            let cross = simd_cross(b - a, c - a)
            let length = simd_length(cross)
            if length > 1e-6 { faceNormals[face] = cross / length }
        }

        var neighbours = Array(repeating: Set<Int>(), count: vertices.count)
        var fixed = Array(repeating: false, count: vertices.count)
        // A 40-degree crease is a useful boundary between scan noise and a designed
        // edge. The threshold is conservative because this tool must not soften detail.
        let sharpnessCosine = cos(Float.pi * 40 / 180)
        for (edge, faces) in edgeFaces {
            let a = Int(edge.low), b = Int(edge.high)
            guard let other = faces.second, other >= 0 else {
                fixed[a] = true
                fixed[b] = true
                continue
            }
            guard simd_dot(faceNormals[faces.first], faceNormals[other]) >= sharpnessCosine else {
                // A crease belongs to the object's shape, not the scan noise. Keeping
                // its endpoints fixed also prevents in-face diagonals from rounding it.
                fixed[a] = true
                fixed[b] = true
                continue
            }
            neighbours[a].insert(b)
            neighbours[b].insert(a)
        }

        func pass(_ input: [SIMD3<Float>], factor: Float) -> [SIMD3<Float>] {
            var output = input
            for i in input.indices where !fixed[i] && !neighbours[i].isEmpty {
                let average = neighbours[i].reduce(SIMD3<Float>.zero) { $0 + input[$1] } / Float(neighbours[i].count)
                output[i] += (average - input[i]) * factor
            }
            return output
        }

        var result = vertices
        for _ in 0..<level.iterations {
            // The negative pass counters the volume loss of ordinary Laplacian smoothing.
            result = pass(result, factor: 0.28)
            result = pass(result, factor: -0.29)
        }
        return MeshData.seated(vertices: result, indices: indices)
    }
}
