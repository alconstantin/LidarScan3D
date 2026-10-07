import SwiftUI
import UIKit
import RealityKit
import AVFoundation

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
    /// Live capture conditions; persisted in the scan when the user finishes capture.
    var captureQuality = ScanQuality()

    @ObservationIgnored private var currentScan: ScanFolder?
    @ObservationIgnored private var userCancelledCapture = false
    @ObservationIgnored private var reconstruction = CancellationGate()
    var isCancelling = false
    var captureMessage: String?
    @ObservationIgnored private var isStartingCapture = false
    /// Holds the capture session for as long as it runs, so it has to be stopped by hand.
    @ObservationIgnored private var feedbackTask: Task<Void, Never>?

    /// Object Capture reports itself supported on some hardware that cannot feed it
    /// depth. Both have to hold, or capture starts and then quietly produces nothing.
    static var isSupported: Bool { ObjectCaptureSession.isSupported && DeviceCapability.hasSceneDepth }

    static var unsupportedReason: String? {
        if !ObjectCaptureSession.isSupported {
            return "This device does not support Object Capture. It needs an iPhone or iPad Pro with a LiDAR sensor, running iOS 17 or later."
        }
        if !DeviceCapability.hasSceneDepth {
            return "This device has no LiDAR depth sensor, which Object Capture needs to measure the object. Scanning would start but never capture anything. LiDAR is on the Pro iPhone models and the iPad Pro."
        }
        return nil
    }

    func goHome() {
        phase = .home
    }

    // MARK: Capture

    func startNewScan() {
        guard !isStartingCapture else { return }
        isStartingCapture = true
        Task {
            defer { isStartingCapture = false }
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            let allowed: Bool
            if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .video) }
            else { allowed = status == .authorized }
            guard allowed else {
                phase = .failed("Camera access is required. Open Settings → LiDAR Scan 3D and enable Camera, then try again.")
                return
            }
            beginNewScan()
        }
    }

    private func beginNewScan() {
        DeviceCapability.log()
        if let unsupportedReason = Self.unsupportedReason {
            phase = .failed(unsupportedReason)
            return
        }
        do {
            let scan = try ScanFolder.create()
            currentScan = scan
            userCancelledCapture = false
            captureQuality = ScanQuality()
            captureMessage = nil

            var configuration = ObjectCaptureSession.Configuration()
            configuration.checkpointDirectory = scan.checkpointsURL

            let session = ObjectCaptureSession()
            session.start(imagesDirectory: scan.imagesURL, configuration: configuration)
            captureLog.notice("session started, images=\(scan.imagesURL.lastPathComponent, privacy: .public)")
            phase = .capturing(session)
            observe(session)
            observeFeedback(session)
        } catch {
            phase = .failed("Could not create the scan folder: \(error.localizedDescription)")
        }
    }

    func cancelCapture(_ session: ObjectCaptureSession) {
        userCancelledCapture = true
        session.cancel()
    }

    func startCapturing(_ session: ObjectCaptureSession) {
        captureLog.notice("tapped Start capture, state=\(session.state.label, privacy: .public)")
        session.startCapturing()
        captureLog.notice("startCapturing returned, state=\(session.state.label, privacy: .public)")
    }

    /// Save the observations before `finish()` tears down the capture session. The
    /// count is guidance, not a score: a long scan naturally takes many photos.
    func finishCapture(_ session: ObjectCaptureSession, passCount: Int) {
        guard session.numberOfShotsTaken >= CaptureProgress.minimumPhotos else {
            captureMessage = "Capture at least \(CaptureProgress.minimumPhotos) photos from different angles before building a model."
            return
        }
        captureMessage = nil
        captureQuality.shotCount = max(captureQuality.shotCount, session.numberOfShotsTaken)
        captureQuality.passCount = max(captureQuality.passCount, passCount)
        currentScan?.saveQuality(captureQuality)
        session.finish()
    }

    private func observe(_ session: ObjectCaptureSession) {
        Task { [weak self] in
            for await state in session.stateUpdates {
                guard let self else { return }
                captureLog.notice("state -> \(state.label, privacy: .public)")
                switch state {
                case .completed:
                    // Leaving the capturing phase releases the capture session (and its memory)
                    // before reconstruction starts. The feedback loop holds it too, and a
                    // finished session stops sending feedback, so that loop would otherwise
                    // wait forever with the session in hand.
                    self.stopObservingFeedback()
                    if self.userCancelledCapture {
                        self.discardCurrentScan()
                        self.phase = .home
                    } else { self.startReconstruction() }
                    return
                case .failed(let error):
                    captureLog.error("capture failed: \(String(describing: error), privacy: .public)")
                    self.stopObservingFeedback()
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

    /// Feedback is the only signal that says why capture is not progressing.
    private func observeFeedback(_ session: ObjectCaptureSession) {
        feedbackTask?.cancel()
        feedbackTask = Task { [weak self] in
            for await feedback in session.feedbackUpdates {
                guard self != nil else { return }
                let names = feedback.map(\.label).sorted().joined(separator: ",")
                captureLog.notice("feedback -> [\(names, privacy: .public)]")
                self?.recordCaptureFeedback(feedback)
            }
        }
    }

    private func recordCaptureFeedback(_ feedback: Set<ObjectCaptureSession.Feedback>) {
        var issues = Set<CaptureIssue>()
        for item in feedback {
            switch item {
            case .environmentLowLight, .environmentTooDark:
                issues.insert(.lowLight)
            case .movingTooFast:
                issues.insert(.movingTooFast)
            case .outOfFieldOfView:
                issues.insert(.framing)
            case .objectTooClose:
                issues.insert(.tooClose)
            case .objectTooFar:
                issues.insert(.tooFar)
            case .objectNotDetected:
                issues.insert(.objectNotDetected)
            case .overCapturing:
                issues.insert(.overCapturing)
            case .objectNotFlippable:
                issues.insert(.notFlippable)
            @unknown default:
                break
            }
        }
        captureQuality.record(issues)
    }

    private func stopObservingFeedback() {
        feedbackTask?.cancel()
        feedbackTask = nil
    }

    // MARK: Reconstruction

    func cancelReconstruction() {
        isCancelling = true
        progressStatus = "Cancelling…"
        reconstruction.cancel()
    }

    func retryReconstruction(_ scan: ScanFolder) {
        guard case .home = phase else { return }
        guard scan.canRetry else {
            phase = .failed("This scan has too few saved photos to rebuild. Start a new scan, or delete it from Interrupted scans.")
            return
        }
        currentScan = scan
        startReconstruction()
    }

    private func startReconstruction() {
        guard let scan = currentScan else {
            phase = .home
            return
        }
        reconstruction = CancellationGate()
        let gate = reconstruction
        isCancelling = false
        phase = .reconstructing
        progress = 0
        progressStatus = "Preparing…"
        UIApplication.shared.isIdleTimerDisabled = true

        Task {
            defer {
                UIApplication.shared.isIdleTimerDisabled = false
                gate.clear()
                isCancelling = false
            }
            await reconstruct(scan, gate: gate)
        }
    }

    /// Runs off the main actor. Creating a PhotogrammetrySession walks the whole image
    /// directory and `process` enqueues against it, both slow enough to stall the UI
    /// for the entire time a scan is being prepared. Only the outcome comes back here.
    ///
    /// `nonisolated` is what moves it: a nonisolated async function runs on the
    /// cooperative pool rather than inheriting the caller's actor.
    private nonisolated func reconstruct(_ scan: ScanFolder, gate: CancellationGate) async {
        do {
            var configuration = PhotogrammetrySession.Configuration()
            configuration.checkpointDirectory = scan.checkpointsURL
            let session = try PhotogrammetrySession(input: scan.imagesURL, configuration: configuration)
            gate.attach { session.cancel() }
            guard !gate.isCancelled else { await finishCancelled(); return }
            try? FileManager.default.removeItem(at: scan.reconstructionURL)
            try session.process(requests: [.modelFile(url: scan.reconstructionURL)])

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
                    if gate.isCancelled { await finishCancelled(); return }
                    guard FileManager.default.fileExists(atPath: scan.reconstructionURL.path) else { throw MeshError.noGeometry }
                    try FileManager.default.moveItem(at: scan.reconstructionURL, to: scan.modelURL)
                    await finish(with: scan)
                    return
                default:
                    break
                }
            }
            // The stream is not documented to end without one of the two messages above,
            // but if it does the reconstruction screen would wait on it forever.
            await fail("Reconstruction stopped without producing a model.")
        } catch {
            if gate.isCancelled { await finishCancelled() }
            else { await fail("Reconstruction failed: \(error.localizedDescription). Your photos are saved; retry from Interrupted scans.") }
        }
    }

    private func report(progress fraction: Double) {
        guard !isCancelling else { return }
        progress = min(max(fraction, 0), 1)
        progressStatus = "Building 3D model…"
    }

    private func finish(with scan: ScanFolder) {
        // Checkpoints only exist to speed up a reconstruction; once the model is written
        // they are hundreds of megabytes of nothing.
        scan.deleteCheckpoints()
        currentScan = nil
        phase = .result(scan)
    }

    private func finishCancelled() {
        if let currentScan { try? FileManager.default.removeItem(at: currentScan.reconstructionURL) }
        currentScan = nil
        phase = .home
    }

    private func fail(_ message: String) {
        currentScan = nil
        phase = .failed(message)
    }

    private func discardCurrentScan() {
        if let currentScan { try? currentScan.delete() }
        currentScan = nil
    }
}
