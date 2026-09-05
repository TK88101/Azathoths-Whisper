import Foundation
import Testing

@testable import AzathothsWhisper

// ACCEPTANCE D-08：token 驗證走 Genius account API
@Suite("GeniusTokenValidator")
struct TokenValidatorTests {
    private let validAccountBody = #"{"response":{"user":{"id":1,"name":"tester"}}}"#

    @Test func acceptsAccountResponseContainingUser() async {
        let client = MockHTTPClient()
        client.on("api.genius.com/account", respond: HTTPResponse(statusCode: 200, body: validAccountBody))

        let result = await GeniusTokenValidator(client: client).validate(token: "fake-token")

        #expect(result == .valid)
        let request = client.requests.first
        #expect(request?.headers["Authorization"] == "Bearer fake-token")
        #expect(request?.url.contains("api.genius.com/account") == true)
    }

    @Test func rejectsUnauthorizedResponse() async {
        let client = MockHTTPClient()
        client.on("api.genius.com/account", respond: HTTPResponse(statusCode: 401, body: "{}"))

        let result = await GeniusTokenValidator(client: client).validate(token: "fake-bad")

        #expect(result == .invalid("HTTP 401 from Genius account API"))
    }

    @Test func rejectsResponseWithoutUserPayload() async {
        let client = MockHTTPClient()
        client.on("api.genius.com/account", respond: HTTPResponse(statusCode: 200, body: #"{"response":{}}"#))

        let result = await GeniusTokenValidator(client: client).validate(token: "fake-token")

        #expect(result == .invalid("Unexpected account response"))
    }

    @Test func mapsTransportFailureToMessage() async {
        let client = MockHTTPClient()
        client.on("api.genius.com/account", fail: .timedOut)

        let result = await GeniusTokenValidator(client: client).validate(token: "fake-token")

        #expect(result == .invalid("request timed out"))
    }

    @Test func rejectsEmptyTokenWithoutNetworkCall() async {
        let client = MockHTTPClient()

        let result = await GeniusTokenValidator(client: client).validate(token: "   ")

        #expect(result == .invalid("Empty token"))
        #expect(client.requests.isEmpty)
    }
}
