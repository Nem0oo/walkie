import Foundation

enum APIError: Error {
    case invalidResponse
    case serverError(Int)
}

final class APIClient {
    static let shared = APIClient()

    // The backend subdomain chosen for this deployment (walkie.gcourtot.fr).
    private let baseURL = URL(string: "https://walkie.gcourtot.fr")!
    private let session = URLSession.shared

    func createChannel() async throws -> Channel {
        var request = URLRequest(url: baseURL.appendingPathComponent("channels"))
        request.httpMethod = "POST"
        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response, expect: 201)
        return try JSONDecoder().decode(Channel.self, from: data)
    }

    func channelExists(code: String) async throws -> Bool {
        let url = baseURL.appendingPathComponent("channels").appendingPathComponent(code)
        let (_, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return http.statusCode == 200
    }

    func fetchMessages(code: String, since: String?) async throws -> [VoiceMessage] {
        var url = baseURL.appendingPathComponent("channels").appendingPathComponent(code).appendingPathComponent("messages")
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
