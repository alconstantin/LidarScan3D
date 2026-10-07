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
            if t.isMultiple(of: 1024), Task.isCancelled { return SCNGeometry() }
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


extension MeshData {
    /// Overlays are separate nodes: highlighting never changes the export geometry.
    func problemNodes(report: PrintReport) -> [SCNNode] {
        var nodes: [SCNNode] = []
        if !report.problemEdges.isEmpty {
            let positions = SCNGeometrySource(vertices: vertices.map { SCNVector3($0.x, $0.y, $0.z) })
            let lines = report.problemEdges.flatMap { [$0.x, $0.y] }
            let geometry = SCNGeometry(sources: [positions], elements: [SCNGeometryElement(indices: lines, primitiveType: .line)])
            geometry.firstMaterial = Self.problemMaterial(.systemOrange)
            let node = SCNNode(geometry: geometry)
            node.name = "surfaceProblems"
            node.renderingOrder = 10
            nodes.append(node)
        }
        if !report.problemFaces.isEmpty {
            let positions = SCNGeometrySource(vertices: vertices.map { SCNVector3($0.x, $0.y, $0.z) })
            let faces = report.problemFaces.filter { $0 >= 0 && $0 < triangleCount }.flatMap { face in
                Array(indices[(face * 3)..<(face * 3 + 3)])
            }
            let geometry = SCNGeometry(sources: [positions], elements: [SCNGeometryElement(indices: faces, primitiveType: .triangles)])
            geometry.firstMaterial = Self.problemMaterial(.systemRed.withAlphaComponent(0.7))
            let node = SCNNode(geometry: geometry)
            node.name = "surfaceProblems"
            node.renderingOrder = 10
            nodes.append(node)
        }
        return nodes
    }

    private static func problemMaterial(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.readsFromDepthBuffer = false
        material.writesToDepthBuffer = false
        return material
    }
}
