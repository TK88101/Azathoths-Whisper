import Foundation

// HTTP 抽象（Plan §4.9）：每請求超時、取消傳播、錯誤分類；不自動重試（對齊原版）。
struct HTTPResponse: Equatable, Sendable {
    let statusCode: Int
    let body: String

    var isOK: Bool { statusCode == 200 }
}

enum HTTPError: Error, Equatable {
    case timedOut
    case cancelled
    case transport(String)     // DNS / 連線失敗等
    case invalidURL(String)
    case undecodableBody
}

protocol HTTPClient: Sendable {
    func get(_ url: URL, headers: [String: String], timeout: TimeInterval) async throws -> HTTPResponse
    func post(_ url: URL, form: [String: String], headers: [String: String], timeout: TimeInterval) async throws -> HTTPResponse
}

extension HTTPClient {
    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPResponse {
        try await get(url, headers: [:], timeout: timeout)
    }
}

// 各來源的超時值：沿用 py 既有值，Python 未設者取同級預設（Plan §4.9）
enum HTTPTimeout {
    static let darkLyricsDirect: TimeInterval = 10   // py:1312
    static let duckDuckGo: TimeInterval = 15         // py:1333/1336
    static let darkLyricsPage: TimeInterval = 15     // py:1360
    static let genius: TimeInterval = 15             // Python 未設，取同級預設
}

struct URLSessionHTTPClient: HTTPClient {
    // py:940 的 USER_AGENT 常量（原版定義但未使用；此處實際採用）
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36"

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieAcceptPolicy = .always
            configuration.httpShouldSetCookies = true
            configuration.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
            self.session = URLSession(configuration: configuration)
        }
    }

    func get(_ url: URL, headers: [String: String], timeout: TimeInterval) async throws -> HTTPResponse {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        return try await perform(request)
    }

    func post(_ url: URL, form: [String: String], headers: [String: String], timeout: TimeInterval) async throws -> HTTPResponse {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = Self.encodeForm(form).data(using: .utf8)
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw HTTPError.transport("non-HTTP response")
            }
            // 頁面可能非 UTF-8（DarkLyrics 為 Latin-1 系）；退回 ISO-8859-1 保證可解析
            let body = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
            guard let body else { throw HTTPError.undecodableBody }
            return HTTPResponse(statusCode: http.statusCode, body: body)
        } catch let error as HTTPError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw HTTPError.timedOut
            case .cancelled: throw HTTPError.cancelled
            default: throw HTTPError.transport(error.localizedDescription)
            }
        } catch is CancellationError {
            throw HTTPError.cancelled
        } catch {
            throw HTTPError.transport(error.localizedDescription)
        }
    }

    static func encodeForm(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form
            .sorted { $0.key < $1.key }
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
    }
}
