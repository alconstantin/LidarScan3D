// swift-tools-version: 5.9
import PackageDescription

// Builds only Sources/Geometry — the platform-neutral half of the app — so the
// print-critical mesh code can be tested on macOS in CI. The iOS app is built from
// project.yml by XcodeGen and compiles the same files; this package adds no target
// to it. Nothing under Sources/Geometry may import UIKit.
let package = Package(
    name: "LidarScan3DGeometry",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "Geometry", path: "Sources/Geometry"),
        .testTarget(name: "GeometryTests", dependencies: ["Geometry"], path: "Tests/GeometryTests"),
    ]
)
