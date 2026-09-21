import SwiftUI
// SceneKit predates Sendable. A scene is built on one thread and handed over
// once, never touched from two at a time, so its warnings do not apply here.
@preconcurrency import SceneKit
import UIKit
import simd

/// 3D preview, real-world dimensions, orientation, scaling, flat base and STL/OBJ/USDZ export.
struct ResultView: View {
    let scan: ScanFolder

    @State private var texturedScene: SCNScene?
    @State private var generatedScene: SCNScene?
    @State private var mesh: MeshData?          // exactly as loaded, never re-derived
    @State private var oriented: MeshData?      // mesh after the current orientation
    @State private var flat: MeshData?          // oriented after the base cut
    @State private var orientation = MeshData.noRotation
    @State private var isReoriented = false
    @State private var errorMessage: String?
    @State private var scalePercent: Double = 100
    @State private var flatBase = false
    @State private var trimFraction: Double = 0
    @State private var isPreparing = false
    /// Bumped by every rebuild; a task whose stamp is stale drops its result.
    @State private var rebuildGeneration = 0
    @State private var isExporting = false
    @State private var shareItem: ShareItem?
    @State private var showingCalibration = false
    @State private var calibrationText = ""

    private enum Format { case stl, obj }

    /// The slider's range. Calibration clamps to it too, so the readout and the
    /// control can never disagree.
    private static let scaleRange: ClosedRange<Double> = 10...500

    private static let xAxis = SIMD3<Float>(1, 0, 0)
    private static let yAxis = SIMD3<Float>(0, 1, 0)

    /// What the size readout and the exporters work from.
    ///
    /// This must never go nil once a mesh has loaded. The controls live behind it, so
    /// returning nil while a cut is still being computed would tear the toggle that
    /// started the cut out of the view tree, losing the very callback that finishes it.
    /// Until the cut lands, the mesh it is being cut from stands in for it.
    private var activeMesh: MeshData? {
        if flatBase, let flat { return flat }
        return oriented ?? mesh
    }

    /// The textured USDZ cannot show a turn or a cut, so anything that changes the
    /// geometry switches the preview to the mesh actually being exported.
    private var showsGeneratedPreview: Bool { flatBase || isReoriented }

    /// Falls back rather than blanking: an empty preview reads as a hang.
    private var previewScene: SCNScene? {
        showsGeneratedPreview ? (generatedScene ?? texturedScene) : texturedScene
    }

    private var trimMM: Float {
        Float(trimFraction) * (oriented?.sizeMM.z ?? 0)
    }

    var body: some View {
        List {
            Section {
                if let scene = previewScene {
                    SceneView(scene: scene, options: [.allowsCameraControl, .autoenablesDefaultLighting])
                        .frame(height: 320)
                        .id(ObjectIdentifier(scene))
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 320)
                }
            }
            .listRowInsets(EdgeInsets())

            if let activeMesh {
                Section {
                    let size = activeMesh.sizeMM * Float(scalePercent / 100)
                    LabeledContent("Size (X × Y × Z)", value: "\(mm(size.x)) × \(mm(size.y)) × \(mm(size.z)) mm")
                    LabeledContent("Triangles", value: activeMesh.triangleCount.formatted())
                    VStack(alignment: .leading) {
                        Text("Scale: \(Int(scalePercent.rounded())) %")
                        Slider(value: $scalePercent, in: Self.scaleRange, step: 1)
                    }
                    Button("Match real size…") {
                        calibrationText = ""
                        showingCalibration = true
                    }
                } header: {
                    Text("Print size")
                } footer: {
                    Text("LiDAR gives true scale, usually within a few mm. For an exact fit, measure the object's longest side with a ruler or calipers and tap Match real size.")
                }

                Section {
                    HStack {
                        turnButton("Tip back", "arrow.up", axis: Self.xAxis, clockwise: true)
                        turnButton("Tip forward", "arrow.down", axis: Self.xAxis, clockwise: false)
                        turnButton("Tip left", "arrow.left", axis: Self.yAxis, clockwise: true)
                        turnButton("Tip right", "arrow.right", axis: Self.yAxis, clockwise: false)
                    }
                    if isReoriented {
                        Button("Reset orientation") {
                            orientation = MeshData.noRotation
                            isReoriented = false
                            rebuild()
                        }
                    }
                } header: {
                    Text("Orientation")
                } footer: {
                    Text("Quarter turns, which between them reach every side. The flat base is cut from whichever side faces the bed, so turn the model until the side you want to print on is down. The grey bed in the preview shows how the model sits: a scan that leans touches it on one side and lifts off on the other.")
                }

                Section {
                    // The rebuild rides the binding rather than onChange: the handler runs
                    // from the tap itself, so it cannot be lost if this row is rebuilt.
                    Toggle("Flat base", isOn: Binding(
                        get: { flatBase },
                        set: { isOn in
                            flatBase = isOn
                            if isOn, trimFraction == 0 { trimFraction = 0.02 }
                            rebuild()
                        }
                    ))

                    if flatBase {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Trim from bottom: \(mm(trimMM)) mm")
                                if isPreparing {
                                    Spacer()
                                    ProgressView().controlSize(.small)
                                }
                            }
                            // Held as a fraction of height, so a quarter turn onto a
                            // different side cannot leave the trim out of range.
                            Slider(value: $trimFraction, in: 0...0.2, step: 0.005) { editing in
                                if !editing { rebuild() }
                            }
                        }
                    }
                } header: {
                    Text("Print preparation")
                } footer: {
                    Text(flatBase
                         ? "Slices the bottom off at the chosen height and caps it with a flat face, so the model sits solidly on the bed. Raise the trim until the ragged underside of the scan is gone. Measurements above already account for it."
                         : "Scans usually reconstruct a rough, uneven underside. A flat base cuts it off so the print adheres to the bed and stands straight.")
                }

                Section("Export") {
                    Button { export(.stl) } label: {
                        Label("Export STL (for your slicer)", systemImage: "printer")
                    }
                    Button { export(.obj) } label: {
                        Label("Export OBJ", systemImage: "cube")
                    }
                    Button { shareItem = ShareItem(url: scan.modelURL) } label: {
                        Label("Share USDZ (textured, for AR/viewing)", systemImage: "arkit")
                    }
                }
                .disabled(isExporting || isPreparing)
            } else if errorMessage == nil {
                Section { ProgressView("Reading mesh…") }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle(scan.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $shareItem) { ActivityView(url: $0.url) }
        .overlay {
            if isExporting {
                ProgressView("Exporting…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("Real longest side (mm)", isPresented: $showingCalibration) {
            TextField("e.g. 85", text: $calibrationText)
                .keyboardType(.decimalPad)
            Button("Apply") { applyCalibration() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let activeMesh {
                Text("The scan's longest side is currently \(mm(activeMesh.longestSideMM)) mm at 100 %.")
            }
        }
    }

    private func turnButton(_ title: String, _ symbol: String, axis: SIMD3<Float>, clockwise: Bool) -> some View {
        Button {
            orientation = MeshData.quarterTurn(about: axis, clockwise: clockwise) * orientation
            isReoriented = true
            rebuild()
        } label: {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(title)
    }

    private func load() async {
        guard mesh == nil else { return }
        let url = scan.modelURL
        // Parsing a textured USDZ is seconds of work on a real scan, and SCNScene(url:)
        // does all of it synchronously on whatever thread asks.
        texturedScene = await Task.detached {
            guard let loaded = try? SCNScene(url: url, options: nil) else { return nil }
            loaded.background.contents = UIColor.secondarySystemBackground
            return loaded
        }.value
        do {
            let loaded = try await Task.detached { try MeshData.load(from: url) }.value
            mesh = loaded
            oriented = loaded
        } catch {
            errorMessage = "Could not read the model: \(error.localizedDescription)"
        }
    }

    /// Re-derives the oriented mesh, the cut mesh and the preview from the untouched
    /// original. Turning and trimming both come through here, so neither accumulates
    /// rounding error across repeated taps — only the quaternion accumulates.
    private func rebuild() {
        guard let mesh else { return }
        isPreparing = true
        rebuildGeneration += 1
        let generation = rebuildGeneration
        let rotation = orientation
        let fraction = flatBase ? Float(trimFraction) : 0

        Task {
            // The scene is built here too, not after the hop back. makeGeometry walks
            // every triangle to accumulate normals and then packs two vertex-sized
            // arrays, which on a scan-scale mesh is the most expensive step of the lot.
            let result = await Task.detached { () -> (MeshData, MeshData?, SCNScene) in
                let oriented = mesh.rotated(by: rotation)
                guard fraction > 0 else { return (oriented, nil, Self.makeScene(for: oriented)) }
                let cut = oriented.flatBase(trimMM: oriented.sizeMM.z * fraction)
                return (oriented, cut, Self.makeScene(for: cut))
            }.value

            // Turns are cheap but a cut on a large scan is not, so two quick taps can
            // finish out of order. Only the newest rebuild may publish, or the mesh on
            // screen and in the export stops matching the accumulated orientation.
            guard generation == rebuildGeneration else { return }
            oriented = result.0
            flat = result.1
            generatedScene = result.2
            isPreparing = false
        }
    }

    private nonisolated static func makeScene(for mesh: MeshData) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.secondarySystemBackground

        // The mesh is Z-up and rests on Z = 0; SceneKit is Y-up. Rotating -90° about X
        // stands it upright, then it drops by half its height to sit around the origin.
        let node = SCNNode(geometry: mesh.makeGeometry())
        node.eulerAngles.x = -.pi / 2
        node.position = SCNVector3(0, -mesh.sizeMM.z / 2, 0)
        scene.rootNode.addChildNode(node)

        // Something to judge the base against by eye, which beats guessing at the lean
        // from a plane fit through a surface that is rough by definition.
        let span = CGFloat(max(mesh.sizeMM.x, mesh.sizeMM.y) * 1.8)
        let bed = SCNPlane(width: span, height: span)
        bed.firstMaterial?.diffuse.contents = UIColor.tertiarySystemFill
        bed.firstMaterial?.isDoubleSided = true
        let bedNode = SCNNode(geometry: bed)
        bedNode.eulerAngles.x = -.pi / 2
        bedNode.position = SCNVector3(0, -mesh.sizeMM.z / 2, 0)
        scene.rootNode.addChildNode(bedNode)

        // Units are millimetres, so the default camera clips badly without help.
        let longest = max(mesh.sizeMM.max(), 1)
        let camera = SCNCamera()
        camera.zNear = 0.5
        camera.zFar = Double(longest) * 20
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, longest * 0.4, longest * 2.2)
        scene.rootNode.addChildNode(cameraNode)

        return scene
    }

    private func applyCalibration() {
        guard let activeMesh,
              let real = Double(calibrationText.replacingOccurrences(of: ",", with: ".")),
              real > 0, activeMesh.longestSideMM > 0 else { return }
        let percent = real / Double(activeMesh.longestSideMM) * 100
        scalePercent = min(max(percent, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
    }

    private func export(_ format: Format) {
        guard let mesh = activeMesh else { return }
        isExporting = true
        errorMessage = nil
        let scale = Float(scalePercent / 100)
        // The trim goes in the name: without it, two different cuts collide. The
        // orientation cannot be named usefully, so uniqueURL catches what is left.
        let suffix = flatBase ? String(format: " flat %.1fmm", Double(trimMM)) : ""
        let baseName = "\(scan.name) \(Int(scalePercent.rounded()))pct\(suffix)"
        let exportsURL = scan.exportsURL

        Task {
            do {
                let url = try await Task.detached { () throws -> URL in
                    switch format {
                    case .stl:
                        let url = Self.uniqueURL(in: exportsURL, name: baseName, ext: "stl")
                        try mesh.writeBinarySTL(to: url, scale: scale)
                        return url
                    case .obj:
                        let url = Self.uniqueURL(in: exportsURL, name: baseName, ext: "obj")
                        try mesh.writeOBJ(to: url, scale: scale)
                        return url
                    }
                }.value
                shareItem = ShareItem(url: url)
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
            isExporting = false
        }
    }

    /// `name.ext`, or `name (2).ext` if that is taken. An export is minutes of the
    /// user's time; silently replacing an earlier one loses work that cannot be undone.
    private nonisolated static func uniqueURL(in directory: URL, name: String, ext: String) -> URL {
        let candidate = directory.appendingPathComponent(name).appendingPathExtension(ext)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
        for n in 2... {
            let next = directory.appendingPathComponent("\(name) (\(n))").appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: next.path) { return next }
        }
        return candidate
    }

    private func mm(_ value: Float) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

struct ShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Share sheet: AirDrop to a PC/Mac, save to Files, send to a slicer app, etc.
struct ActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
