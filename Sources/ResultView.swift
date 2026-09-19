import SwiftUI
import SceneKit
import UIKit

/// 3D preview, real-world dimensions, scaling and STL/OBJ/USDZ export.
struct ResultView: View {
    let scan: ScanFolder

    @State private var scene: SCNScene?
    @State private var mesh: MeshData?
    @State private var errorMessage: String?
    @State private var scalePercent: Double = 100
    @State private var isExporting = false
    @State private var shareItem: ShareItem?
    @State private var showingCalibration = false
    @State private var calibrationText = ""

    private enum Format { case stl, obj }

    var body: some View {
        List {
            Section {
                if let scene {
                    SceneView(scene: scene, options: [.allowsCameraControl, .autoenablesDefaultLighting])
                        .frame(height: 320)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 320)
                }
            }
            .listRowInsets(EdgeInsets())

            if let mesh {
                Section {
                    let size = mesh.sizeMM * Float(scalePercent / 100)
                    LabeledContent("Size (X × Y × Z)", value: "\(mm(size.x)) × \(mm(size.y)) × \(mm(size.z)) mm")
                    LabeledContent("Triangles", value: mesh.triangleCount.formatted())
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
                .disabled(isExporting)
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
            if let mesh {
                Text("The scan's longest side is currently \(mm(mesh.longestSideMM)) mm at 100 %.")
            }
        }
    }

    private func load() async {
        guard mesh == nil else { return }
        let url = scan.modelURL
        if let loaded = try? SCNScene(url: url, options: nil) {
            loaded.background.contents = UIColor.secondarySystemBackground
            scene = loaded
        }
        do {
            mesh = try await Task.detached { try MeshData.load(from: url) }.value
        } catch {
            errorMessage = "Could not read the model: \(error.localizedDescription)"
        }
    }

    private func applyCalibration() {
        guard let mesh,
              let real = Double(calibrationText.replacingOccurrences(of: ",", with: ".")),
              real > 0, mesh.longestSideMM > 0 else { return }
        scalePercent = real / Double(mesh.longestSideMM) * 100
    }

    private func export(_ format: Format) {
        guard let mesh else { return }
        isExporting = true
        errorMessage = nil
        let scale = Float(scalePercent / 100)
        let baseURL = scan.exportsURL.appendingPathComponent("\(scan.name) \(Int(scalePercent.rounded()))pct")

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
