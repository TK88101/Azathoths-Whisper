import Foundation

@testable import AzathothsWhisper

// 測試用 HTTP 替身：按 URL 前綴路由到預設回應，並記錄請求（Plan §7：集成測試離線化）
final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    struct Request: Equatable {
        let method: String
        let url: String
        let headers: [String: String]
        let form: [String: String]
    }

    enum Route {
        case response(HTTPResponse)
        case failure(HTTPError)
    }

    private let lock = NSLock()
    private var routes: [(match: String, route: Route)] = []
    private var fallback: Route = .response(HTTPResponse(statusCode: 404, body: "not found"))
    private var recorded: [Request] = []

    init() {}

    @discardableResult
    func on(_ urlSubstring: String, respond: HTTPResponse) -> Self {
        lock.lock(); defer { lock.unlock() }
        routes.append((urlSubstring, .response(respond)))
        return self
    }

    @discardableResult
    func on(_ urlSubstring: String, fail error: HTTPError) -> Self {
        lock.lock(); defer { lock.unlock() }
        routes.append((urlSubstring, .failure(error)))
        return self
    }

    @discardableResult
    func setFallback(_ route: Route) -> Self {
        lock.lock(); defer { lock.unlock() }
        fallback = route
        return self
    }

    var requests: [Request] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    var requestedURLs: [String] {
        requests.map(\.url)
    }

    func get(_ url: URL, headers: [String: String], timeout: TimeInterval) async throws -> HTTPResponse {
        try resolve(method: "GET", url: url, headers: headers, form: [:])
    }

    func post(_ url: URL, form: [String: String], headers: [String: String], timeout: TimeInterval) async throws -> HTTPResponse {
        try resolve(method: "POST", url: url, headers: headers, form: form)
    }

    private func resolve(method: String, url: URL, headers: [String: String], form: [String: String]) throws -> HTTPResponse {
        lock.lock()
        recorded.append(Request(method: method, url: url.absoluteString, headers: headers, form: form))
        let matched = routes.first { url.absoluteString.contains($0.match) }?.route ?? fallback
        lock.unlock()

        switch matched {
        case .response(let response): return response
        case .failure(let error): throw error
        }
    }
}
