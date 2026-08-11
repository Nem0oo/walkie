import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: WalkieViewModel
    @State private var exportItem: ExportItem?

    var body: some View {
        Group {
            if viewModel.messages.isEmpty {
                Text("Aucun message reçu pour l'instant.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List(viewModel.messages) { message in
                    Button {
                        viewModel.replay(message)
                    } label: {
                        HStack {
                            // Tapping again while this row is playing stops it — the icon
                            // doubles as the app's only stop/pause affordance.
                            Image(systemName: viewModel.playingMessageID == message.id ? "stop.circle.fill" : "play.circle")
                            VStack(alignment: .leading) {
                                Text(message.sender)
                                    .font(.headline)
                                Text(Self.formatted(message.createdAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    .swipeActions(edge: .trailing) {
                        // Garder ce message en souvenir en dehors de l'app — Fichiers,
                        // AirDrop, Messages, etc. via la feuille de partage standard.
                        // Note : `ShareLink` placé directement dans `.swipeActions` ne
                        // déclenche rien sur certaines versions d'iOS (le bouton
                        // s'affiche mais l'action ne part jamais) — on présente donc
                        // `UIActivityViewController` nous-mêmes via `.sheet`, qui ne
                        // dépend pas de ce contexte de présentation fragile.
                        Button {
                            exportItem = ExportItem(url: MessageHistoryStore.shared.exportURL(for: message))
                        } label: {
                            Label("Exporter", systemImage: "square.and.arrow.up")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .leading) {
                        Button(role: .destructive) {
                            viewModel.delete(message)
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Historique")
        .sheet(item: $exportItem) { item in
            ActivityView(activityItems: [item.url])
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter
    }()

    private static func formatted(_ isoString: String) -> String {
        guard let date = isoFormatter.date(from: isoString) else { return isoString }
        return displayFormatter.string(from: date)
    }
}

private struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
