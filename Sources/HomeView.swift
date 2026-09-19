import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var scans: [ScanFolder] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        model.startNewScan()
                    } label: {
                        Label("New Scan", systemImage: "viewfinder")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!AppModel.isSupported)

                    if !AppModel.isSupported {
                        Text("This device doesn't support Object Capture (it needs LiDAR and iOS 17 or later).")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("Tips for printable scans") {
                    tip("sun.max", "Bright, even, diffuse light. Avoid hard shadows.")
                    tip("hand.raised", "Matte, textured objects work best. Shiny, transparent or plain one-colour objects need a matte spray or powder.")
                    tip("square.dashed", "Put the object on a plain, non-reflective surface with free space all around it.")
                    tip("arrow.triangle.2.circlepath", "Walk slowly around it. Do the flip pass to capture the bottom.")
                    tip("ruler", "Objects from about mug size to chair size work best. Very small parts (under ~5 cm) lose detail.")
                }

                Section("Your scans") {
                    if scans.isEmpty {
                        Text("No scans yet").foregroundStyle(.secondary)
                    }
                    ForEach(scans) { scan in
                        NavigationLink(scan.name) { ResultView(scan: scan) }
                    }
                    .onDelete { offsets in
                        offsets.forEach { scans[$0].delete() }
                        scans.remove(atOffsets: offsets)
                    }
                }
            }
            .navigationTitle("LiDAR Scan 3D")
            .onAppear { scans = ScanFolder.all() }
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline)
    }
}
