import Foundation
import simd

/// Surface checks, not a guarantee about wall thickness, supports or slicer behavior.
struct PrintReport: Sendable, Equatable {
    var holeEdges = 0
    var nonManifoldEdges = 0
    var flippedEdges = 0
    var degenerateTriangles = 0
    var volumeMM3: Double = 0
    var inwardShells = 0
    var intersectingTriangles = 0
    var intersectionCheckComplete = true

    var isWatertight: Bool {
        holeEdges == 0 && nonManifoldEdges == 0 && flippedEdges == 0
            && degenerateTriangles == 0 && volumeMM3 > 0 && inwardShells == 0
            && intersectingTriangles == 0 && intersectionCheckComplete
    }
}

extension MeshData {
    func printReport() -> PrintReport {
        var ids: [VertexKey: UInt32] = [:]
        let canonical = vertices.map { v -> UInt32 in
            let key = VertexKey(v)
            if let existing = ids[key] { return existing }
            let id = UInt32(ids.count)
            ids[key] = id
            return id
        }
        var report = PrintReport()
        var undirected: [UInt64: Int] = [:]
        var directed: [UInt64: Int] = [:]
        var edgeOwner: [UInt64: Int] = [:]
        var parent = Array(0..<triangleCount)
        var volumes = [Double](repeating: 0, count: triangleCount)
        var valid = [Bool](repeating: false, count: triangleCount)
        func root(_ value: Int) -> Int {
            var node = value
            while parent[node] != node {
                parent[node] = parent[parent[node]]
                node = parent[node]
            }
            return node
        }
        func count(_ a: UInt32, _ b: UInt32, face: Int) {
            let edge = UInt64(min(a, b)) << 32 | UInt64(max(a, b))
            undirected[edge, default: 0] += 1
            directed[UInt64(a) << 32 | UInt64(b), default: 0] += 1
            if let other = edgeOwner[edge] {
                let lhs = root(face), rhs = root(other)
                if lhs != rhs { parent[lhs] = rhs }
            } else { edgeOwner[edge] = face }
        }
        for t in 0..<triangleCount {
            if t.isMultiple(of: 1024), Task.isCancelled {
                report.intersectionCheckComplete = false
                return report
            }
            let i = (Int(indices[t * 3]), Int(indices[t * 3 + 1]), Int(indices[t * 3 + 2]))
            let v = (canonical[i.0], canonical[i.1], canonical[i.2])
            guard v.0 != v.1, v.1 != v.2, v.0 != v.2 else {
                report.degenerateTriangles += 1
                continue
            }
            valid[t] = true
            count(v.0, v.1, face: t)
            count(v.1, v.2, face: t)
            count(v.2, v.0, face: t)
            let p = SIMD3<Double>(vertices[i.0]), q = SIMD3<Double>(vertices[i.1]), r = SIMD3<Double>(vertices[i.2])
            volumes[t] = simd_dot(p, simd_cross(q, r)) / 6
            report.volumeMM3 += volumes[t]
        }
        var shellVolumes: [Int: Double] = [:]
        for t in 0..<triangleCount where valid[t] { shellVolumes[root(t), default: 0] += volumes[t] }
        // Separate negative shells need review: they may be intentional internal cavities.
        report.inwardShells = shellVolumes.values.filter { $0 <= 0 }.count
        report.holeEdges = undirected.values.filter { $0 == 1 }.count
        report.nonManifoldEdges = undirected.values.filter { $0 > 2 }.count
        report.flippedEdges = directed.values.filter { $0 > 1 }.count
        let intersections = MeshIntersections.check(self, canonical: canonical)
        report.intersectingTriangles = intersections.count
        report.intersectionCheckComplete = intersections.complete
        return report
    }
}

/// Bounding-volume hierarchy prunes spatially separate triangles. A bounded work
/// budget leaves an explicit incomplete verdict rather than freezing on pathological input.
private enum MeshIntersections {
    struct Face {
        let ids: SIMD3<UInt32>
        let a, b, c, lo, hi: SIMD3<Double>
        var centre: SIMD3<Double> { (lo + hi) / 2 }
    }
    struct Node {
        let lo, hi: SIMD3<Double>
        var left = -1
        var right = -1
        var faces: [Int] = []
    }
    static func check(_ mesh: MeshData, canonical: [UInt32]) -> (count: Int, complete: Bool) {
        var faces: [Face] = []
        for t in 0..<mesh.triangleCount {
            let ids = (0..<3).map { Int(mesh.indices[t * 3 + $0]) }
            let a = SIMD3<Double>(mesh.vertices[ids[0]])
            let b = SIMD3<Double>(mesh.vertices[ids[1]])
            let c = SIMD3<Double>(mesh.vertices[ids[2]])
            faces.append(Face(ids: SIMD3(canonical[ids[0]], canonical[ids[1]], canonical[ids[2]]),
                              a: a, b: b, c: c, lo: simd_min(a, simd_min(b, c)), hi: simd_max(a, simd_max(b, c))))
        }
        guard !faces.isEmpty else { return (0, true) }
        var nodes: [Node] = []
        func build(_ list: [Int]) -> Int {
            var lo = faces[list[0]].lo, hi = faces[list[0]].hi
            for i in list { lo = simd_min(lo, faces[i].lo); hi = simd_max(hi, faces[i].hi) }
            let index = nodes.count
            nodes.append(Node(lo: lo, hi: hi))
            if list.count <= 4 || Task.isCancelled { nodes[index].faces = list; return index }
            let span = hi - lo
            let axis = span.x >= span.y && span.x >= span.z ? 0 : (span.y >= span.z ? 1 : 2)
            let sorted = list.sorted { faces[$0].centre[axis] < faces[$1].centre[axis] }
            let middle = sorted.count / 2
            let left = build(Array(sorted[..<middle])), right = build(Array(sorted[middle...]))
            nodes[index].left = left
            nodes[index].right = right
            return index
        }
        _ = build(Array(faces.indices))
        var count = 0, work = 0
        var stack = [(0, 0)]
        let epsilon = 0.000001
        func overlaps(_ a: Node, _ b: Node) -> Bool {
            for k in 0..<3 where a.hi[k] < b.lo[k] - epsilon || b.hi[k] < a.lo[k] - epsilon { return false }
            return true
        }
        while let (i, j) = stack.popLast() {
            work += 1
            if Task.isCancelled || work > 2_000_000 { return (count, false) }
            let a = nodes[i], b = nodes[j]
            guard overlaps(a, b) else { continue }
            if a.left < 0 && b.left < 0 {
                for x in a.faces {
                    for y in b.faces where i != j || x < y {
                        let f = faces[x], g = faces[y]
                        if (0..<3).contains(where: { f.hi[$0] < g.lo[$0] - epsilon || g.hi[$0] < f.lo[$0] - epsilon }) { continue }
                        work += 1
                        if work > 2_000_000 { return (count, false) }
                        // Neighbours meet along an edge or vertex by design.
                        if (0..<3).contains(where: { k in (0..<3).contains { f.ids[k] == g.ids[$0] } }) { continue }
                        if intersects(f, g) {
                            count += 1
                            if count >= 100 { return (count, false) }
                        }
                    }
                }
            } else if i == j {
                stack.append((a.left, a.left)); stack.append((a.left, a.right)); stack.append((a.right, a.right))
            } else if b.left < 0 || (a.left >= 0 && simd_length_squared(a.hi - a.lo) >= simd_length_squared(b.hi - b.lo)) {
                stack.append((a.left, j)); stack.append((a.right, j))
            } else {
                stack.append((i, b.left)); stack.append((i, b.right))
            }
        }
        return (count, true)
    }
    /// Separating-axis test, including in-plane axes for coplanar triangles.
    private static func intersects(_ a: Face, _ b: Face) -> Bool {
        for k in 0..<3 where a.hi[k] < b.lo[k] - 1e-6 || b.hi[k] < a.lo[k] - 1e-6 { return false }
        let ae = [a.b - a.a, a.c - a.b, a.a - a.c]
        let be = [b.b - b.a, b.c - b.b, b.a - b.c]
        let an = simd_cross(ae[0], ae[1]), bn = simd_cross(be[0], be[1])
        guard simd_length_squared(an) > 1e-20, simd_length_squared(bn) > 1e-20 else { return false }
        var axes = [an, bn]
        for x in ae {
            axes.append(simd_cross(an, x))
            for y in be { axes.append(simd_cross(x, y)) }
        }
        for y in be { axes.append(simd_cross(bn, y)) }
        for axis in axes {
            let length = simd_length(axis)
            guard length > 1e-12 else { continue }
            let n = axis / length
            let av = [simd_dot(a.a, n), simd_dot(a.b, n), simd_dot(a.c, n)]
            let bv = [simd_dot(b.a, n), simd_dot(b.b, n), simd_dot(b.c, n)]
            if av.max()! < bv.min()! - 1e-6 || bv.max()! < av.min()! - 1e-6 { return false }
        }
        return true
    }
}
