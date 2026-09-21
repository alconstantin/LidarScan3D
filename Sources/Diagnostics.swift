import Foundation
import OSLog
// ObjectCaptureSession lives in the RealityKit/SwiftUI cross-import overlay, so it is
// only visible when both are imported.
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
