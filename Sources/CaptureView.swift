import SwiftUI
import RealityKit

/// Apple's guided capture UI (camera, LiDAR bounding box, coverage dial) plus our controls.
struct CaptureView: View {
    @Environment(AppModel.self) private var model
    let session: ObjectCaptureSession
    /// Set while the session is paused for the user to turn the object over.
    @State private var isFlipping = false
    /// A complete slow circle at a new height is a meaningful unit of coverage. The
    /// count is preserved with the scan so the result can explain its confidence.
    @State private var captureProgressState = CaptureProgress()
    @State private var captureStatusUpdatedAt = Date.now
    @State private var isCaptureStalled = false
    private var scanPasses: Int { captureProgressState.passes }

    var body: some View {
        ZStack {
            ObjectCaptureView(session: session)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                HStack {
                    Button("Cancel") { model.cancelCapture(session) }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    Spacer()
                    if isCapturing {
                        Label("\(session.numberOfShotsTaken)", systemImage: "camera.fill")
                            .font(.callout.monospacedDigit())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }

                Spacer()

                if let feedbackMessage {
                    Text(feedbackMessage)
                        .font(.callout.weight(.semibold))
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }

                if isCapturing, !isFlipping {
                    captureProgress
                }

                if let message = model.captureMessage { hint(message) }
                controls
            }
            .padding()
        }
        .task {
            await monitorCaptureProgress()
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch session.state {
        case .ready:
            hint("Point the camera at your object, then tap Continue.")
            Button("Continue") { _ = session.startDetecting() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

        case .detecting:
            hint("Adjust the box so it tightly surrounds the object.")
            HStack {
                Button("Reset box") { _ = session.resetDetection() }
                    .buttonStyle(.bordered)
                Button("Start capture") {
                    captureProgressState.start(at: .now)
                    resetCaptureWatchdog()
                    model.startCapturing(session)
                }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)

        case .capturing:
            if isFlipping {
                VStack(spacing: 10) {
                    Text("Turn the object over").font(.headline)
                    Text("Lay it on a side you have not photographed yet, in the same spot, then tap Continue and fit the box around it again.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                    Button("Continue") { finishFlip() }
                        .buttonStyle(.borderedProminent)
                    Button("Back") { cancelFlip() }
                        .buttonStyle(.bordered)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            } else if session.userCompletedScanPass {
                VStack(spacing: 10) {
                    Text("Scan pass complete!").font(.headline)
                    if isFlippable {
                        Button("Flip object & scan the bottom") { startFlip() }
                            .buttonStyle(.bordered)
                    } else {
                        Text("This object is too plain or symmetric to match up after a flip. Scan it again from another height instead.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                    }
                    Button("Scan again from another height") { beginPass() }
                        .buttonStyle(.bordered)
                    Button("Finish & build model") { model.finishCapture(session, passCount: max(scanPasses, 1)) }
                        .buttonStyle(.borderedProminent)
                        .disabled(session.numberOfShotsTaken < CaptureProgress.minimumPhotos)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 8) {
                    hint("Walk slowly around the object and keep it in frame.")
                    if isFlippable {
                        Button("Flip object & scan the bottom") { startFlip() }
                            .buttonStyle(.bordered)
                        Text("For the best alignment, make one steady circle before flipping. You can still flip manually if the coverage dial stalls.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Apple cannot reliably align a flipped pass for this plain or symmetric object. Scan another low pass from the same side instead.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    Button("Finish early") { model.finishCapture(session, passCount: max(scanPasses, 1)) }
                        .buttonStyle(.bordered)
                        .disabled(session.numberOfShotsTaken < CaptureProgress.minimumPhotos)
                    if session.numberOfShotsTaken < CaptureProgress.minimumPhotos {
                        Text("Capture at least \(CaptureProgress.minimumPhotos) photos; 60 or more from varied angles usually gives better detail.")
                            .font(.footnote).multilineTextAlignment(.center)
                    }
                }
            }

        case .finishing:
            ProgressView("Saving photos…")
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

        case .failed(let error):
            // Previously this fell into a bare spinner, which is exactly what a hang
            // looks like. A stalled session should say so.
            VStack(spacing: 10) {
                Label("Capture failed", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(error.localizedDescription)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                Button("Back to start") { model.goHome() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

        default:
            VStack(spacing: 8) {
                ProgressView()
                Text(session.state.label)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    /// Apple raises this when it does not expect to stitch a flipped pass to the first
    /// one (a plain or symmetric object), and its own sample steers away from the flip then.
    private var isFlippable: Bool {
        !session.feedback.contains(.objectNotFlippable)
    }

    /// A new pass from the same side is valid straight from `.capturing`. The first tap
    /// resets the pass before SwiftUI has redrawn the button, so a second tap on the same
    /// frame is dropped rather than calling into a session that has moved on.
    private func beginPass() {
        guard isCapturing, session.userCompletedScanPass else {
            captureLog.notice("ignored new pass, state=\(session.state.label, privacy: .public)")
            return
        }
        captureLog.notice("begin new pass")
        session.beginNewScanPass()
        captureProgressState.newPass(at: .now)
        resetCaptureWatchdog()
    }

    /// A flipped pass is valid from a session paused mid-capture; it does not need to
    /// wait for Apple's coverage dial. Calling `beginNewScanPassAfterFlip()` while
    /// still capturing traps, so pause first and only resume after the object is turned.
    private func startFlip() {
        guard isCapturing, !isFlipping else { return }
        captureLog.notice("pausing for flip")
        session.pause()
        isFlipping = true
    }

    private func finishFlip() {
        guard isFlipping, isCapturing, session.isPaused else {
            captureLog.notice("ignored flip, state=\(session.state.label, privacy: .public) paused=\(session.isPaused, privacy: .public)")
            isFlipping = false
            return
        }
        isFlipping = false
        session.beginNewScanPassAfterFlip()
        captureProgressState.newPass(at: .now)
        // The flip sends the session back to `.ready` for a new box. Apple's sample
        // resumes once its flip sheet closes; without it detection would stay paused.
        if session.isPaused { session.resume() }
        resetCaptureWatchdog()
        captureLog.notice("flip pass begun, state=\(session.state.label, privacy: .public)")
    }

    private func cancelFlip() {
        isFlipping = false
        if session.isPaused { session.resume() }
    }

    private var isCapturing: Bool {
        if case .capturing = session.state { return true }
        return false
    }

    private var feedbackMessage: String? {
        let feedback = session.feedback
        if feedback.contains(.objectTooClose) { return "Move farther away" }
        if feedback.contains(.objectTooFar) { return "Move closer" }
        if feedback.contains(.movingTooFast) { return "Slow down" }
        if feedback.contains(.environmentTooDark) { return "Too dark: add more light" }
        if feedback.contains(.environmentLowLight) { return "Low light: more light helps" }
        if #available(iOS 17.4, *), feedback.contains(.objectNotDetected) { return "Object not detected: adjust the capture box and try a clearer angle" }
        if feedback.contains(.outOfFieldOfView) { return "Keep the object in view" }
        return nil
    }

    private var captureProgress: some View {
        VStack(spacing: 4) {
            Text("Pass \(max(scanPasses, 1)) · make one slow, complete circle")
                .font(.callout.weight(.semibold))
            Label(captureActivityText, systemImage: "camera.fill")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(isCaptureStalled ? .orange : .secondary)
            Text("Change height for the next pass. Apple’s coverage ring decides when this pass is complete.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if isCaptureStalled {
                Label(session.numberOfShotsTaken == 0
                      ? "No photos captured yet. Add light, check the box and distance, and move slowly to a new angle. Cancel and try again if capture does not start."
                      : "No new photo for \(lastPhotoAge) seconds. Move to a fresh angle. Finish early is available after \(CaptureProgress.minimumPhotos) photos.", systemImage: "pause.circle")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.orange)
            }
            if let issue = model.captureQuality.notableIssues.first {
                Label(issue.recommendation, systemImage: issue.symbol)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var lastPhotoAge: Int {
        max(0, Int(captureStatusUpdatedAt.timeIntervalSince(captureProgressState.lastPhotoAt)))
    }

    private var captureActivityText: String {
        let noun = session.numberOfShotsTaken == 1 ? "photo" : "photos"
        return "\(session.numberOfShotsTaken) \(noun) · last photo \(lastPhotoAge)s ago"
    }

    private func resetCaptureWatchdog() {
        captureProgressState.update(shots: session.numberOfShotsTaken, at: .now, paused: true)
        captureStatusUpdatedAt = .now
        isCaptureStalled = false
    }

    @MainActor
    private func monitorCaptureProgress() async {
        resetCaptureWatchdog()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            captureStatusUpdatedAt = .now
            let paused = !isCapturing || session.isPaused || isFlipping || session.userCompletedScanPass
            captureProgressState.update(shots: session.numberOfShotsTaken, at: .now, paused: paused)
            isCaptureStalled = !paused && captureProgressState.isStalled(at: .now)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
