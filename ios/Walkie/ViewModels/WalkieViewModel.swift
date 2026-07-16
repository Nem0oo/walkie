import Combine
import Foundation
import SwiftUI

@MainActor
final class WalkieViewModel: ObservableObject {
    @Published private(set) var channelCode: String?
    @Published private(set) var connectionState: ConnectionState = .disconnected

    private let api = APIClient.shared
    private let store = PersistenceStore.shared
    private let webSocket = WebSocketClient()
    private let audio = AudioSessionManager()

    var shareURL: URL? {
        channelCode.flatMap { URL(string: "https://walkie.gcourtot.fr/send/\($0)") }
    }

    var qrImage: UIImage? {
        shareURL.flatMap { QRCodeGenerator.generate(from: $0.absoluteString) }
    }

    var connectionStatusText: String {
        switch connectionState {
        case .connected: return "Connecté"
        case .connecting: return "Connexion…"
        case .disconnected: return "Reconnexion en cours…"
        }
    }

    init() {
        audio.startKeepAlive()

        webSocket.onMessage = { [weak self] message in
            Task { @MainActor in await self?.handleIncoming(message) }
        }
        webSocket.$state
            .receive(on: DispatchQueue.main)
            .assign(to: &$connectionState)
    }

    func start() {
        Task {
            if let existingCode = store.channelCode {
                channelCode = existingCode
                webSocket.connect(code: existingCode)
                await catchUp()
            } else {
                await pair()
            }
        }
    }

    func onScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .active, channelCode != nil else { return }
        Task { await catchUp() }
    }

    // The app runs unattended in the background — a one-off failure here (cold-started
    // backend, transient DNS/network blip at first launch) must not strand the app on
    // "Configuration du canal…" forever. Retry with the same backoff shape as
    // WebSocketClient's reconnect (1s → 2s → ... → 30s cap) until it succeeds.
    private func pair() async {
        var backoff: TimeInterval = 1
        while channelCode == nil {
            do {
                let channel = try await api.createChannel()
                store.channelCode = channel.code
                channelCode = channel.code
                webSocket.connect(code: channel.code)
                return
            } catch {
                print("WalkieViewModel: pairing failed, retrying in \(backoff)s: \(error)")
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                backoff = min(backoff * 2, 30)
            }
        }
    }

    private func catchUp() async {
        guard let code = channelCode else { return }
        do {
            let messages = try await api.fetchMessages(code: code, since: store.lastSeenMessageId)
            for message in messages {
                await handleIncoming(message)
            }
        } catch {
            print("WalkieViewModel: catch-up failed: \(error)")
        }
    }

    private func handleIncoming(_ message: VoiceMessage) async {
        store.lastSeenMessageId = message.id
        do {
            let fileURL = try await DownloadManager.shared.downloadToLocalFile(from: message.url)
            audio.enqueue(message, localFileURL: fileURL)
        } catch {
            print("WalkieViewModel: failed to download message \(message.id): \(error)")
        }
    }
}
