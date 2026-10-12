import Foundation
import simd

/// A flat region on the outside of a mesh that could rest on the print bed.
struct FlatFace: Sendable, Equatable {
    /// Outward unit normal in the coordinates of the mesh it was found on.
    let normal: SIMD3<Float>
    /// Area of the triangles lying in the resting plane, in mm².
    let contactAreaMM2: Float

    /// The absolute turn that puts this face down on the bed, with the footprint then
    /// squared to X and Y, for a mesh in the same coordinates the face was found in.
    func rotation(for mesh: MeshData) -> simd_quatf {
        let down = SIMD3<Float>(0, 0, -1)
        let tilt: simd_quatf
        if simd_dot(normal, down) < -0.9999 {
            // Facing straight up: any half turn about a horizontal axis puts it down.
            tilt = simd_quatf(angle: .pi, axis: SIMD3(1, 0, 0))
        } else {
            tilt = simd_quatf(from: normal, to: down)
        }
        let points = mesh.vertices.map { v -> SIMD2<Float> in
            let p = tilt.act(v)
            return SIMD2(p.x, p.y)
        }
        let heading = MeshData.squaringAngle(points)
        guard heading != 0 else { return tilt }
        return simd_quatf(angle: heading, axis: SIMD3(0, 0, 1)) * tilt
    }
}

extension MeshData {
    /// Flat outer faces the model could rest on, largest contact first.
    ///
    /// Quarter turns only reach axis-aligned sides, but a scan rarely comes out of
    /// Object Capture square to the world: a box can lean a few degrees, and a part
    /// can have its intended base at any angle. A face qualifies only when it lies in
    /// the extreme plane along its own normal, so the whole model sits on one side of
    /// it and laying it down cannot push anything through the bed. Triangles count
    /// toward contact within a small tolerance, because a scanned flat side is never
    /// exactly flat.
    ///
    /// Curved models have no face worth resting on and return an empty list rather
    /// than a handful of tiny facets.
    func flatFaces(limit: Int = 6) -> [FlatFace] {
        guard triangleCount > 0, limit > 0 else { return [] }
        var normals: [SIMD3<Float>] = []
        var areas: [Float] = []
        normals.reserveCapacity(triangleCount)
        areas.reserveCapacity(triangleCount)
        var totalArea: Float = 0
        for t in 0..<triangleCount {
            let a = vertices[Int(indices[3 * t])], b = vertices[Int(indices[3 * t + 1])], c = vertices[Int(indices[3 * t + 2])]
            let cross = simd_cross(b - a, c - a)
            let length = simd_length(cross)
            guard length.isFinite, length > 1e-9 else {
                normals.append(.zero)
                areas.append(0)
                continue
            }
            normals.append(cross / length)
            areas.append(length / 2)
            totalArea += length / 2
        }
        guard totalArea > 0 else { return [] }

        // Group triangles by roughly shared direction (about 4° per step) to find
        // directions worth testing. Contact is then measured across all triangles,
        // so a flat side split between neighbouring groups is still counted whole.
        struct DirectionKey: Hashable {
            let x: Int16, y: Int16, z: Int16
            init(_ n: SIMD3<Float>) {
                x = Int16((n.x * 14).rounded())
                y = Int16((n.y * 14).rounded())
                z = Int16((n.z * 14).rounded())
            }
        }
        var groups: [DirectionKey: SIMD3<Float>] = [:]
        for t in areas.indices where areas[t] > 0 {
            groups[DirectionKey(normals[t]), default: .zero] += normals[t] * areas[t]
        }
        let candidates = groups.values
            .filter { simd_length($0) > 0 }
            .sorted { simd_length($0) != simd_length($1) ? simd_length($0) > simd_length($1) : ($0.x, $0.y, $0.z) < ($1.x, $1.y, $1.z) }
            .prefix(32)
            .map { simd_normalize($0) }

        let tolerance = Swift.max(0.5, sizeMM.max() * 0.01)
        let alignment: Float = cos(10 * .pi / 180)

        /// The triangles lying in the outermost plane along `direction`, and the
        /// area-weighted normal they share.
        func contact(along direction: SIMD3<Float>) -> (area: Float, normal: SIMD3<Float>) {
            var extreme = -Float.infinity
            for v in vertices { extreme = Swift.max(extreme, simd_dot(v, direction)) }
            var area: Float = 0
            var sum = SIMD3<Float>.zero
            for t in areas.indices where areas[t] > 0 && simd_dot(normals[t], direction) >= alignment {
                let corners = (0..<3).map { vertices[Int(indices[3 * t + $0])] }
                guard corners.allSatisfy({ simd_dot($0, direction) >= extreme - tolerance }) else { continue }
                area += areas[t]
                sum += normals[t] * areas[t]
            }
            return (area, simd_length(sum) > 0 ? simd_normalize(sum) : direction)
        }

        // A single facet of a finely tessellated curve is not a base.
        let minimumArea = totalArea * 0.02
        var found: [FlatFace] = []
        for direction in candidates {
            // One refinement: re-measure along the normal the contact actually has,
            // so a slightly noisy face is laid down by its average, not its first guess.
            let first = contact(along: direction)
            guard first.area >= minimumArea else { continue }
            let refined = contact(along: first.normal)
            let face = refined.area >= first.area
                ? FlatFace(normal: first.normal, contactAreaMM2: refined.area)
                : FlatFace(normal: direction, contactAreaMM2: first.area)
            if let duplicate = found.firstIndex(where: { simd_dot($0.normal, face.normal) > cos(5 * .pi / 180) }) {
                if face.contactAreaMM2 > found[duplicate].contactAreaMM2 { found[duplicate] = face }
            } else {
                found.append(face)
            }
        }
        return Array(found.sorted { $0.contactAreaMM2 > $1.contactAreaMM2 }.prefix(limit))
    }
}
