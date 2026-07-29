import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var viewModel: WalkieViewModel

    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("Accueil", systemImage: "antenna.radiowaves.left.and.right") }

            NavigationStack {
                HistoryView(viewModel: viewModel)
            }
            .tabItem { Label("Historique", systemImage: "clock.arrow.circlepath") }

            NavigationStack {
                SettingsView(viewModel: viewModel)
            }
            .tabItem { Label("Configuration", systemImage: "gearshape") }
        }
    }
}
