import SwiftUI
import ImageIO
@preconcurrency import UIKit

/// Reads only a small cached image or one captured photo, never the full 3D model.
struct ScanRow: View {
    let scan: ScanFolder
    @State private var thumbnail: UIImage?
    @State private var title = ""

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFill() }
                else { Image(systemName: "cube").font(.title2).foregroundStyle(.secondary) }
            }
            .frame(width: 60, height: 60)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
            Text(title.isEmpty ? scan.url.lastPathComponent : title)
                .font(.headline)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
        .task {
            let task = Task.detached { (scan.name, Self.readThumbnail(scan)) }
            let result = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
            guard !Task.isCancelled else { return }
            title = result.0
            thumbnail = result.1
        }
    }

    private nonisolated static func readThumbnail(_ scan: ScanFolder) -> UIImage? {
        var url = scan.thumbnailURL
        if !FileManager.default.fileExists(atPath: url.path) {
            let files = (try? FileManager.default.contentsOfDirectory(at: scan.imagesURL, includingPropertiesForKeys: nil)) ?? []
            guard let photo = files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                .first(where: { ["heic", "jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }) else { return nil }
            url = photo
        }
        guard !Task.isCancelled, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 180,
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
