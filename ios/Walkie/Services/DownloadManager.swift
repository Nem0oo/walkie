import Foundation

enum DownloadError: Error {
    case invalidResponse
}

final class DownloadManager {
    static let shared = DownloadManager()

    private let session = URLSession.shared

    /// AVAudioPlayer needs a local file URL, not a remote one — especially unreliable
    /// in background. Download fully before handing off to playback.
    func downloadToLocalFile(from url: URL, ownerToken: String) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(ownerToken)", forHTTPHeaderField: "Authorization")
        let (tempURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DownloadError.invalidResponse
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }
}
