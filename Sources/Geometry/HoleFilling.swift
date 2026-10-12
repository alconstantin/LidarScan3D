import Foundation
import simd

struct HoleFill: Sendable {
    let mesh: MeshData
    let filledHoles: Int
    let addedTriangles: Int
    /// Open loops left alone: too long, or not a simple chain of boundary edges.
    let skippedHoles: Int
}

extension MeshData {
    /// Closes open boundary loops of at most `maxEdges` edges, or nil when the mesh
    /// has no holes.
    ///
    /// Each hole is laid onto its best-fit plane and ear-clipped, so a concave hole is
    /// covered exactly. Holes that do not project to a simple outline, such as a
    /// strongly saddle-shaped gap, fall back to a fan from their centre. The patches
    /// are wound to match the surrounding surface. This closes gaps; it does not
    /// rebuild missing shape, which is why a large opening such as a missing
    /// underside is left to the flat base cut instead.
    func fillingHoles(maxEdges: Int = 300) -> HoleFill? {
        // A boundary edge is used by one triangle only. The patch must run the other way
        // along it, so the chains are built from reversed edges.
        var undirected: [UInt64: Int] = [:]
        for t in 0..<triangleCount {
            for k in 0..<3 {
                let a = indices[3 * t + k], b = indices[3 * t + (k + 1) % 3]
                undirected[UInt64(min(a, b)) << 32 | UInt64(max(a, b)), default: 0] += 1
            }
        }
        var outgoing: [UInt32: [UInt32]] = [:]
        var boundaryEdges = 0
        for t in 0..<triangleCount {
            for k in 0..<3 {
                let a = indices[3 * t + k], b = indices[3 * t + (k + 1) % 3]
                guard undirected[UInt64(min(a, b)) << 32 | UInt64(max(a, b))] == 1 else { continue }
                outgoing[b, default: []].append(a)
                boundaryEdges += 1
            }
        }
        guard boundaryEdges > 0 else { return nil }

        var loops: [[UInt32]] = []
        var skipped = 0
        var remaining = outgoing
        for start in outgoing.keys.sorted() {
            while let first = remaining[start]?.first {
                remaining[start]?.removeFirst()
                var loop = [start]
                var current = first
                var closed = false
                while loop.count <= boundaryEdges {
                    if current == start { closed = true; break }
                    loop.append(current)
                    guard let next = remaining[current]?.first else { break }
                    remaining[current]?.removeFirst()
                    current = next
                }
                // A vertex where two holes touch makes the chain ambiguous; leave it.
                let simple = Set(loop).count == loop.count
                if closed, simple, loop.count >= 3, loop.count <= maxEdges { loops.append(loop) } else { skipped += 1 }
            }
        }
        guard !loops.isEmpty else {
            return HoleFill(mesh: self, filledHoles: 0, addedTriangles: 0, skippedHoles: skipped)
        }

        var outVertices = vertices
        var outIndices = indices
        var added = 0
        for loop in loops {
            let patch = Self.patch(loop, vertices: vertices, nextVertex: UInt32(outVertices.count))
            outVertices += patch.newVertices
            outIndices += patch.indices
            added += patch.indices.count / 3
        }
        return HoleFill(mesh: MeshData.seated(vertices: outVertices, indices: outIndices),
                        filledHoles: loops.count, addedTriangles: added, skippedHoles: skipped)
    }

    private static func patch(_ loop: [UInt32], vertices: [SIMD3<Float>], nextVertex: UInt32) -> (indices: [UInt32], newVertices: [SIMD3<Float>]) {
        let points = loop.map { SIMD3<Double>(vertices[Int($0)]) }
        if loop.count == 3 { return ([loop[0], loop[1], loop[2]], []) }

        // Newell's method gives the loop's own facing, so the projection keeps it
        // counter-clockwise and the triangles come back wound the same way.
        var normal = SIMD3<Double>.zero
        for i in points.indices {
            let p = points[i], q = points[(i + 1) % points.count]
            normal += SIMD3((p.y - q.y) * (p.z + q.z), (p.z - q.z) * (p.x + q.x), (p.x - q.x) * (p.y + q.y))
        }
        if simd_length(normal) > 1e-12 {
            let n = simd_normalize(normal)
            let helper: SIMD3<Double> = abs(n.x) < 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0)
            let u = simd_normalize(simd_cross(helper, n)), v = simd_cross(n, u)
            let flat = points.map { CapTriangulation.Point(simd_dot($0, u), simd_dot($0, v)) }
            var lookup: [CapTriangulation.Point: UInt32] = [:]
            for (i, p) in flat.enumerated() { lookup[p] = loop[i] }
            if lookup.count == loop.count, CapTriangulation.signedArea(flat) > 0, isSimple(flat) {
                let triangles = CapTriangulation.triangulate([flat])
                let mapped = triangles.compactMap { t -> [UInt32]? in
                    guard let a = lookup[t.0], let b = lookup[t.1], let c = lookup[t.2] else { return nil }
                    return [a, b, c]
                }
                if mapped.count == triangles.count, mapped.count == loop.count - 2 {
                    return (mapped.flatMap { $0 }, [])
                }
            }
        }

        // Fallback: a fan from the centre, following the loop's direction.
        let centre = points.reduce(.zero, +) / Double(points.count)
        var fan: [UInt32] = []
        for i in loop.indices { fan += [loop[i], loop[(i + 1) % loop.count], nextVertex] }
        return (fan, [SIMD3<Float>(centre)])
    }

    /// Whether no two non-adjacent edges of the outline cross.
    private static func isSimple(_ polygon: [CapTriangulation.Point]) -> Bool {
        let n = polygon.count
        guard n > 3 else { return true }
        func crosses(_ a: CapTriangulation.Point, _ b: CapTriangulation.Point, _ c: CapTriangulation.Point, _ d: CapTriangulation.Point) -> Bool {
            let d1 = CapTriangulation.cross(c, d, a), d2 = CapTriangulation.cross(c, d, b)
            let d3 = CapTriangulation.cross(a, b, c), d4 = CapTriangulation.cross(a, b, d)
            return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0)) && d1 != 0 && d2 != 0 && d3 != 0 && d4 != 0
        }
        for i in 0..<n {
            for j in stride(from: i + 2, to: n, by: 1) where !(i == 0 && j == n - 1) {
                if crosses(polygon[i], polygon[(i + 1) % n], polygon[j], polygon[(j + 1) % n]) { return false }
            }
        }
        return true
    }
}
