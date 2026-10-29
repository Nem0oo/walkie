import Foundation

/// UserDefaults is enough here — the channel code is a shareable-link secret, and the
/// owner token only guards that same channel's voice clips (no account behind it), so
/// storing them in the Keychain would be over-engineering for v1. Don't "fix" this into
/// Keychain without a reason; it was a deliberate call.
final class PersistenceStore {
    static let shared = PersistenceStore()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let channelCode = "walkie.channelCode"
        static let ownerToken = "walkie.ownerToken"
        static let lastSeenMessageId = "walkie.lastSeenMessageId"
        static let serverURL = "walkie.serverURL"
    }

    var channelCode: String? {
        get { defaults.string(forKey: Keys.channelCode) }
        set { defaults.set(newValue, forKey: Keys.channelCode) }
    }

    var ownerToken: String? {
        get { defaults.string(forKey: Keys.ownerToken) }
        set { defaults.set(newValue, forKey: Keys.ownerToken) }
    }

    var lastSeenMessageId: String? {
        get { defaults.string(forKey: Keys.lastSeenMessageId) }
        set { defaults.set(newValue, forKey: Keys.lastSeenMessageId) }
    }

    /// `nil` until the user configures one in the Configuration tab — deliberately no
    /// hardcoded default, so a sideloaded copy of this app never silently phones home to
    /// the maintainer's own server.
    var serverURLString: String? {
        get { defaults.string(forKey: Keys.serverURL) }
        set { defaults.set(newValue, forKey: Keys.serverURL) }
    }
}
