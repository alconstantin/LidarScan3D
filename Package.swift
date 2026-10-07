// swift-tools-version: 5.9
import PackageDescription

// Builds geometry and scan storage — the platform-neutral half of the app — so the
// print-critical mesh code can be tested on macOS in CI. The iOS app is built from
// project.yml by XcodeGen and compiles the same files; this package adds no target
// to it. Nothing under Sources/Geometry may import UIKit.
let package = Package(
    name: "LidarScan3DGeometry",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "Geometry", path: "Sources",
                exclude: ["AppModel.swift", "CaptureView.swift", "Diagnostics.swift", "HomeView.swift",
                          "LidarScan3DApp.swift", "MeshDataPreview.swift", "ReconstructionView.swift",
                          "ResultView.swift", "ScanRow.swift", "Info.plist"], sources: ["Geometry", "ScanFolder.swift"]),
        .testTarget(name: "GeometryTests", dependencies: ["Geometry"], path: "Tests/GeometryTests"),
    ]
)
