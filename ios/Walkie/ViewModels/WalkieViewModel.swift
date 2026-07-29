import Combine
import Foundation
import SwiftUI

@MainActor
final class WalkieViewModel: ObservableObject {
    @Published private(set) var channelCode: String?
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var messages: [StoredMessage] = [] // most recent first
    // Surfaced in the UI (not just printed) — without Xcode/a Mac, console prints are
    // otherwise invisible on a Theos-built, sideloaded app.
    @Published private(set) var lastError: String?
    @Published private(set) var isRevoking = false
    @Published private(set) var serverURLString: String?

    private let api = APIClient.shared
    private let store = PersistenceStore.shared
    private let history = MessageHistoryStore.shared
    private let webSocket = WebSocketClient()
    private let audio = AudioSessionManager()
    // `.onAppear` (which calls `start()`) can fire more than once for the same view —
    // e.g. popping back from HistoryView re-triggers it. `WebSocketClient.connect` is
    // itself guarded against redundant calls, but avoiding a duplicate `pair()`/
    // `catchUp()` pass here too is one less thing to reason about.
    private var hasStarted = false

    var shareURL: URL? {
        guard let code = channelCode, let serverString = serverURLString, let base = URL(string: serverString) else {
            return nil
        }
        return base.appendingPathComponent("send").appendingPathComponent(code)
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
        messages = Array(history.loadAll().reversed())

        // Pre-v-configuration-tab installs have a paired `channelCode` but never wrote a
        // `serverURLString` (that setting didn't exist yet) — they were always pointed
        // at the maintainer's own server. Grandfather them in rather than stranding
        // existing users on "no server configured" after an update. Fresh installs
        // (no channelCode either) get no default: see `PersistenceStore.serverURLString`.
        if store.serverURLString == nil, store.channelCode != nil {
            store.serverURLString = "https://walkie.gcourtot.fr"
        }
        serverURLString = store.serverURLString

        webSocket.onMessage = { [weak self] message in
            Task { @MainActor in await self?.handleIncoming(message) }
        }
        webSocket.$state
            .receive(on: DispatchQueue.main)
            .assign(to: &$connectionState)
        webSocket.$lastErrorDescription
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .map { "WebSocket : \($0)" }
            .assign(to: &$lastError)
    }

    func start() {
        guard !hasStarted else { return }
        guard serverURLString != nil else { return } // wait for Configuration tab
        hasStarted = true
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
            let fetched = try await api.fetchMessages(code: code, since: store.lastSeenMessageId)
            for message in fetched {
                await handleIncoming(message)
            }
        } catch {
            print("WalkieViewModel: catch-up failed: \(error)")
            lastError = "Rattrapage échoué : \(error.localizedDescription)"
        }
    }

    private func handleIncoming(_ message: VoiceMessage) async {
        do {
            let downloadedURL = try await DownloadManager.shared.downloadToLocalFile(from: message.url)
            let stored = try history.save(
                id: message.id,
                sender: message.sender ?? "Anonyme",
                createdAt: message.created_at,
                downloadedFileURL: downloadedURL
            )
            // Only mark as seen once actually persisted — marking it earlier would let a
            // transient download/save failure silently and permanently drop the message,
            // since the REST catch-up (`since=<lastSeenMessageId>`) would never re-deliver
            // anything at or before this id.
            store.lastSeenMessageId = message.id
            messages.insert(stored, at: 0)
            lastError = nil
            audio.enqueue(id: stored.id, fileURL: history.fileURL(for: stored))
        } catch {
            print("WalkieViewModel: failed to handle message \(message.id): \(error)")
            lastError = "Message non lu (\(message.sender ?? "Anonyme")) : \(error.localizedDescription)"
        }
    }

    /// Replays a message from history — reuses the same serial playback queue as live
    /// messages so a manual replay never overlaps with an incoming one.
    func replay(_ message: StoredMessage) {
        audio.enqueue(id: message.id, fileURL: history.fileURL(for: message))
    }

    /// Deletes a single message from local history (audio file + index entry).
    func delete(_ message: StoredMessage) {
        do {
            try history.delete(message)
            messages.removeAll { $0.id == message.id }
        } catch {
            print("WalkieViewModel: failed to delete message \(message.id): \(error)")
            lastError = "Suppression échouée : \(error.localizedDescription)"
        }
    }

    /// Invalidates the current link (everyone who has it loses access) and re-runs the
    /// normal pairing flow to get a fresh one — deliberately reuses `pair()`'s own
    /// retry/backoff rather than duplicating that logic here.
    func revokeChannelAndRepair() async {
        guard let code = channelCode else { return }
        isRevoking = true
        defer { isRevoking = false }

        do {
            try await api.revokeChannel(code: code)
        } catch {
            print("WalkieViewModel: revoke failed: \(error)")
            lastError = "Révocation échouée : \(error.localizedDescription)"
            return
        }

        webSocket.disconnect()
        store.channelCode = nil
        store.lastSeenMessageId = nil
        channelCode = nil
        await pair()
    }

    /// Points the app at a different backend. Distributed copies of this app must never
    /// silently pair against the maintainer's own server — this is the only way a
    /// server gets configured (see `PersistenceStore.serverURLString`). Switching server
    /// implicitly abandons the current channel: a channel code only means something on
    /// the server that issued it, so a fresh one is paired on the new server. Locally
    /// downloaded message history (audio files) is unaffected — it doesn't depend on
    /// the server that originally delivered it.
    func configureServer(_ urlString: String) {
        var trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/") { trimmed.removeLast() }

        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host != nil else {
            lastError = "URL de serveur invalide (exemple : https://mon-serveur.fr)."
            return
        }
        guard trimmed != store.serverURLString else { return }

        webSocket.disconnect()
        store.serverURLString = trimmed
        store.channelCode = nil
        store.lastSeenMessageId = nil
        serverURLString = trimmed
        channelCode = nil
        lastError = nil
        hasStarted = false
        start()
    }
}
