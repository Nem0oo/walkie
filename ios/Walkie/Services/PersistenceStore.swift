import Foundation

/// UserDefaults is enough here — the channel code is a shareable-link secret, not a
/// high-value credential (same trust model as a classic share link), so storing it in
/// the Keychain would be over-engineering for v1. Don't "fix" this into Keychain
/// without a reason; it was a deliberate call.
final class PersistenceStore {
    static let shared = PersistenceStore()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let channelCode = "walkie.channelCode"
        static let lastSeenMessageId = "walkie.lastSeenMessageId"
    }

    var channelCode: String? {
        get { defaults.string(forKey: Keys.channelCode) }
        set { defaults.set(newValue, forKey: Keys.channelCode) }
    }

    var lastSeenMessageId: String? {
        get { defaults.string(forKey: Keys.lastSeenMessageId) }
        set { defaults.set(newValue, forKey: Keys.lastSeenMessageId) }
    }
}
