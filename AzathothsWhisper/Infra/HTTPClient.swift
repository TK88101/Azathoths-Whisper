import Foundation

// HTTP 抽象（Plan §4.9）：每請求超時、取消傳播、錯誤分類；不自動重試（對齊原版）。
struct HTTPResponse: Equatable, Sendable {
    let statusCode: Int
    let body: String
    /// 標頭名一律小寫（`retry-after`）
    let headers: [String: String]

    init(statusCode: Int, body: String, headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.body = body
        self.headers = headers
    }

    var isOK: Bool { statusCode == 200 }
}

/// 任意方法＋原始 body 的請求（C 段：JSON POST、GraphQL）
struct HTTPRequest: Equatable, Sendable {
    static let defaultMaxResponseBytes = 2 << 20

    let method: String
    let url: URL
    let headers: [String: String]
    let body: Data?
    let timeout: TimeInterval
    /// 回應大小上限：接收中超過即中止（C 段計劃 §3.1，Codex R1 #2）
    let maxResponseBytes: Int

    init(
        method: String, url: URL, headers: [String: String] = [:], body: Data? = nil,
        timeout: TimeInterval, maxResponseBytes: Int = HTTPRequest.defaultMaxResponseBytes
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
        self.maxResponseBytes = maxResponseBytes
    }
}

enum HTTPError: Error, Equatable {
    case timedOut
    case cancelled
    case transport(String)     // DNS / 連線失敗等
    case invalidURL(String)
    case undecodableBody
    case responseTooLarge
}

protocol HTTPClient: Sendable {
    func get(_ url: URL, headers: [String: String], timeout: TimeInterval) async throws -> HTTPResponse
    func post(_ url: URL, form: [String: String], headers: [String: String], timeout: TimeInterval) async throws -> HTTPResponse
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
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

    /// 邊收邊數：`Content-Length` 或實收量超過上限即中止；轉址只跟同主機的 https（C 段計劃 §3.1）
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method
        for (key, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: key) }
        urlRequest.httpBody = request.body
        return try await mappingErrors {
            let (bytes, response) = try await session.bytes(for: urlRequest, delegate: SameHostHTTPSRedirects())
            let http = try Self.httpResponse(response)
            guard http.expectedContentLength <= Int64(request.maxResponseBytes) else {
                bytes.task.cancel()
                throw HTTPError.responseTooLarge
            }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > request.maxResponseBytes {
                    bytes.task.cancel()
                    throw HTTPError.responseTooLarge
                }
            }
            return HTTPResponse(statusCode: http.statusCode, body: try Self.decode(data), headers: Self.lowercasedHeaders(http))
        }
    }

    /// 時間軸查找專用：不收也不送 cookie，與 Genius／DarkLyrics 的 session 分開
    static func cookielessConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        return configuration
    }

    private func perform(_ request: URLRequest) async throws -> HTTPResponse {
        try await mappingErrors {
            let (data, response) = try await session.data(for: request)
            return HTTPResponse(statusCode: try Self.httpResponse(response).statusCode, body: try Self.decode(data))
        }
    }

    private static func httpResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else { throw HTTPError.transport("non-HTTP response") }
        return http
    }

    /// 頁面可能非 UTF-8（DarkLyrics 為 Latin-1 系）；退回 ISO-8859-1 保證可解析
    private static func decode(_ data: Data) throws -> String {
        guard let body = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw HTTPError.undecodableBody
        }
        return body
    }

    private static func lowercasedHeaders(_ response: HTTPURLResponse) -> [String: String] {
        Dictionary(
            response.allHeaderFields.compactMap { key, value in
                (key as? String).map { ($0.lowercased(), "\(value)") }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func mappingErrors(_ operation: () async throws -> HTTPResponse) async throws -> HTTPResponse {
        do {
            return try await operation()
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

/// 轉址只准同主機、https→https；其餘不跟，呼叫端拿到的就是那個 3xx（C 段計劃 §3.1，Codex R2 #4）
private final class SameHostHTTPSRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let original = task.originalRequest?.url, let target = request.url,
              target.scheme?.lowercased() == "https",
              target.host?.lowercased() == original.host?.lowercased(),
              (target.port ?? 443) == (original.port ?? 443)
        else { return nil }
        return request
    }
}
