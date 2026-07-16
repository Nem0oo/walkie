import Foundation

/// Persists received voice messages (audio + metadata) to disk so they can be replayed
/// later — the app's Documents directory survives relaunches, unlike the temp
/// directory `DownloadManager` downloads into first.
final class MessageHistoryStore {
    static let shared = MessageHistoryStore()

    private let directory: URL
    private let indexFile: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = documents.appendingPathComponent("Messages", isDirectory: true)
        indexFile = directory.appendingPathComponent("index.json")

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // These are ephemeral voice clips, not user documents worth cloud backup space.
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(excluded)
    }

    func fileURL(for message: StoredMessage) -> URL {
        directory.appendingPathComponent(message.filename)
    }

    /// Moves the (temp) downloaded file into permanent storage and appends it to the index.
    func save(id: String, sender: String, createdAt: String, downloadedFileURL: URL) throws -> StoredMessage {
        let filename = "\(id).m4a"
        let destination = directory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: downloadedFileURL, to: destination)

        let stored = StoredMessage(id: id, sender: sender, createdAt: createdAt, filename: filename)
        var all = loadAll()
        all.append(stored)
        try save(all)
        return stored
    }

    /// Chronological order (oldest first) — callers that want most-recent-first reverse it.
    func loadAll() -> [StoredMessage] {
        guard let data = try? Data(contentsOf: indexFile) else { return [] }
        return (try? JSONDecoder().decode([StoredMessage].self, from: data)) ?? []
    }

    private func save(_ messages: [StoredMessage]) throws {
        let data = try JSONEncoder().encode(messages)
        try data.write(to: indexFile, options: .atomic)
    }
}
