import Foundation

enum APIError: Error {
    case invalidResponse
    case serverError(Int)
    case noServerConfigured
}

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Réponse invalide du serveur."
        case .serverError(let code): return "Erreur serveur (\(code))."
        case .noServerConfigured: return "Aucun serveur configuré."
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    private let session = URLSession.shared

    // Read fresh on every call (rather than cached at init) so switching servers in the
    // Configuration tab takes effect immediately, without recreating this singleton.
    private var baseURL: URL {
        get throws {
            guard let string = PersistenceStore.shared.serverURLString,
                  let url = URL(string: string) else {
                throw APIError.noServerConfigured
            }
            return url
        }
    }

    func createChannel() async throws -> Channel {
        var request = URLRequest(url: try baseURL.appendingPathComponent("channels"))
        request.httpMethod = "POST"
        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response, expect: 201)
        return try JSONDecoder().decode(Channel.self, from: data)
    }

    func channelExists(code: String) async throws -> Bool {
        let url = try baseURL.appendingPathComponent("channels").appendingPathComponent(code)
        let (_, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return http.statusCode == 200
    }

    /// Invalidates the current channel code — everyone holding the old link loses
    /// access. Doesn't return a replacement; callers re-run the normal pairing flow.
    func revokeChannel(code: String) async throws {
        var request = URLRequest(url: try baseURL.appendingPathComponent("channels").appendingPathComponent(code).appendingPathComponent("revoke"))
        request.httpMethod = "POST"
        let (_, response) = try await session.data(for: request)
        try Self.checkStatus(response, expect: 204)
    }

    func fetchMessages(code: String, since: String?) async throws -> [VoiceMessage] {
        var url = try baseURL.appendingPathComponent("channels").appendingPathComponent(code).appendingPathComponent("messages")
        if let since {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "since", value: since)]
            url = components.url!
        }
        let (data, response) = try await session.data(from: url)
        try Self.checkStatus(response, expect: 200)
        return try JSONDecoder().decode([VoiceMessage].self, from: data)
    }

    private static func checkStatus(_ response: URLResponse, expect: Int) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard http.statusCode == expect else { throw APIError.serverError(http.statusCode) }
    }
}
