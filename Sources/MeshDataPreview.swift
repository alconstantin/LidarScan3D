import SceneKit
import UIKit
import simd

// Kept out of Sources/Geometry so that the geometry compiles, and is tested,
// without UIKit. This is the only part of MeshData that needs a UI framework.
extension MeshData {
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
}
