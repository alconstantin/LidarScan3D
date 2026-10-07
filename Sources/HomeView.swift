import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var scans: [ScanFolder] = []
    @State private var interrupted: [ScanFolder] = []
    @State private var path: [ScanFolder] = []
    @State private var sampleError: String?
    @State private var scanPendingDeletion: ScanFolder?
    @State private var deletionError: String?
    @State private var isDeleting = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button {
                        model.startNewScan()
                    } label: {
                        Text("New Scan")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            // Keep the call to action optically centred. A Label
                            // centres its icon and title as one group, making the
                            // title itself look shifted to the right.
                            .overlay(alignment: .leading) {
                                Image(systemName: "viewfinder")
                                    .padding(.leading, 16)
                            }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!AppModel.isSupported)

                    if let reason = AppModel.unsupportedReason {
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if !interrupted.isEmpty {
                    Section("Interrupted scans") {
                        ForEach(interrupted) { scan in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(scan.name).font(.headline)
                                Text("\(scan.imageCount) saved photos").font(.caption).foregroundStyle(.secondary)
                                if scan.canRetry {
                                    Button("Retry reconstruction") { model.retryReconstruction(scan) }
                                } else {
                                    Text("Too few photos to rebuild. Start a new scan.").font(.footnote)
                                }
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) { scanPendingDeletion = scan }
                            }
                        }
                    }
                }

                Section("Tips for printable scans") {
                    tip("sun.max", "Bright, even, diffuse light. Avoid hard shadows.")
                    tip("hand.raised", "Matte, textured objects work best. Shiny, transparent or plain one-colour objects need a matte spray or powder.")
                    tip("square.dashed", "Put the object on a plain, non-reflective surface with free space all around it.")
                    tip("arrow.triangle.2.circlepath", "Walk slowly around it. Do the flip pass to capture the bottom.")
                    tip("ruler", "Objects from about mug size to chair size work best. Very small parts (under ~5 cm) lose detail.")
                }

                Section {
                    if scans.isEmpty {
                        Text("No scans yet").foregroundStyle(.secondary)
                    }
                    ForEach(scans) { scan in
                        NavigationLink(scan.name, value: scan)
                            .swipeActions {
                                Button(role: .destructive) {
                                    scanPendingDeletion = scan
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                    .onDelete { offsets in
                        scanPendingDeletion = offsets.first.map { scans[$0] }
                    }
                    if !scans.contains(where: \.isSample) {
                        Button { openSample() } label: {
                            Label("Try the sample scan", systemImage: "cube")
                        }
                    }
                    if let sampleError {
                        Text(sampleError).font(.footnote).foregroundStyle(.red)
                    }
                    if let deletionError {
                        Text(deletionError).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Your scans")
                } footer: {
                    Text("The sample is a vase on a foot ring. Turn it, give it a flat base and export it on any iPhone, LiDAR or not.")
                }
                Section {
                    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
                    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
                    LabeledContent("App version", value: "\(version) (\(build))")
                }
            }
            .navigationTitle("LiDAR Scan 3D")
            .toolbar { EditButton() }
            .navigationDestination(for: ScanFolder.self) { scan in
                ResultView(scan: scan) { deletedScan in
                    // A result opened from this list is still inside this navigation
                    // stack. Remove it from both the visible list and the stack so a
                    // successful deletion returns here immediately.
                    scans.removeAll { $0 == deletedScan }
                    path.removeAll { $0 == deletedScan }
                }
            }
            // Listing the folder stats every scan on disk, which does not belong
            // on the main thread once a few dozen have piled up. Scans that never
            // produced a model are cleared out on the way.
            .task {
                let listing = await Task.detached { (ScanFolder.all(), ScanFolder.incomplete()) }.value
                scans = listing.0
                interrupted = listing.1
            }
            .confirmationDialog("Delete this scan?", isPresented: Binding(
                get: { scanPendingDeletion != nil },
                set: { if !$0 { scanPendingDeletion = nil } }
            ), titleVisibility: .visible) {
                Button("Delete scan", role: .destructive) { deletePendingScan() }
                Button("Cancel", role: .cancel) { scanPendingDeletion = nil }
            } message: {
                Text("This permanently deletes its photos, checkpoints, model, exports and capture notes from this iPhone.")
            }
            .overlay {
                if isDeleting {
                    ProgressView("Deleting scan…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func deletePendingScan() {
        guard let scan = scanPendingDeletion else { return }
        scanPendingDeletion = nil
        isDeleting = true
        deletionError = nil
        Task {
            do {
                try await Task.detached { try scan.delete() }.value
                scans.removeAll { $0 == scan }
                interrupted.removeAll { $0 == scan }
                path.removeAll { $0 == scan }
            } catch {
                deletionError = "Could not delete \(scan.name): \(error.localizedDescription)"
            }
            isDeleting = false
        }
    }

    private func openSample() {
        Task {
            do {
                let sample = try await Task.detached { try ScanFolder.installSample() }.value
                scans = await Task.detached { ScanFolder.all() }.value
                sampleError = nil
                path.append(sample)
            } catch {
                sampleError = "Could not open the sample: \(error.localizedDescription)"
            }
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline)
    }
}
