import Foundation
import Testing

@testable import AzathothsWhisper

// URLSessionHTTPClient 的真實路徑測試：用 URLProtocol 攔截，全程離線。
// 覆蓋 Plan §4.9 的超時/取消/錯誤分類與非 UTF-8 頁面解碼。
@Suite(.serialized)
struct HTTPClientTests {
    // URLProtocol 子類需要跨實例共享 handler，故用靜態變數；@Suite(.serialized) 確保不併發。
    final class StubURLProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = Self.handler else {
                client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
                return
            }
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    private func makeClient() -> URLSessionHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSessionHTTPClient(session: URLSession(configuration: configuration))
    }

    @Test func getReturnsStatusAndBody() async throws {
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("hello".utf8))
        }
        defer { StubURLProtocol.handler = nil }

        let response = try await makeClient().get(URL(string: "https://example.com/x")!, timeout: 5)
        #expect(response.statusCode == 200)
        #expect(response.body == "hello")
        #expect(response.isOK)
    }

    @Test func getPropagatesHeadersAndNonOKStatus() async throws {
        nonisolated(unsafe) var seenAuthorization: String?
        StubURLProtocol.handler = { request in
            seenAuthorization = request.value(forHTTPHeaderField: "Authorization")
            return (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!, Data())
        }
        defer { StubURLProtocol.handler = nil }

        let response = try await makeClient().get(
            URL(string: "https://example.com/x")!,
            headers: ["Authorization": "Bearer fake-token"],
            timeout: 5
        )
        #expect(response.statusCode == 403)
        #expect(response.isOK == false)
        #expect(seenAuthorization == "Bearer fake-token")
    }

    @Test func postSendsURLEncodedForm() async throws {
        nonisolated(unsafe) var seenBody: String?
        nonisolated(unsafe) var seenContentType: String?
        StubURLProtocol.handler = { request in
            // URLProtocol 下 httpBody 可能改走 stream，兩種都取
            if let body = request.httpBody {
                seenBody = String(data: body, encoding: .utf8)
            } else if let stream = request.httpBodyStream {
                stream.open()
                var buffer = [UInt8](repeating: 0, count: 4096)
                let read = stream.read(&buffer, maxLength: buffer.count)
                stream.close()
                seenBody = String(bytes: buffer.prefix(max(read, 0)), encoding: .utf8)
            }
            seenContentType = request.value(forHTTPHeaderField: "Content-Type")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("ok".utf8))
        }
        defer { StubURLProtocol.handler = nil }

        _ = try await makeClient().post(
            URL(string: "https://lite.duckduckgo.com/lite/")!,
            form: ["q": "site:darklyrics.com \"A\" \"B\""],
            headers: ["Referer": "https://lite.duckduckgo.com/"],
            timeout: 5
        )
        #expect(seenContentType == "application/x-www-form-urlencoded")
        #expect(seenBody?.hasPrefix("q=site%3Adarklyrics.com") == true)
    }

    @Test func mapsTimeoutToTypedError() async {
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        defer { StubURLProtocol.handler = nil }

        await #expect(throws: HTTPError.timedOut) {
            _ = try await makeClient().get(URL(string: "https://example.com/x")!, timeout: 1)
        }
    }

    @Test func mapsCancellationToTypedError() async {
        StubURLProtocol.handler = { _ in throw URLError(.cancelled) }
        defer { StubURLProtocol.handler = nil }

        await #expect(throws: HTTPError.cancelled) {
            _ = try await makeClient().get(URL(string: "https://example.com/x")!, timeout: 1)
        }
    }

    @Test func mapsOtherURLErrorsToTransport() async {
        StubURLProtocol.handler = { _ in throw URLError(.cannotFindHost) }
        defer { StubURLProtocol.handler = nil }

        do {
            _ = try await makeClient().get(URL(string: "https://example.com/x")!, timeout: 1)
            Issue.record("expected throw")
        } catch let error as HTTPError {
            guard case .transport = error else {
                Issue.record("expected .transport, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    // DarkLyrics 頁面非 UTF-8（Latin-1 系），需要退回解碼而非失敗
    @Test func decodesLatin1BodyWhenNotUTF8() async throws {
        let latin1 = "Mötley".data(using: .isoLatin1)!
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, latin1)
        }
        defer { StubURLProtocol.handler = nil }

        let response = try await makeClient().get(URL(string: "http://www.darklyrics.com/x.html")!, timeout: 5)
        #expect(response.body == "Mötley")
    }
}
