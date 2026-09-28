import SwiftUI
import RealityKit

/// Apple's guided capture UI (camera, LiDAR bounding box, coverage dial) plus our controls.
struct CaptureView: View {
    @Environment(AppModel.self) private var model
    let session: ObjectCaptureSession

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

                controls
            }
            .padding()
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
                    captureLog.notice("tapped Start capture, state=\(session.state.label, privacy: .public)")
                    session.startCapturing()
                    captureLog.notice("startCapturing returned, state=\(session.state.label, privacy: .public)")
                }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)

        case .capturing:
            if session.userCompletedScanPass {
                VStack(spacing: 10) {
                    Text("Scan pass complete!").font(.headline)
                    if isFlippable {
                        Button("Flip object & scan the bottom") { beginPass(flipped: true) }
                            .buttonStyle(.bordered)
                    } else {
                        Text("This object is too plain or symmetric to match up after a flip. Scan it again from another height instead.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                    }
                    Button("Scan again from another height") { beginPass(flipped: false) }
                        .buttonStyle(.bordered)
                    Button("Finish & build model") { session.finish() }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            } else {
                hint("Walk slowly around the object and keep it in frame.")
                Button("Finish early") { session.finish() }
                    .buttonStyle(.bordered)
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

    /// Both calls are documented as valid only mid-capture, and neither can report a
    /// misuse except by failing. The first tap moves the session on (a flip all the way
    /// back to `.ready`) before SwiftUI has redrawn the button, so a second tap on the
    /// same frame would land in a state the call does not accept.
    private func beginPass(flipped: Bool) {
        guard isCapturing, session.userCompletedScanPass else {
            captureLog.notice("ignored new pass (flipped=\(flipped, privacy: .public)), state=\(session.state.label, privacy: .public)")
            return
        }
        captureLog.notice("begin new pass, flipped=\(flipped, privacy: .public)")
        if flipped {
            session.beginNewScanPassAfterFlip()
        } else {
            session.beginNewScanPass()
        }
        captureLog.notice("new pass begun, state=\(session.state.label, privacy: .public)")
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
        if feedback.contains(.outOfFieldOfView) { return "Keep the object in view" }
        return nil
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
