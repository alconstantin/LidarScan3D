import Foundation
import simd
@testable import Geometry

/// Closed test solids with outward-facing windings, in the app's own convention
/// (millimetres, Z-up, seated on Z = 0).
enum Solids {
    static func sphere(radius r: Float, rings: Int = 40, segments: Int = 48) -> MeshData {
        var vertices: [SIMD3<Float>] = []
        for i in 0...rings {
            let phi = Float.pi * Float(i) / Float(rings)
            for j in 0..<segments {
                let theta = 2 * Float.pi * Float(j) / Float(segments)
                vertices.append(SIMD3(r * sin(phi) * cos(theta), r * sin(phi) * sin(theta), r * cos(phi)))
            }
        }
        func at(_ i: Int, _ j: Int) -> UInt32 { UInt32(i * segments + (j % segments)) }
        var indices: [UInt32] = []
        for i in 0..<rings {
            for j in 0..<segments {
                let a = at(i, j), b = at(i, j + 1), c = at(i + 1, j + 1), d = at(i + 1, j)
                if i != 0 { indices += [a, c, b] }
                if i != rings - 1 { indices += [a, d, c] }
            }
        }
        return MeshData.seated(vertices: vertices, indices: indices)
    }

    static func box(_ lo: SIMD3<Float>, _ hi: SIMD3<Float>) -> (vertices: [SIMD3<Float>], indices: [UInt32]) {
        ([SIMD3(lo.x, lo.y, lo.z), SIMD3(hi.x, lo.y, lo.z), SIMD3(hi.x, hi.y, lo.z), SIMD3(lo.x, hi.y, lo.z),
          SIMD3(lo.x, lo.y, hi.z), SIMD3(hi.x, lo.y, hi.z), SIMD3(hi.x, hi.y, hi.z), SIMD3(lo.x, hi.y, hi.z)],
         [0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7, 0, 1, 5, 0, 5, 4,
          1, 2, 6, 1, 6, 5, 2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7])
    }

    static func cube(side: Float) -> MeshData {
        let h = side / 2
        let b = box(SIMD3(-h, -h, -h), SIMD3(h, h, h))
        return MeshData.seated(vertices: b.vertices, indices: b.indices)
    }

    /// Two disconnected legs. A cut through both must cap them separately: one cap
    /// bridging the gap would show up as extra volume.
    static func twoLegged() -> MeshData {
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for leg in [box(SIMD3(-4, -4, 0), SIMD3(-1, 4, 20)), box(SIMD3(1, -4, 0), SIMD3(4, 4, 20))] {
            let base = UInt32(vertices.count)
            vertices += leg.vertices
            indices += leg.indices.map { $0 + base }
        }
        return MeshData.seated(vertices: vertices, indices: indices)
    }

    /// A sphere with a patch of triangles missing, standing in for the open, ragged
    /// underside a real scan reconstructs.
    static func holedSphere(radius r: Float, rings: Int = 40, segments: Int = 48, drop: Int = 6) -> MeshData {
        let full = sphere(radius: r, rings: rings, segments: segments)
        var indices: [UInt32] = []
        for t in 0..<full.triangleCount {
            let tri = (0..<3).map { full.indices[t * 3 + $0] }
            let ring = Int(tri[0]) / segments
            let column = Int(tri[0]) % segments
            if ring >= rings - 12, ring <= rings - 6, column < drop { continue }
            indices += tri
        }
        return MeshData.seated(vertices: full.vertices, indices: indices)
    }
}
