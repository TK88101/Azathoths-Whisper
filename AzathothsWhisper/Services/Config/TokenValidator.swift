import Foundation

// Genius token 驗證（py:2141-2152 validate_token → lyricsgenius Genius.account()）。
// 庫實作＝GET https://api.genius.com/account 帶 Bearer，非 2xx 由 requests 拋 HTTPError。
enum TokenValidation: Equatable, Sendable {
    case valid
    case invalid(String)
}

protocol TokenValidating: Sendable {
    func validate(token: String) async -> TokenValidation
}

struct GeniusTokenValidator: TokenValidating {
    static let accountEndpoint = URL(string: "https://api.genius.com/account")!

    let client: any HTTPClient

    func validate(token: String) async -> TokenValidation {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalid("Empty token") }

        do {
            let response = try await client.get(
                Self.accountEndpoint,
                headers: ["Authorization": "Bearer \(trimmed)"],
                timeout: HTTPTimeout.genius
            )
            guard response.isOK else {
                return .invalid("HTTP \(response.statusCode) from Genius account API")
            }
            guard Self.containsUser(response.body) else {
                return .invalid("Unexpected account response")
            }
            return .valid
        } catch let error as HTTPError {
            return .invalid(GeniusSource.describe(error))
        } catch {
            return .invalid(error.localizedDescription)
        }
    }

    /// account() 以 response.user 是否存在判定有效（py:2147-2150）
    static func containsUser(_ body: String) -> Bool {
        guard
            let data = body.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let payload = root["response"] as? [String: Any]
        else { return false }
        return payload["user"] != nil
    }
}
