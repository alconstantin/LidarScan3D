import Foundation

/// Capture problems reported by Object Capture, stored with the scan so the result
/// screen can explain why a model may need cleanup even after the camera has closed.
enum CaptureIssue: String, Codable, CaseIterable, Hashable, Sendable {
    case lowLight
    case movingTooFast
    case framing
    case tooClose
    case tooFar
    case objectNotDetected
    case overCapturing
    case notFlippable

    var title: String {
        switch self {
        case .lowLight: "More light needed"
        case .movingTooFast: "Camera moved too fast"
        case .framing: "Object left the frame"
        case .tooClose: "Camera was too close"
        case .tooFar: "Camera was too far"
        case .objectNotDetected: "Object was not detected"
        case .overCapturing: "Too many similar photos"
        case .notFlippable: "Bottom flip unavailable"
        }
    }

    var recommendation: String {
        switch self {
        case .lowLight: "Use bright, even light before scanning again."
        case .movingTooFast: "Walk one slow circle at a steady distance."
        case .framing: "Keep the whole object and its base in view."
        case .tooClose: "Step back slightly so LiDAR can see the full outline."
        case .tooFar: "Move closer until the object fills more of the capture box."
        case .objectNotDetected: "Reset and tighten the capture box around the object."
        case .overCapturing: "Change height or angle instead of repeating the same view."
        case .notFlippable: "For a symmetric object, scan another pass from a lower height."
        }
    }

    var symbol: String {
        switch self {
        case .lowLight: "sun.max.trianglebadge.exclamationmark"
        case .movingTooFast: "figure.walk.motion"
        case .framing: "viewfinder"
        case .tooClose, .tooFar: "arrow.left.and.right"
        case .objectNotDetected: "cube.transparent"
        case .overCapturing: "camera.badge.ellipsis"
        case .notFlippable: "arrow.triangle.2.circlepath"
        }
    }
}

/// A compact, persisted record of the capture conditions. It is deliberately advice,
/// not a verdict: Object Capture can still build a useful model after a warning.
struct ScanQuality: Codable, Sendable {
    var issueCounts: [CaptureIssue: Int] = [:]
    var shotCount = 0
    var passCount = 0

    mutating func record(_ issues: Set<CaptureIssue>) {
        for issue in issues { issueCounts[issue, default: 0] += 1 }
    }

    var notableIssues: [CaptureIssue] {
        issueCounts.keys.sorted { (issueCounts[$0] ?? 0) > (issueCounts[$1] ?? 0) }
    }

    var grade: String {
        // A symmetric cylinder legitimately cannot be flipped; that is capture advice,
        // not a quality defect by itself.
        let qualityIssues = notableIssues.filter { $0 != .notFlippable }
        if issueCounts[.objectNotDetected, default: 0] > 0 || issueCounts[.lowLight, default: 0] >= 3 {
            return "Needs attention"
        }
        return qualityIssues.isEmpty ? "Good" : "Usable with checks"
    }
}

/// One scan on disk: Documents/Scans/<name>/{Images, Checkpoints, Exports, model.usdz}.
/// The bundled sample has a plain model.obj instead of a textured USDZ.
struct ScanFolder: Identifiable, Hashable, Sendable {
    let url: URL

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var imagesURL: URL { url.appendingPathComponent("Images", isDirectory: true) }
    var checkpointsURL: URL { url.appendingPathComponent("Checkpoints", isDirectory: true) }
    var exportsURL: URL { url.appendingPathComponent("Exports", isDirectory: true) }
    private var qualityURL: URL { url.appendingPathComponent("capture-quality.json") }
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

    /// Older scans predate this file; they remain fully usable, just without capture notes.
    var quality: ScanQuality? {
        guard let data = try? Data(contentsOf: qualityURL) else { return nil }
        return try? JSONDecoder().decode(ScanQuality.self, from: data)
    }

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
            try? scan.delete()
        }
    }

    /// Permanently removes the scan's enclosing folder. That folder owns every piece
    /// of app-managed scan data: source photos, reconstruction checkpoints, model,
    /// exports and the capture-quality record. A successful remove leaves no scan
    /// artefacts in Documents/Scans.
    func delete() throws {
        try FileManager.default.removeItem(at: url)
    }

    func deleteCheckpoints() {
        try? FileManager.default.removeItem(at: checkpointsURL)
    }

    func saveQuality(_ quality: ScanQuality) {
        guard let data = try? JSONEncoder().encode(quality) else { return }
        try? data.write(to: qualityURL, options: .atomic)
    }
}
