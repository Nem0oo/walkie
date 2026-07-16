import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: WalkieViewModel

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
                            Image(systemName: "play.circle")
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
                }
            }
        }
        .navigationTitle("Historique")
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
