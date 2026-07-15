import Foundation

/// Matches both the REST catch-up array shape (`GET /channels/:code/messages`) and the
/// WebSocket push payload (`{"type":"new_message", ...}`) — `type` is nil for REST
/// responses (the key isn't present there) and used purely as a discriminator by
/// WebSocketClient for the live-push path.
struct VoiceMessage: Codable, Identifiable, Equatable {
    let id: String
    let url: URL
    let sender: String?
    let created_at: String
    let type: String?
}
