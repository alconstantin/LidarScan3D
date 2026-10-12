import Foundation
import simd

/// Wall thickness measured by casting a ray inward from sampled triangles to the next
/// surface. Values are in the mesh's own millimetres, before the print scale.
///
/// A ray that leaves through a hole in an open scan measures nothing, and a ray into
/// an overlapping second shell measures the overlap rather than the real wall, so
/// this is a guide to where a print may fail, not a proof that it will not.
struct WallThickness: Sendable, Equatable {
    /// Sampled triangles whose ray found an opposite surface.
    var faces: [Int] = []
    var thicknessMM: [Float] = []
    var areasMM2: [Float] = []
    /// Area of every sampled triangle, measured or not.
    var sampledAreaMM2: Float = 0
    var sampledTriangles = 0
    var totalTriangles = 0
    var cancelled = false

    var isSampled: Bool { sampledTriangles < totalTriangles }
    var hasMeasurements: Bool { !faces.isEmpty }

    func thinnestMM(scale: Float) -> Float? { thicknessMM.min().map { $0 * scale } }

    /// Share of the checked surface thinner than `minimumMM` once printed at `scale`.
    func thinAreaFraction(below minimumMM: Float, scale: Float) -> Float {
        guard sampledAreaMM2 > 0, scale > 0 else { return 0 }
        var thin: Float = 0
        for i in thicknessMM.indices where thicknessMM[i] * scale < minimumMM { thin += areasMM2[i] }
        return thin / sampledAreaMM2
    }

    func thinFaces(below minimumMM: Float, scale: Float, limit: Int = 5000) -> [Int] {
        guard scale > 0 else { return [] }
        return Array(faces.indices.lazy.filter { thicknessMM[$0] * scale < minimumMM }.prefix(limit).map { faces[$0] })
    }
}

extension MeshData {
    /// Casts at most `maxSamples` rays, spread evenly over the triangle list.
    func wallThickness(maxSamples: Int = 20_000) -> WallThickness {
        var result = WallThickness()
        result.totalTriangles = triangleCount
        guard triangleCount > 0, maxSamples > 0 else { return result }
        let tree = TriangleTree(self)
        let stride = Swift.max(1, (triangleCount + maxSamples - 1) / maxSamples)
        // Starting just inside the surface keeps the ray off its own triangle and
        // neighbours that share its plane, without skipping any real wall.
        let offset: Float = 0.001
        var count = 0
        for t in Swift.stride(from: 0, to: triangleCount, by: stride) {
            count += 1
            if count.isMultiple(of: 512), Task.isCancelled {
                result.cancelled = true
                return result
            }
            let a = vertices[Int(indices[3 * t])], b = vertices[Int(indices[3 * t + 1])], c = vertices[Int(indices[3 * t + 2])]
            let cross = simd_cross(b - a, c - a)
            let length = simd_length(cross)
            guard length.isFinite, length > 1e-9 else { continue }
            let area = length / 2
            result.sampledTriangles += 1
            result.sampledAreaMM2 += area
            let direction = -cross / length
            let origin = (a + b + c) / 3 + direction * offset
            guard let distance = tree.nearestHit(from: origin, along: direction, skipping: t) else { continue }
            result.faces.append(t)
            result.thicknessMM.append(distance + offset)
            result.areasMM2.append(area)
        }
        return result
    }
}

/// A bounding-volume hierarchy for nearest ray hits.
private struct TriangleTree {
    struct Node {
        var lo: SIMD3<Float>, hi: SIMD3<Float>
        var left = -1, right = -1
        var first = 0, count = 0
    }
    let mesh: MeshData
    let order: [Int]
    let nodes: [Node]

    init(_ mesh: MeshData) {
        self.mesh = mesh
        var order = Array(0..<mesh.triangleCount)
        var nodes: [Node] = []
        var lo = [SIMD3<Float>](), hi = [SIMD3<Float>](), centre = [SIMD3<Float>]()
        for t in 0..<mesh.triangleCount {
            let a = mesh.vertices[Int(mesh.indices[3 * t])], b = mesh.vertices[Int(mesh.indices[3 * t + 1])], c = mesh.vertices[Int(mesh.indices[3 * t + 2])]
            lo.append(simd_min(a, simd_min(b, c)))
            hi.append(simd_max(a, simd_max(b, c)))
            centre.append((a + b + c) / 3)
        }
        func build(_ first: Int, _ count: Int) -> Int {
            var boxLo = lo[order[first]], boxHi = hi[order[first]]
            for i in first..<(first + count) {
                boxLo = simd_min(boxLo, lo[order[i]])
                boxHi = simd_max(boxHi, hi[order[i]])
            }
            let index = nodes.count
            nodes.append(Node(lo: boxLo, hi: boxHi, first: first, count: count))
            guard count > 4 else { return index }
            let span = boxHi - boxLo
            let axis = span.x >= span.y && span.x >= span.z ? 0 : (span.y >= span.z ? 1 : 2)
            order[first..<(first + count)].sort { centre[$0][axis] < centre[$1][axis] }
            let half = count / 2
            let left = build(first, half)
            let right = build(first + half, count - half)
            nodes[index].left = left
            nodes[index].right = right
            nodes[index].count = 0
            return index
        }
        if !order.isEmpty { _ = build(0, order.count) }
        self.order = order
        self.nodes = nodes
    }

    func nearestHit(from origin: SIMD3<Float>, along direction: SIMD3<Float>, skipping skipped: Int) -> Float? {
        guard !nodes.isEmpty else { return nil }
        let inverse = SIMD3<Float>(1 / direction.x, 1 / direction.y, 1 / direction.z)
        var best = Float.infinity
        var stack = [0]
        while let index = stack.popLast() {
            let node = nodes[index]
            guard let entry = Self.entry(origin, inverse, node.lo, node.hi), entry < best else { continue }
            if node.left < 0 {
                for i in node.first..<(node.first + node.count) where order[i] != skipped {
                    if let t = hit(order[i], origin, direction), t < best { best = t }
                }
            } else {
                stack.append(node.left)
                stack.append(node.right)
            }
        }
        return best.isFinite ? best : nil
    }

    /// Slab test; returns where the ray enters the box, or nil when it misses.
    private static func entry(_ origin: SIMD3<Float>, _ inverse: SIMD3<Float>, _ lo: SIMD3<Float>, _ hi: SIMD3<Float>) -> Float? {
        let t0 = (lo - origin) * inverse, t1 = (hi - origin) * inverse
        var enter: Float = 0, exit = Float.infinity
        // NaN from 0 × ∞ (a ray along a box face) is treated as "no constraint".
        for k in 0..<3 {
            let near = Swift.min(t0[k], t1[k]), far = Swift.max(t0[k], t1[k])
            if !near.isNaN { enter = Swift.max(enter, near) }
            if !far.isNaN { exit = Swift.min(exit, far) }
        }
        return enter <= exit ? enter : nil
    }

    /// Möller–Trumbore, either side of the triangle.
    private func hit(_ t: Int, _ origin: SIMD3<Float>, _ direction: SIMD3<Float>) -> Float? {
        let a = mesh.vertices[Int(mesh.indices[3 * t])], b = mesh.vertices[Int(mesh.indices[3 * t + 1])], c = mesh.vertices[Int(mesh.indices[3 * t + 2])]
        let e1 = b - a, e2 = c - a
        let p = simd_cross(direction, e2)
        let det = simd_dot(e1, p)
        guard abs(det) > 1e-12 else { return nil }
        let s = origin - a
        let u = simd_dot(s, p) / det
        guard u >= 0, u <= 1 else { return nil }
        let q = simd_cross(s, e1)
        let v = simd_dot(direction, q) / det
        guard v >= 0, u + v <= 1 else { return nil }
        let distance = simd_dot(e2, q) / det
        return distance > 0 ? distance : nil
    }
}
