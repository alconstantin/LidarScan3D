import Foundation
import simd

/// Triangulates the flat face that closes a plane cut: every closed rim loop the cut
/// left behind, with loops inside loops treated as holes.
///
/// A fan from each loop's centre, which this replaces, only covers a convex outline.
/// Scanned objects often meet the bed on something else: a bowl or vase on a foot ring
/// cuts into an outer and an inner loop, and a U- or C-shaped footprint puts its centre
/// outside the outline. Fans there overlap, cover the hole, and leave edges that a
/// slicer reads as non-manifold. Ear clipping with bridged holes covers exactly the
/// region between the loops, whatever its shape.
enum CapTriangulation {
    typealias Point = SIMD2<Double>

    /// Triangles covering the outer loops minus their holes, each wound
    /// counter-clockwise seen from +Z. The winding of the input loops does not matter:
    /// which loops are holes is decided by nesting, not by the direction they run in.
    static func triangulate(_ loops: [[Point]]) -> [(Point, Point, Point)] {
        var rings: [(points: [Point], area: Double)] = []
        for loop in loops where loop.count >= 3 {
            let area = signedArea(loop)
            if abs(area) > 1e-9 { rings.append((loop, area)) }
        }

        // Even nesting depth is solid, odd is a hole; an island inside a hole is solid again.
        let depth = rings.indices.map { i in
            rings.indices.filter { j in j != i && encloses(rings[j].points, rings[i].points[0]) }.count
        }

        var outers: [Int: (ring: [Point], holes: [[Point]])] = [:]
        for i in rings.indices where depth[i] % 2 == 0 {
            let ring = rings[i].area > 0 ? rings[i].points : Array(rings[i].points.reversed())
            outers[i] = (ring, [])
        }
        for i in rings.indices where depth[i] % 2 == 1 {
            // The hole belongs to the tightest solid loop around it.
            let parents = outers.keys.filter { encloses(rings[$0].points, rings[i].points[0]) }
            guard let parent = (parents.isEmpty ? Array(outers.keys) : parents)
                .min(by: { abs(rings[$0].area) < abs(rings[$1].area) }) else { continue }
            let hole = rings[i].area < 0 ? rings[i].points : Array(rings[i].points.reversed())
            outers[parent]?.holes.append(hole)
        }

        var triangles: [(Point, Point, Point)] = []
        for (ring, holes) in outers.values {
            var polygon = ring
            // Rightmost hole first, so later bridges never have to cross earlier ones.
            for hole in holes.sorted(by: { maxX($0) > maxX($1) }) {
                if let merged = bridge(polygon, hole) { polygon = merged }
            }
            earClip(polygon, into: &triangles)
        }
        return triangles
    }

    // MARK: Geometry

    /// Twice the signed area of triangle o, a, b: positive when it turns left.
    static func cross(_ o: Point, _ a: Point, _ b: Point) -> Double {
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }

    static func signedArea(_ polygon: [Point]) -> Double {
        var sum = 0.0
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    /// Even-odd point in polygon.
    private static func encloses(_ polygon: [Point], _ p: Point) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > p.y) != (b.y > p.y) {
                let x = a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y)
                if p.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    private static func maxX(_ polygon: [Point]) -> Double {
        polygon.reduce(-Double.infinity) { max($0, $1.x) }
    }

    /// Whether `q` lies inside the interior angle at vertex `k` of a counter-clockwise polygon.
    private static func interiorAngle(of polygon: [Point], at k: Int, contains q: Point) -> Bool {
        let n = polygon.count
        let prev = polygon[(k + n - 1) % n], a = polygon[k], next = polygon[(k + 1) % n]
        let leftOfOutgoing = cross(a, next, q) > 0
        let leftOfIncoming = cross(prev, a, q) > 0
        return cross(prev, a, next) >= 0
            ? leftOfOutgoing && leftOfIncoming
            : leftOfOutgoing || leftOfIncoming
    }

    // MARK: Holes

    /// Splices a clockwise hole into a counter-clockwise outline along a segment that
    /// both can see, giving one weakly simple polygon that walks out to the hole, around
    /// it, and back. (Eberly, "Triangulation by Ear Clipping", section 3.)
    private static func bridge(_ outer: [Point], _ hole: [Point]) -> [Point]? {
        guard let m = hole.indices.max(by: { hole[$0].x < hole[$1].x }) else { return nil }
        let mPoint = hole[m]
        let n = outer.count

        // Cast a ray from the hole's rightmost point along +X and find the first edge it hits.
        var hitX = Double.infinity
        var hitEdge: Int?
        for i in 0..<n {
            let a = outer[i], b = outer[(i + 1) % n]
            guard (a.y > mPoint.y) != (b.y > mPoint.y) else { continue }
            let x = a.x + (mPoint.y - a.y) * (b.x - a.x) / (b.y - a.y)
            if x >= mPoint.x, x < hitX {
                hitX = x
                hitEdge = i
            }
        }
        guard let edge = hitEdge else { return nil }

        let hit = Point(hitX, mPoint.y)
        var p = outer[edge].x > outer[(edge + 1) % n].x ? edge : (edge + 1) % n

        // The edge's far endpoint is visible unless a reflex vertex pokes into triangle
        // M, hit, P. If one does, the one closest in angle to the ray is visible instead.
        let triangle = cross(mPoint, hit, outer[p]) > 0 ? (mPoint, hit, outer[p]) : (mPoint, outer[p], hit)
        var best: (cosine: Double, distance: Double)?
        let candidate = outer[p]
        for k in 0..<n where k != p && outer[k] != candidate {
            let q = outer[k]
            guard cross(outer[(k + n - 1) % n], q, outer[(k + 1) % n]) <= 0,
                  cross(triangle.0, triangle.1, q) >= 0,
                  cross(triangle.1, triangle.2, q) >= 0,
                  cross(triangle.2, triangle.0, q) >= 0 else { continue }
            let d = simd_length(q - mPoint)
            guard d > 0 else { continue }
            let cosine = (q.x - mPoint.x) / d
            if best == nil || cosine > best!.cosine || (cosine == best!.cosine && d < best!.distance) {
                best = (cosine, d)
                p = k
            }
        }

        // An earlier bridge leaves its endpoint in the polygon twice. Take the copy whose
        // interior angle actually faces the hole, or the new bridge crosses the old one.
        if let facing = (0..<n).first(where: { outer[$0] == outer[p] && interiorAngle(of: outer, at: $0, contains: mPoint) }) {
            p = facing
        }

        return Array(outer[...p]) + Array(hole[m...]) + Array(hole[...m]) + Array(outer[p...])
    }

    // MARK: Ear clipping

    /// Appends the triangles of a counter-clockwise, weakly simple polygon.
    private static func earClip(_ polygon: [Point], into triangles: inout [(Point, Point, Point)]) {
        let n = polygon.count
        guard n >= 3 else { return }
        var prev = (0..<n).map { ($0 + n - 1) % n }
        var next = (0..<n).map { ($0 + 1) % n }
        var remaining = n

        /// Convex, with no other vertex in or on it. Vertices sharing a position with a
        /// corner are the two ends of a bridge and do not block.
        func isEar(_ i: Int, allowingFlat: Bool) -> Bool {
            let a = polygon[prev[i]], b = polygon[i], c = polygon[next[i]]
            let turn = cross(a, b, c)
            if turn < 0 || (turn == 0 && !allowingFlat) { return false }
            if turn == 0 { return true }
            var k = next[next[i]]
            while k != prev[i] {
                let v = polygon[k]
                if v != a, v != b, v != c,
                   cross(a, b, v) >= 0, cross(b, c, v) >= 0, cross(c, a, v) >= 0 {
                    return false
                }
                k = next[k]
            }
            return true
        }

        var i = 0
        var misses = 0
        // Real rims carry runs of collinear points. Those are only clipped, as
        // zero-area triangles, once no proper ear is left: they still need a
        // triangle to keep the cap closed.
        var allowingFlat = false
        while remaining > 3 {
            if isEar(i, allowingFlat: allowingFlat) {
                triangles.append((polygon[prev[i]], polygon[i], polygon[next[i]]))
                next[prev[i]] = next[i]
                prev[next[i]] = prev[i]
                remaining -= 1
                i = next[i]
                misses = 0
                allowingFlat = false
                continue
            }
            i = next[i]
            misses += 1
            guard misses >= remaining else { continue }
            if !allowingFlat {
                allowingFlat = true
                misses = 0
                continue
            }

            // A self-intersecting rim, from a scan that crosses itself, has no ear left
            // to find. Fan what remains so the cap still closes; the input was already
            // broken there and the slicer will say so.
            var rest: [Point] = []
            var k = i
            for _ in 0..<remaining {
                rest.append(polygon[k])
                k = next[k]
            }
            let centre = rest.reduce(Point.zero, +) / Double(rest.count)
            for j in rest.indices {
                triangles.append((rest[j], rest[(j + 1) % rest.count], centre))
            }
            return
        }
        triangles.append((polygon[prev[i]], polygon[i], polygon[next[i]]))
    }
}
