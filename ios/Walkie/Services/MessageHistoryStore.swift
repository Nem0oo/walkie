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

    /// A copy under a human-readable name ("Sender 2026-07-16 1204 (ab12).m4a"), for
    /// exporting a message out of the app (share sheet → Files/AirDrop/etc.) — the
    /// stored file itself is just named after its opaque id, not fit to hand someone as
    /// a keepsake. Cached in tmp/Exports and reused across calls for the same message;
    /// the id suffix keeps two messages from the same sender in the same minute from
    /// colliding onto (and silently serving) the same export file.
    func exportURL(for message: StoredMessage) -> URL {
        let date = Self.isoFormatter.date(from: message.createdAt) ?? Date()
        let name = "\(Self.sanitizedFilenameComponent(message.sender)) \(Self.exportDateFormatter.string(from: date)) (\(message.id.suffix(4))).m4a"

        let exportsDir = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: exportsDir, withIntermediateDirectories: true)

        let destination = exportsDir.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.copyItem(at: fileURL(for: message), to: destination)
        }
        return destination
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

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // No colons: macOS/Finder alias ":" to "/" in filenames, which is confusing when
    // exporting to a Mac via AirDrop/Files.
    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return formatter
    }()

    private static let filenameSafeCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))

    private static func sanitizedFilenameComponent(_ raw: String) -> String {
        let filtered = String(String.UnicodeScalarView(raw.unicodeScalars.filter { filenameSafeCharacters.contains($0) }))
        let trimmed = filtered.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Anonyme" : trimmed
    }
}
