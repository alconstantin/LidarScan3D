import SwiftUI

struct ReconstructionView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 64))
                .symbolEffect(.pulse)
            Text("Building your 3D model")
                .font(.title2.bold())
            ProgressView(value: model.progress)
            Text("\(Int(model.progress * 100))%  ·  \(model.progressStatus)")
                .font(.callout.monospacedDigit())
            Text("Keep the app open while it works. This usually takes a few minutes.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Cancel", role: .destructive) { model.cancelReconstruction() }
        }
        .padding(32)
    }
}
