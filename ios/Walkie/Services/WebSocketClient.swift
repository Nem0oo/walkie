import Foundation

enum ConnectionState {
    case disconnected
    case connecting
    case connected
}

/// `URLSessionWebSocketTask` never surfaces inbound ping/pong frames to app code — the
/// OS answers server-sent pings transparently and never tells the app it happened — so
/// there is no passive way to detect "this connection went idle-dead." Instead we
/// drive our own heartbeat: ping every ~20s, require a pong within 10s, and treat a
/// timeout exactly like a `didCloseWith` event (cancel, reconnect with backoff).
///
/// This is independent of, but complementary to, the server's own 25s ping (see
/// backend/src/ws/hub.ts): our heartbeat detects real liveness from the client's point
/// of view, while the server's heartbeat resets nginx-proxy's idle timer in the
/// server-to-client direction. Both are needed — neither alone covers both directions
/// of the proxy's 60s idle timeout.
final class WebSocketClient: NSObject, ObservableObject {
    @Published private(set) var state: ConnectionState = .disconnected
    // Surfaced in the UI — without Xcode/a Mac, console prints are otherwise invisible
    // on a Theos-built, sideloaded app.
    @Published private(set) var lastErrorDescription: String?

    var onMessage: ((VoiceMessage) -> Void)?

    // Dedicated session, NOT `.shared`: nginx-proxy negotiates HTTP/2 (ALPN) for this
    // host by default, and reusing `URLSession.shared` — already holding a pooled H2
    // connection to walkie.gcourtot.fr from APIClient's REST calls — makes iOS coalesce
    // the WebSocket task onto that H2 connection. The classic RFC6455 `Upgrade` header
    // this server relies on is meaningless over H2 — the socket never opens. A private
    // session gets its own connection pool, free to negotiate HTTP/1.1.
    // `lazy` + delegate: self so `didOpenWithProtocol` can flip `state` to `.connected`
    // as soon as the handshake actually completes — waiting for the first *message* (as
    // this used to) left the UI stuck on "Connexion…" forever on an idle-but-healthy
    // channel, since a ping/pong doesn't count as a message at this API level.
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        // Confirmed via server-side logs: without this, the WS socket gets torn down
        // by iOS ~5s after the app enters the background — while the app's own
        // Dispatch-timer-based reconnect logic kept firing on schedule the whole time,
        // proving the *process* stays alive (the UIBackgroundModes: audio keep-alive
        // loop is doing its job) but iOS still kills this specific socket on the
        // foreground→background transition. This flag is the documented ask to keep
        // the underlying TCP connection open across that transition instead of letting
        // it get reaped.
        configuration.shouldUseExtendedBackgroundIdleMode = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    private var task: URLSessionWebSocketTask?
    private var channelCode: String?
    private var backoff: TimeInterval = 1
    private let maxBackoff: TimeInterval = 30
    private var heartbeatTimer: Timer?
    private var reconnectWorkItem: DispatchWorkItem?

    // `connect(code:)` can be called more than once for the same WebSocketClient
    // instance — e.g. SwiftUI can fire `.onAppear` twice (a known quirk with
    // NavigationStack: popping back to a view re-triggers it), which would otherwise
    // call this while a handshake is already in flight or connected. Without this
    // guard, a second call creates a second `URLSessionWebSocketTask` that overwrites
    // `self.task`; the *first* task is left orphaned but still alive, and when its
    // `.receive()` eventually fails, its completion closure calls `scheduleReconnect()`
    // which does `task?.cancel()` — cancelling whatever `self.task` currently is, i.e.
    // the perfectly healthy *second* connection. That cross-task cancellation is a
    // self-inflicted `ECONNABORTED` ("software caused connection abort") loop that has
    // nothing to do with the network or the server.
    func connect(code: String) {
        if channelCode == code, state != .disconnected { return }
        channelCode = code
        reconnectWorkItem?.cancel()
        openSocket()
    }

    func disconnect() {
        reconnectWorkItem?.cancel()
        heartbeatTimer?.invalidate()
        task?.cancel(with: .goingAway, reason: nil)
        state = .disconnected
    }

    private func openSocket() {
        guard let channelCode, state != .connecting else { return }
        guard let url = Self.subscribeURL(code: channelCode) else {
            lastErrorDescription = "Aucun serveur configuré."
            return
        }
        state = .connecting

        let newTask = session.webSocketTask(with: url)
        task = newTask
        newTask.resume()

        listen(on: newTask)
        startHeartbeat(for: newTask)
    }

    /// Derives the `wss://` subscribe URL from the server configured in the
    /// Configuration tab (same host as `APIClient`'s REST calls, just a different
    /// scheme) — read fresh each time so a server change takes effect on next connect.
    private static func subscribeURL(code: String) -> URL? {
        guard let serverString = PersistenceStore.shared.serverURLString,
              let httpURL = URL(string: serverString) else { return nil }
        let path = httpURL.appendingPathComponent("channels").appendingPathComponent(code).appendingPathComponent("subscribe")
        guard var components = URLComponents(url: path, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = (components.scheme == "http") ? "ws" : "wss"
        return components.url
    }

    // Every callback below takes the specific task it was armed for and checks it's
    // still `self.task` (identity, not equality) before acting — a stale task that a
    // newer `connect()`/reconnect has already superseded is not allowed to touch shared
    // state or cancel the current task. See the note on `connect(code:)`.

    private func listen(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self, self.task === task else { return }
            switch result {
            case .success(let message):
                self.backoff = 1 // reset on any successful traffic
                self.state = .connected
                self.handle(message)
                self.listen(on: task) // receive() is one-shot — re-arm for the next frame
            case .failure(let error):
                let nsError = error as NSError
                var detail = "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
                if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                    detail += " ← \(underlying.domain) \(underlying.code): \(underlying.localizedDescription)"
                }
                print("WebSocketClient: connection failed: \(detail)")
                self.lastErrorDescription = detail
                self.scheduleReconnect(for: task)
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message, let data = text.data(using: .utf8) else { return }
        guard let voiceMessage = try? JSONDecoder().decode(VoiceMessage.self, from: data),
              voiceMessage.type == "new_message" else { return }
        onMessage?(voiceMessage)
    }

    private func startHeartbeat(for task: URLSessionWebSocketTask) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.sendPing(on: task)
        }
    }

    private func sendPing(on task: URLSessionWebSocketTask) {
        guard self.task === task else { return }
        var answered = false
        task.sendPing { error in
            answered = (error == nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.task === task, !answered else { return }
            self.scheduleReconnect(for: task)
        }
    }

    private func scheduleReconnect(for task: URLSessionWebSocketTask) {
        guard self.task === task else { return } // already superseded — nothing to do
        guard state != .disconnected else { return } // avoid stacking retries
        state = .disconnected
        task.cancel()
        heartbeatTimer?.invalidate()

        let delay = backoff
        backoff = min(backoff * 2, maxBackoff)

        let workItem = DispatchWorkItem { [weak self] in self?.openSocket() }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}

extension WebSocketClient: URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.task === webSocketTask else { return }
            self.state = .connected
            self.backoff = 1
        }
    }
}
