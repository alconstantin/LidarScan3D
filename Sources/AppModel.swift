import SwiftUI
import UIKit
import RealityKit

/// Drives the scan flow: capture (LiDAR-guided photos) -> on-device reconstruction -> result.
@MainActor
@Observable
final class AppModel {
    enum Phase {
        case home
        case capturing(ObjectCaptureSession)
        case reconstructing
        case result(ScanFolder)
        case failed(String)
    }

    var phase: Phase = .home
    var progress: Double = 0
    var progressStatus = ""

    @ObservationIgnored private var currentScan: ScanFolder?
    @ObservationIgnored private var userCancelledCapture = false
    @ObservationIgnored private var photogrammetrySession: PhotogrammetrySession?

    static var isSupported: Bool { ObjectCaptureSession.isSupported }

    func goHome() {
        phase = .home
    }

    // MARK: Capture

    func startNewScan() {
        guard ObjectCaptureSession.isSupported else {
            phase = .failed("This device does not support Object Capture. A LiDAR-equipped iPhone/iPad Pro with iOS 17 or later is required.")
            return
        }
        do {
            let scan = try ScanFolder.create()
            currentScan = scan
            userCancelledCapture = false

            var configuration = ObjectCaptureSession.Configuration()
            configuration.checkpointDirectory = scan.checkpointsURL

            let session = ObjectCaptureSession()
            session.start(imagesDirectory: scan.imagesURL, configuration: configuration)
            phase = .capturing(session)
            observe(session)
        } catch {
            phase = .failed("Could not create the scan folder: \(error.localizedDescription)")
        }
    }

    func cancelCapture(_ session: ObjectCaptureSession) {
        userCancelledCapture = true
        session.cancel()
    }

    private func observe(_ session: ObjectCaptureSession) {
        Task { [weak self] in
            for await state in session.stateUpdates {
                guard let self else { return }
                switch state {
                case .completed:
                    // Leaving the capturing phase releases the capture session (and its memory)
                    // before reconstruction starts.
                    self.startReconstruction()
                    return
                case .failed(let error):
                    if self.userCancelledCapture {
                        self.discardCurrentScan()
                        self.phase = .home
                    } else {
                        self.phase = .failed("Capture failed: \(error.localizedDescription)")
                    }
                    return
                default:
                    break
                }
            }
        }
    }

    // MARK: Reconstruction

    func cancelReconstruction() {
        photogrammetrySession?.cancel()
    }

    private func startReconstruction() {
        guard let scan = currentScan else {
            phase = .home
            return
        }
        phase = .reconstructing
        progress = 0
        progressStatus = "Preparing…"
        UIApplication.shared.isIdleTimerDisabled = true

        Task {
            defer {
                UIApplication.shared.isIdleTimerDisabled = false
                photogrammetrySession = nil
            }
            do {
                var configuration = PhotogrammetrySession.Configuration()
                configuration.checkpointDirectory = scan.checkpointsURL
                let session = try PhotogrammetrySession(input: scan.imagesURL, configuration: configuration)
                photogrammetrySession = session
                try session.process(requests: [.modelFile(url: scan.modelURL)])

                for try await output in session.outputs {
                    switch output {
                    case .requestProgress(_, let fraction):
                        progress = fraction
                        progressStatus = "Building 3D model…"
                    case .requestError(_, let error):
                        throw error
                    case .processingCancelled:
                        discardCurrentScan()
                        phase = .home
                        return
                    case .processingComplete:
                        phase = .result(scan)
                        return
                    default:
                        break
                    }
                }
            } catch {
                phase = .failed("Reconstruction failed: \(error.localizedDescription)")
            }
        }
    }

    private func discardCurrentScan() {
        currentScan?.delete()
        currentScan = nil
    }
}
