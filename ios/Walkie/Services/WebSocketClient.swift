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

    var onMessage: ((VoiceMessage) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var channelCode: String?
    private var backoff: TimeInterval = 1
    private let maxBackoff: TimeInterval = 30
    private var heartbeatTimer: Timer?
    private var reconnectWorkItem: DispatchWorkItem?

    func connect(code: String) {
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
        guard let channelCode else { return }
        state = .connecting

        let url = URL(string: "wss://walkie.gcourtot.fr/channels/\(channelCode)/subscribe")!
        let newTask = URLSession.shared.webSocketTask(with: url)
        task = newTask
        newTask.resume()

        listen()
        startHeartbeat()
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.backoff = 1 // reset on any successful traffic
                self.state = .connected
                self.handle(message)
                self.listen() // receive() is one-shot — re-arm for the next frame
            case .failure:
                self.scheduleReconnect()
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message, let data = text.data(using: .utf8) else { return }
        guard let voiceMessage = try? JSONDecoder().decode(VoiceMessage.self, from: data),
              voiceMessage.type == "new_message" else { return }
        onMessage?(voiceMessage)
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }

    private func sendPing() {
        guard let task else { return }
        var answered = false
        task.sendPing { error in
            answered = (error == nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if !answered { self?.scheduleReconnect() }
        }
    }

    private func scheduleReconnect() {
        guard state != .disconnected else { return } // avoid stacking retries
        state = .disconnected
        task?.cancel()
        heartbeatTimer?.invalidate()

        let delay = backoff
        backoff = min(backoff * 2, maxBackoff)

        let workItem = DispatchWorkItem { [weak self] in self?.openSocket() }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
