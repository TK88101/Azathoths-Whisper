import Testing
@testable import RemoteTransport

struct EchoServiceTests {
    /// 與 iPad Info.plist 的 NSBonjourServices、S0 N5 探針同一個服務型別
    @Test func bonjourServiceTypeAndDomain() {
        #expect(EchoService.type == "_yse._tcp")
        #expect(EchoService.domain == "local.")
    }
}
