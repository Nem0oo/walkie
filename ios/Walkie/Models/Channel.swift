import Foundation

struct Channel: Codable {
    let code: String
    // Only ever returned by `POST /channels`: proves this app owns the channel (reading
    // history, downloading audio, subscribing, revoking). The code alone only allows sending.
    let owner_token: String
}
