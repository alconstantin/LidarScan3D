import Foundation
import simd
@testable import Geometry

/// The checks tools/check_stl.py runs on an exported file, applied straight to a mesh.
/// A closed surface uses every edge exactly twice, once in each direction, and encloses
/// a positive volume.
struct SurfaceReport {
    var boundaryEdges = 0    // used once: a hole
    var overUsedEdges = 0    // used 3+ times: non-manifold
    var flippedEdges = 0     // same direction twice: inconsistent winding
    var degenerateTriangles = 0
    var volumeMM3: Double = 0

    var isWatertight: Bool {
        boundaryEdges == 0 && overUsedEdges == 0 && flippedEdges == 0 && degenerateTriangles == 0 && volumeMM3 > 0
    }

    /// Welded at micron precision, matching what MeshData itself considers one vertex.
    init(_ mesh: MeshData) {
        struct Key: Hashable { let x, y, z: Int32 }
        func key(_ p: SIMD3<Float>) -> Key {
            Key(x: Int32((p.x * 1000).rounded()), y: Int32((p.y * 1000).rounded()), z: Int32((p.z * 1000).rounded()))
        }

        var ids: [Key: Int] = [:]
        var undirected: [UInt64: Int] = [:]
        var directed: [UInt64: Int] = [:]

        for t in 0..<mesh.triangleCount {
            let p = (0..<3).map { mesh.vertices[Int(mesh.indices[t * 3 + $0])] }
            let v = p.map { point -> Int in
                let k = key(point)
                if let existing = ids[k] { return existing }
                ids[k] = ids.count
                return ids.count - 1
            }
            guard Set(v).count == 3 else {
                degenerateTriangles += 1
                continue
            }
            for i in 0..<3 {
                let a = v[i], b = v[(i + 1) % 3]
                undirected[UInt64(min(a, b)) << 32 | UInt64(max(a, b)), default: 0] += 1
                directed[UInt64(a) << 32 | UInt64(b), default: 0] += 1
            }
            volumeMM3 += Double(simd_dot(p[0], simd_cross(p[1], p[2]))) / 6
        }

        boundaryEdges = undirected.values.count { $0 == 1 }
        overUsedEdges = undirected.values.count { $0 > 2 }
        flippedEdges = directed.values.count { $0 > 1 }
    }
}

private extension Collection {
    func count(where predicate: (Element) -> Bool) -> Int { reduce(0) { predicate($1) ? $0 + 1 : $0 } }
}
