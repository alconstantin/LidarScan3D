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
    @ObservationIgnored private let reconstruction = SessionBox()

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
        reconstruction.cancel()
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
                reconstruction.clear()
            }
            await reconstruct(scan)
        }
    }

    /// Runs off the main actor. Creating a PhotogrammetrySession walks the whole image
    /// directory and `process` enqueues against it, both slow enough to stall the UI
    /// for the entire time a scan is being prepared. Only the outcome comes back here.
    ///
    /// `nonisolated` is what moves it: a nonisolated async function runs on the
    /// cooperative pool rather than inheriting the caller's actor.
    private nonisolated func reconstruct(_ scan: ScanFolder) async {
        do {
            var configuration = PhotogrammetrySession.Configuration()
            configuration.checkpointDirectory = scan.checkpointsURL
            let session = try PhotogrammetrySession(input: scan.imagesURL, configuration: configuration)
            reconstruction.adopt(session)
            try session.process(requests: [.modelFile(url: scan.modelURL)])

            // The session itself never leaves this function; only Sendable outputs do.
            for try await output in session.outputs {
                switch output {
                case .requestProgress(_, let fraction):
                    await report(progress: fraction)
                case .requestError(_, let error):
                    throw error
                case .processingCancelled:
                    await finishCancelled()
                    return
                case .processingComplete:
                    await finish(with: scan)
                    return
                default:
                    break
                }
            }
        } catch {
            await fail("Reconstruction failed: \(error.localizedDescription)")
        }
    }

    private func report(progress fraction: Double) {
        progress = fraction
        progressStatus = "Building 3D model…"
    }

    private func finish(with scan: ScanFolder) {
        phase = .result(scan)
    }

    private func finishCancelled() {
        discardCurrentScan()
        phase = .home
    }

    private func fail(_ message: String) {
        phase = .failed(message)
    }

    private func discardCurrentScan() {
        currentScan?.delete()
        currentScan = nil
    }
}

/// Lets the main actor cancel a reconstruction that is running off it.
/// PhotogrammetrySession is not Sendable, so the reference is kept behind a lock and
/// never handed out — `cancel()` is the only thing reachable from another thread.
private final class SessionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var session: PhotogrammetrySession?

    func adopt(_ session: PhotogrammetrySession) {
        lock.withLock { self.session = session }
    }

    func cancel() {
        lock.withLock { session?.cancel() }
    }

    func clear() {
        lock.withLock { session = nil }
    }
}
