import SwiftUI

@main
struct LidarScan3DApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.phase {
        case .home:
            HomeView()
        case .capturing(let session):
            CaptureView(session: session)
        case .reconstructing:
            ReconstructionView()
        case .result(let scan):
            NavigationStack {
                ResultView(scan: scan)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { model.goHome() }
                        }
                    }
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Something went wrong", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Back to start") { model.goHome() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
