import Foundation
import OSLog
// ObjectCaptureSession lives in the RealityKit/SwiftUI cross-import overlay, so it is
// only visible when both are imported.
import ARKit
import RealityKit
import SwiftUI

/// Capture goes through Apple's state machine, and when it stalls there is nothing on
/// screen to say where. These land in the unified log, readable in Console.app with the
/// device tethered and no debugger attached.
let captureLog = Logger(subsystem: "com.alconstantin.lidarscan3d", category: "capture")

extension ObjectCaptureSession.CaptureState {
    /// `failed` carries the error, which is the whole point of logging the state at all.
    var label: String {
        switch self {
        case .initializing: "initializing"
        case .ready: "ready"
        case .detecting: "detecting"
        case .capturing: "capturing"
        case .finishing: "finishing"
        case .completed: "completed"
        case .failed(let error): "failed(\(error.localizedDescription))"
        @unknown default: "unknown"
        }
    }
}

extension ObjectCaptureSession.Feedback {
    var label: String {
        switch self {
        case .objectTooClose: "objectTooClose"
        case .objectTooFar: "objectTooFar"
        case .movingTooFast: "movingTooFast"
        case .environmentLowLight: "environmentLowLight"
        case .environmentTooDark: "environmentTooDark"
        case .outOfFieldOfView: "outOfFieldOfView"
        case .objectNotFlippable: "objectNotFlippable"
        case .overCapturing: "overCapturing"
        case .objectNotDetected: "objectNotDetected"
        @unknown default: "unknown"
        }
    }
}

/// What the hardware can actually do. Object Capture needs LiDAR depth in every ARFrame;
/// without it the logs fill with "No depth map is available in ARFrame!" and the session
/// never produces a point cloud, however healthy the state machine looks.
enum DeviceCapability {
    static var hasSceneDepth: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    /// e.g. "iPhone16,1". Non-Pro iPhones carry a Dynamic Island but no LiDAR, so the
    /// exact model is the difference between "unsupported" and "broken".
    static var modelIdentifier: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }

    @MainActor
    static func log() {
        captureLog.notice("""
            device=\(modelIdentifier, privacy: .public) \
            iOS=\(UIDevice.current.systemVersion, privacy: .public) \
            objectCapture=\(ObjectCaptureSession.isSupported, privacy: .public) \
            sceneDepth=\(hasSceneDepth, privacy: .public)
            """)
    }
}
