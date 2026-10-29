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
    @Published private(set) var playingMessageID: String?

    private let api = APIClient.shared
    private let store = PersistenceStore.shared
    private let history = MessageHistoryStore.shared
    private let webSocket = WebSocketClient()
    private let audio = AudioSessionManager()
    // The pairing / connect / catch-up pass. `start()` cancels the previous one before
    // launching a new one, so restarting (e.g. after a server change) can never leave two
    // `pair()` loops racing to create two channels.
    private var startTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    // Only one catch-up pass runs at a time (so a message can't be downloaded twice, and
    // the cursor only ever moves forward). A trigger arriving mid-pass sets
    // `catchUpRequested`, and the running pass loops once more instead of dropping it.
    private var isCatchingUp = false
    private var catchUpRequested = false

    private static let channelReplacedMessage =
        "L'ancien lien ne fonctionne plus sur le serveur : un nouveau lien a été créé, pense à le repartager."

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

        serverURLString = store.serverURLString

        // A push is only a wake-up signal: the message itself is fetched by the REST
        // catch-up, which delivers in server order from the persisted cursor. Handling the
        // push payload directly would let a failed message be skipped by a later success.
        webSocket.onMessage = { [weak self] _ in
            Task { @MainActor in await self?.catchUp() }
        }
        webSocket.onChannelGone = { [weak self] in
            Task { @MainActor in self?.handleChannelGone() }
        }
        webSocket.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                let wasConnected = self.connectionState == .connected
                self.connectionState = state
                // Anything sent while the socket was down was never pushed to us — and
                // in the background `onScenePhaseChange` won't fire — so pull it from
                // REST as soon as the socket is back.
                if state == .connected, !wasConnected, self.channelCode != nil {
                    Task { await self.catchUp() }
                }
            }
            .store(in: &cancellables)
        webSocket.$lastErrorDescription
            .receive(on: DispatchQueue.main)
            .sink { [weak self] description in
                guard let self else { return }
                if let description {
                    self.lastError = "WebSocket : \(description)"
                } else if self.lastError?.hasPrefix("WebSocket : ") == true {
                    self.lastError = nil // socket recovered — don't leave its stale error up
                }
            }
            .store(in: &cancellables)
        audio.$currentlyPlayingID
            .receive(on: DispatchQueue.main)
            .assign(to: &$playingMessageID)

        start()
    }

    func start() {
        guard serverURLString != nil else { return } // wait for Configuration tab
        startTask?.cancel()
        startTask = Task {
            if let existingCode = store.channelCode, let ownerToken = store.ownerToken {
                channelCode = existingCode
                webSocket.connect(code: existingCode, ownerToken: ownerToken)
                await catchUp()
            } else {
                if store.channelCode != nil {
                    // Paired before owner tokens existed: the server won't let this app
                    // read that channel anymore, so move to a fresh one.
                    forgetChannel()
                    lastError = Self.channelReplacedMessage
                }
                await pair()
            }
        }
    }

    func onScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .active else { return }
        audio.startKeepAlive() // no-op if already running; retries a failed first start
        guard channelCode != nil else { return }
        Task { await catchUp() }
    }

    // The app runs unattended in the background — a one-off failure here (cold-started
    // backend, transient DNS/network blip at first launch) must not strand the app on
    // "Configuration du canal…" forever. Retry with the same backoff shape as
    // WebSocketClient's reconnect (1s → 2s → ... → 30s cap) until it succeeds.
    private func pair() async {
        var backoff: TimeInterval = 1
        while channelCode == nil, !Task.isCancelled {
            do {
                let channel = try await api.createChannel()
                guard !Task.isCancelled else { return }
                store.channelCode = channel.code
                store.ownerToken = channel.owner_token
                channelCode = channel.code
                webSocket.connect(code: channel.code, ownerToken: channel.owner_token)
                return
            } catch {
                print("WalkieViewModel: pairing failed, retrying in \(backoff)s: \(error)")
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                backoff = min(backoff * 2, 30)
            }
        }
    }

    private func catchUp() async {
        catchUpRequested = true
        guard !isCatchingUp else { return } // the running pass will loop once more
        isCatchingUp = true
        defer { isCatchingUp = false }

        while catchUpRequested, let code = channelCode, let ownerToken = store.ownerToken {
            catchUpRequested = false
            do {
                let fetched = try await api.fetchMessages(code: code, ownerToken: ownerToken, since: store.lastSeenMessageId)
                for message in fetched {
                    // The cursor only moves past a message once it's safely stored, and
                    // stops at the first failure: `since=<lastSeenMessageId>` never
                    // re-delivers anything at or before the cursor, so skipping over a
                    // failed message to store a later one would lose it for good. The
                    // next trigger (push, reconnect, foreground) retries from there.
                    guard channelCode == code, await handleIncoming(message) else { break }
                    store.lastSeenMessageId = message.id
                }
            } catch let error as APIError where error.isChannelGone {
                handleChannelGone()
                return
            } catch {
                print("WalkieViewModel: catch-up failed: \(error)")
                lastError = "Rattrapage échoué : \(error.localizedDescription)"
            }
        }
    }

    /// Downloads, stores and queues one message for playback. Returns whether it is now
    /// stored (including when it already was), i.e. whether the cursor may move past it.
    private func handleIncoming(_ message: VoiceMessage) async -> Bool {
        if messages.contains(where: { $0.id == message.id }) { return true }
        guard let ownerToken = store.ownerToken else { return false }
        do {
            let downloadedURL = try await DownloadManager.shared.downloadToLocalFile(from: message.url, ownerToken: ownerToken)
            let stored = try history.save(
                id: message.id,
                sender: message.sender ?? "Anonyme",
                createdAt: message.created_at,
                downloadedFileURL: downloadedURL
            )
            messages.insert(stored, at: 0)
            lastError = nil
            audio.enqueue(id: stored.id, fileURL: history.fileURL(for: stored))
            return true
        } catch {
            print("WalkieViewModel: failed to handle message \(message.id): \(error)")
            lastError = "Message non lu (\(message.sender ?? "Anonyme")) : \(error.localizedDescription)"
            return false
        }
    }

    /// The server answered 401/404 for our channel (revoked from elsewhere, database
    /// reset, ...): retrying forever would leave the app silently deaf, so drop the
    /// channel and pair a new one — the user has to reshare the new link.
    private func handleChannelGone() {
        guard channelCode != nil else { return }
        forgetChannel()
        lastError = Self.channelReplacedMessage
        start()
    }

    private func forgetChannel() {
        webSocket.disconnect()
        store.channelCode = nil
        store.ownerToken = nil
        store.lastSeenMessageId = nil
        channelCode = nil
    }

    /// Replays a message from history — reuses the same serial playback queue as live
    /// messages so a manual replay never overlaps with an incoming one. Tapping the
    /// message that's currently playing stops it instead — this is the app's only
    /// stop/pause control.
    func replay(_ message: StoredMessage) {
        if playingMessageID == message.id {
            audio.stop()
        } else {
            audio.enqueue(id: message.id, fileURL: history.fileURL(for: message))
        }
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
        guard let code = channelCode, let ownerToken = store.ownerToken else { return }
        isRevoking = true
        defer { isRevoking = false }

        do {
            try await api.revokeChannel(code: code, ownerToken: ownerToken)
        } catch let error as APIError where error.isChannelGone {
            // Already gone server-side — nothing left to cut off, just pair a new one.
        } catch {
            print("WalkieViewModel: revoke failed: \(error)")
            lastError = "Révocation échouée : \(error.localizedDescription)"
            return
        }

        forgetChannel()
        start() // through `startTask`, so it can't race another pairing loop
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

        forgetChannel()
        store.serverURLString = trimmed
        serverURLString = trimmed
        lastError = nil
        start()
    }
}
