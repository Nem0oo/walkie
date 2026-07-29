import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: WalkieViewModel
    @State private var urlText: String = ""

    var body: some View {
        Form {
            Section {
                TextField("https://mon-serveur.fr", text: $urlText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Adresse du serveur")
            } footer: {
                Text("C'est l'adresse de ton propre backend Walkie auto-hébergé. Changer de serveur abandonne le canal actuel et en crée un nouveau sur ce serveur — l'historique déjà téléchargé est conservé.")
            }

            Section {
                Button("Enregistrer") {
                    viewModel.configureServer(urlText)
                }
                .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let lastError = viewModel.lastError {
                Section {
                    Text(lastError)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Configuration")
        .onAppear {
            urlText = viewModel.serverURLString ?? ""
        }
    }
}
