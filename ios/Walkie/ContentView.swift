import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: WalkieViewModel

    var body: some View {
        VStack(spacing: 24) {
            Text(viewModel.connectionStatusText)
                .font(.headline)
                .foregroundStyle(viewModel.connectionState == .connected ? .green : .orange)

            if let code = viewModel.channelCode {
                Text(code)
                    .font(.system(.largeTitle, design: .monospaced))
                    .textSelection(.enabled)

                if let qrImage = viewModel.qrImage {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                }

                if let shareURL = viewModel.shareURL {
                    ShareLink(item: shareURL) {
                        Label("Partager le lien", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView("Configuration du canal…")
            }
        }
        .padding()
    }
}
