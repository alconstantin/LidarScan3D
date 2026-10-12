import XCTest
import simd
@testable import Geometry

final class LayFlatTests: XCTestCase {
    private func leaning(_ mesh: MeshData) -> MeshData {
        mesh.rotated(by: simd_quatf(angle: 17 * .pi / 180, axis: SIMD3(0, 1, 0))
                     * simd_quatf(angle: 23 * .pi / 180, axis: SIMD3(1, 0, 0)))
    }

    private func laidFlat(_ mesh: MeshData, face: Int = 0) throws -> MeshData {
        let faces = mesh.flatFaces()
        XCTAssertGreaterThan(faces.count, face)
        let chosen = try XCTUnwrap(faces.dropFirst(face).first)
        return mesh.rotated(by: chosen.rotation(for: mesh))
    }

    /// Quarter turns cannot undo an arbitrary lean; laying a face flat can.
    func testLayingFlatRestoresALeaningCube() throws {
        let tilted = leaning(Solids.cube(side: 40))
        XCTAssertGreaterThan(tilted.sizeMM.z, 50)
        let flat = try laidFlat(tilted)
        XCTAssertEqual(flat.sizeMM.x, 40, accuracy: 0.05)
        XCTAssertEqual(flat.sizeMM.y, 40, accuracy: 0.05)
        XCTAssertEqual(flat.sizeMM.z, 40, accuracy: 0.05)
        let resting = flat.vertices.filter { $0.z < 0.01 }.count
        XCTAssertEqual(resting, 4, "a whole face, not an edge or corner, touches the bed")
    }

    func testEveryCubeFaceIsOffered() {
        let faces = Solids.cube(side: 20).flatFaces(limit: 10)
        XCTAssertEqual(faces.count, 6)
        for face in faces { XCTAssertEqual(face.contactAreaMM2, 400, accuracy: 0.5) }
    }

    /// The broadest side goes down first: a lying slab, not one standing on edge.
    func testLargestFaceComesFirst() throws {
        let b = Solids.box(SIMD3(-30, -10, 0), SIMD3(30, 10, 6))
        let slab = MeshData.seated(vertices: b.vertices, indices: b.indices)
        let standing = leaning(slab.rotated(by: MeshData.quarterTurn(about: SIMD3(1, 0, 0), clockwise: true)))
        let faces = standing.flatFaces()
        XCTAssertEqual(faces.first?.contactAreaMM2 ?? 0, 60 * 20, accuracy: 1)
        let flat = try laidFlat(standing)
        XCTAssertEqual(flat.sizeMM.z, 6, accuracy: 0.05)
        XCTAssertEqual(max(flat.sizeMM.x, flat.sizeMM.y), 60, accuracy: 0.05, "the footprint is squared to X and Y")
        XCTAssertEqual(min(flat.sizeMM.x, flat.sizeMM.y), 20, accuracy: 0.05)
    }

    func testOtherFacesCanBeChosen() throws {
        let b = Solids.box(SIMD3(-30, -10, 0), SIMD3(30, 10, 6))
        let slab = MeshData.seated(vertices: b.vertices, indices: b.indices)
        let onSide = try laidFlat(slab, face: 2)
        XCTAssertEqual(onSide.sizeMM.z, 20, accuracy: 0.05, "the third face is one of the 60 × 6 sides")
    }

    /// A round model has no base to find; tiny facets must not be offered as one.
    func testCurvedModelsOfferNoFace() {
        XCTAssertTrue(Solids.sphere(radius: 30).flatFaces().isEmpty)
    }

    /// Only the outermost plane counts: a pocket's floor faces the same way as the base
    /// but laying it down would put the rest of the model through the bed.
    func testRecessedFacesDoNotCount() {
        let legs = Solids.twoLegged()
        let down = legs.flatFaces(limit: 10).first { $0.normal.z < -0.99 }
        XCTAssertEqual(down?.contactAreaMM2 ?? 0, 2 * 3 * 8, accuracy: 0.5, "both feet, nothing between them")
        let inner = legs.flatFaces(limit: 10).filter { abs($0.normal.x) > 0.99 }
        for face in inner { XCTAssertEqual(face.contactAreaMM2, 20 * 8, accuracy: 0.5, "only the outer leg sides") }
    }

    /// A lean is saved as an ordinary rotation, so it persists like a quarter turn.
    func testLaidFlatRotationIsAValidRecipe() throws {
        let tilted = leaning(Solids.cube(side: 30))
        let face = try XCTUnwrap(tilted.flatFaces().first)
        let recipe = Preparation(rotation: face.rotation(for: tilted).vector)
        XCTAssertTrue(recipe.isValid)
        XCTAssertEqual(tilted.rotated(by: recipe.quaternion).sizeMM.z, 30, accuracy: 0.05)
    }

    /// Noise of a fraction of a millimetre on a scanned base must not hide it.
    func testSlightlyNoisyBaseIsStillFound() throws {
        let b = Solids.box(SIMD3(-20, -20, 0), SIMD3(20, 20, 10))
        var vertices = b.vertices
        vertices[0].z += 0.2
        vertices[2].z -= 0.15
        let noisy = leaning(MeshData.seated(vertices: vertices, indices: b.indices))
        let flat = try laidFlat(noisy)
        XCTAssertEqual(flat.sizeMM.z, 10, accuracy: 0.5)
    }
}
