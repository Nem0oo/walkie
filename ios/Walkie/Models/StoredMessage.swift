import Foundation

/// A voice message persisted locally for replay — distinct from `VoiceMessage` (the
/// wire format) once its audio has been downloaded and saved to disk.
struct StoredMessage: Codable, Identifiable, Equatable {
    let id: String
    let sender: String
    let createdAt: String
    let filename: String
}
