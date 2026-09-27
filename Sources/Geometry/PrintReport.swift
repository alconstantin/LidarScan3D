import Foundation
import simd

/// Whether a mesh will slice cleanly: a closed surface uses every edge exactly
/// twice, once in each direction, and encloses a positive volume. The same checks
/// tools/check_stl.py runs on an exported file.
struct PrintReport: Sendable, Equatable {
    /// Edges used by one triangle only: the rims of holes.
    var holeEdges = 0
    /// Edges shared by three or more triangles: surfaces passing through each other.
    var nonManifoldEdges = 0
    /// Edges two neighbours traverse the same way: one of them faces inwards.
    var flippedEdges = 0
    /// Triangles with two corners at the same point.
    var degenerateTriangles = 0
    var volumeMM3: Double = 0

    var isWatertight: Bool {
        holeEdges == 0 && nonManifoldEdges == 0 && flippedEdges == 0
            && degenerateTriangles == 0 && volumeMM3 > 0
    }
}

extension MeshData {
    /// Vertices are compared by position at micron precision rather than by index,
    /// so a mesh that was never welded is judged by its shape, not its bookkeeping.
    func printReport() -> PrintReport {
        var ids: [VertexKey: UInt32] = [:]
        ids.reserveCapacity(vertices.count)
        let canonical = vertices.map { v -> UInt32 in
            let key = VertexKey(v)
            if let existing = ids[key] { return existing }
            let id = UInt32(ids.count)
            ids[key] = id
            return id
        }

        var report = PrintReport()
        var undirected: [UInt64: UInt32] = [:]
        var directed: [UInt64: UInt32] = [:]
        undirected.reserveCapacity(indices.count)
        directed.reserveCapacity(indices.count)

        func count(_ a: UInt32, _ b: UInt32) {
            undirected[UInt64(min(a, b)) << 32 | UInt64(max(a, b)), default: 0] += 1
            directed[UInt64(a) << 32 | UInt64(b), default: 0] += 1
        }

        for t in 0..<triangleCount {
            let i = (Int(indices[t * 3]), Int(indices[t * 3 + 1]), Int(indices[t * 3 + 2]))
            let v = (canonical[i.0], canonical[i.1], canonical[i.2])
            guard v.0 != v.1, v.1 != v.2, v.0 != v.2 else {
                report.degenerateTriangles += 1
                continue
            }
            count(v.0, v.1)
            count(v.1, v.2)
            count(v.2, v.0)
            let p = vertices[i.0], q = vertices[i.1], r = vertices[i.2]
            report.volumeMM3 += Double(simd_dot(p, simd_cross(q, r))) / 6
        }

        for uses in undirected.values {
            if uses == 1 { report.holeEdges += 1 } else if uses > 2 { report.nonManifoldEdges += 1 }
        }
        for uses in directed.values where uses > 1 {
            report.flippedEdges += 1
        }
        return report
    }
}
