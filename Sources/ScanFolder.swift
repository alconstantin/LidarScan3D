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

    func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}
