import Foundation

/// One scan on disk: Documents/Scans/<name>/{Images, Checkpoints, Exports, model.usdz}
struct ScanFolder: Identifiable, Hashable, Sendable {
    let url: URL

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var imagesURL: URL { url.appendingPathComponent("Images", isDirectory: true) }
    var checkpointsURL: URL { url.appendingPathComponent("Checkpoints", isDirectory: true) }
    var exportsURL: URL { url.appendingPathComponent("Exports", isDirectory: true) }
    var modelURL: URL { url.appendingPathComponent("model.usdz") }
    var hasModel: Bool { FileManager.default.fileExists(atPath: modelURL.path) }

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
