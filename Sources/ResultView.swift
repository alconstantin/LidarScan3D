import SwiftUI
import SceneKit
import UIKit

/// 3D preview, real-world dimensions, scaling, flat base and STL/OBJ/USDZ export.
struct ResultView: View {
    let scan: ScanFolder

    @State private var texturedScene: SCNScene?
    @State private var flatScene: SCNScene?
    @State private var mesh: MeshData?
    @State private var flatMesh: MeshData?
    @State private var errorMessage: String?
    @State private var scalePercent: Double = 100
    @State private var flatBase = false
    @State private var trimMM: Double = 0
    @State private var isPreparing = false
    @State private var isExporting = false
    @State private var shareItem: ShareItem?
    @State private var showingCalibration = false
    @State private var calibrationText = ""

    private enum Format { case stl, obj }

    /// What the size readout and the exporters work from.
    private var activeMesh: MeshData? { flatBase ? flatMesh : mesh }

    var body: some View {
        List {
            Section {
                if let scene = flatBase ? flatScene : texturedScene {
                    SceneView(scene: scene, options: [.allowsCameraControl, .autoenablesDefaultLighting])
                        .frame(height: 320)
                        .id(flatBase)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 320)
                }
            }
            .listRowInsets(EdgeInsets())

            if let mesh, let activeMesh {
                Section {
                    let size = activeMesh.sizeMM * Float(scalePercent / 100)
                    LabeledContent("Size (X × Y × Z)", value: "\(mm(size.x)) × \(mm(size.y)) × \(mm(size.z)) mm")
                    LabeledContent("Triangles", value: activeMesh.triangleCount.formatted())
                    VStack(alignment: .leading) {
                        Text("Scale: \(Int(scalePercent.rounded())) %")
                        Slider(value: $scalePercent, in: 10...500, step: 1)
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
                    Toggle("Flat base", isOn: $flatBase)
                        .onChange(of: flatBase) { _, isOn in
                            if isOn, trimMM == 0 {
                                trimMM = Double(mesh.sizeMM.z) * 0.02
                            }
                            prepareFlatBase()
                        }

                    if flatBase {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Trim from bottom: \(mm(Float(trimMM))) mm")
                                if isPreparing {
                                    Spacer()
                                    ProgressView().controlSize(.small)
                                }
                            }
                            // A zero-height range would be an invalid slider, so keep a floor.
                            Slider(value: $trimMM, in: 0...max(Double(mesh.sizeMM.z) * 0.2, 0.1), step: 0.1) { editing in
                                if !editing { prepareFlatBase() }
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

    private func load() async {
        guard mesh == nil else { return }
        let url = scan.modelURL
        if let loaded = try? SCNScene(url: url, options: nil) {
            loaded.background.contents = UIColor.secondarySystemBackground
            texturedScene = loaded
        }
        do {
            mesh = try await Task.detached { try MeshData.load(from: url) }.value
        } catch {
            errorMessage = "Could not read the model: \(error.localizedDescription)"
        }
    }

    /// Recomputes the cut mesh and its preview. Cheap enough to run on release of the
    /// slider, expensive enough not to run on every tick of it.
    private func prepareFlatBase() {
        guard flatBase, let mesh else {
            flatMesh = nil
            flatScene = nil
            return
        }
        isPreparing = true
        let trim = Float(trimMM)
        Task {
            let cut = await Task.detached { mesh.flatBase(trimMM: trim) }.value
            flatMesh = cut
            flatScene = makeScene(for: cut)
            isPreparing = false
        }
    }

    private func makeScene(for mesh: MeshData) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.secondarySystemBackground

        let node = SCNNode(geometry: mesh.makeGeometry())
        // The mesh is Z-up and rests on Z = 0; SceneKit is Y-up. Rotating -90° about X
        // stands it upright, then it drops by half its height to sit around the origin.
        node.eulerAngles.x = -.pi / 2
        node.position = SCNVector3(0, -mesh.sizeMM.z / 2, 0)
        scene.rootNode.addChildNode(node)

        // Units are millimetres, so the default camera clips badly without help.
        let longest = max(mesh.sizeMM.max(), 1)
        let camera = SCNCamera()
        camera.zNear = 0.5
        camera.zFar = Double(longest) * 20
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, longest * 2.2)
        scene.rootNode.addChildNode(cameraNode)

        return scene
    }

    private func applyCalibration() {
        guard let activeMesh,
              let real = Double(calibrationText.replacingOccurrences(of: ",", with: ".")),
              real > 0, activeMesh.longestSideMM > 0 else { return }
        scalePercent = real / Double(activeMesh.longestSideMM) * 100
    }

    private func export(_ format: Format) {
        guard let mesh = activeMesh else { return }
        isExporting = true
        errorMessage = nil
        let scale = Float(scalePercent / 100)
        let suffix = flatBase ? " flat" : ""
        let baseURL = scan.exportsURL
            .appendingPathComponent("\(scan.name) \(Int(scalePercent.rounded()))pct\(suffix)")

        Task {
            do {
                let url = try await Task.detached { () throws -> URL in
                    switch format {
                    case .stl:
                        let url = baseURL.appendingPathExtension("stl")
                        try mesh.writeBinarySTL(to: url, scale: scale)
                        return url
                    case .obj:
                        let url = baseURL.appendingPathExtension("obj")
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
