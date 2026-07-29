import SwiftUI

@main
struct WalkieApp: App {
    @StateObject private var viewModel = WalkieViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(viewModel)
                .onAppear { viewModel.start() }
        }
        // Single-parameter form (not the iOS 17 two-parameter variant) — this app
        // targets iOS 16+.
        .onChange(of: scenePhase) { newPhase in
            viewModel.onScenePhaseChange(newPhase)
        }
    }
}
