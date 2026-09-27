import Foundation

/// One scan on disk: Documents/Scans/<name>/{Images, Checkpoints, Exports, model.usdz}.
/// The bundled sample has a plain model.obj instead of a textured USDZ.
struct ScanFolder: Identifiable, Hashable, Sendable {
    let url: URL

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var imagesURL: URL { url.appendingPathComponent("Images", isDirectory: true) }
    var checkpointsURL: URL { url.appendingPathComponent("Checkpoints", isDirectory: true) }
    var exportsURL: URL { url.appendingPathComponent("Exports", isDirectory: true) }
    /// model.usdz for a real scan, and where reconstruction writes; model.obj for the sample.
    var modelURL: URL {
        let usdz = url.appendingPathComponent("model.usdz")
        let obj = url.appendingPathComponent("model.obj")
        if !FileManager.default.fileExists(atPath: usdz.path), FileManager.default.fileExists(atPath: obj.path) {
            return obj
        }
        return usdz
    }
    var hasModel: Bool { FileManager.default.fileExists(atPath: modelURL.path) }
    /// Only a real scan carries photographs of the object to share for viewing and AR.
    var isTextured: Bool { modelURL.pathExtension == "usdz" }
    var isSample: Bool { name == Self.sampleName }

    static let sampleName = "Sample vase"

    static var rootURL: URL {
        URL.documentsDirectory.appendingPathComponent("Scans", isDirectory: true)
    }

    static func create() throws -> ScanFolder {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let folder = ScanFolder(url: rootURL.appendingPathComponent("Scan \(formatter.string(from: Date()))", isDirectory: true))
        for directory in [folder.imagesURL, folder.checkpointsURL, folder.exportsURL] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return folder
    }

    /// Finished scans, newest first.
    static func all() -> [ScanFolder] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)) ?? []
        return urls
            .map(ScanFolder.init(url:))
            .filter(\.hasModel)
            .sorted { $0.name > $1.name }
    }

    /// Copies the bundled sample into the scans folder, where it behaves like any other
    /// scan: it can be turned, cut, exported and deleted, and installed again after.
    static func installSample() throws -> ScanFolder {
        guard let source = Bundle.main.url(forResource: "SampleVase", withExtension: "obj") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let folder = ScanFolder(url: rootURL.appendingPathComponent(sampleName, isDirectory: true))
        try FileManager.default.createDirectory(at: folder.exportsURL, withIntermediateDirectories: true)
        let model = folder.url.appendingPathComponent("model.obj")
        if !FileManager.default.fileExists(atPath: model.path) {
            try FileManager.default.copyItem(at: source, to: model)
        }
        return folder
    }

    /// Scans that never got a model: capture failed, reconstruction failed, or the app
    /// was killed part way. The app cannot resume them and does not list them, so their
    /// photos would otherwise fill the device unseen.
    ///
    /// Anything created in the last minute is left alone: a scan started the moment the
    /// home screen appeared has no model yet either, and must not be swept from under it.
    static func removeIncomplete() {
        let cutoff = Date().addingTimeInterval(-60)
        let urls = (try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.creationDateKey])) ?? []
        for scan in urls.map(ScanFolder.init(url:)) where !scan.hasModel {
            guard let created = try? scan.url.resourceValues(forKeys: [.creationDateKey]).creationDate,
                  created < cutoff else { continue }
            scan.delete()
        }
    }

    func delete() {
        try? FileManager.default.removeItem(at: url)
    }

    func deleteCheckpoints() {
        try? FileManager.default.removeItem(at: checkpointsURL)
    }
}
