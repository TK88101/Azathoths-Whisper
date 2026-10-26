import Foundation
import Network
import Testing
@testable import RemoteTransport

// S2 T10：Bonjour 瀏覽結果的挑選（純函式）。實際瀏覽會觸發區域網路權限，屬 #2-1 實機驗收
struct MacBrowserSelectionTests {
    func mac(_ name: String) -> DiscoveredMac {
        DiscoveredMac(name: name, endpoint: .service(name: name, type: "_yse._tcp", domain: "local.", interface: nil))
    }

    @Test func pairingPrefersInstanceNameFromQR() {
        let all = [mac("Azathoth-AAAA"), mac("Azathoth-BBBB")]
        #expect(MacBrowser.order(all, preferring: "Azathoth-BBBB").map(\.name) == ["Azathoth-BBBB", "Azathoth-AAAA"])
        #expect(MacBrowser.order(all, preferring: "missing").map(\.name) == ["Azathoth-AAAA", "Azathoth-BBBB"])
    }

    /// S4 F14：等任何一台配對過的 Mac——每個配對過的名字都排前面（保持原順序）
    @Test func everyPairedNameIsPreferred() {
        let all = ["Azathoth-AAAA", "Azathoth-BBBB", "Azathoth-CCCC"].map {
            DiscoveredMac(name: $0, endpoint: .service(name: $0, type: EchoService.type, domain: "local.", interface: nil))
        }
        #expect(MacBrowser.order(all, preferringAny: ["Azathoth-CCCC", "Azathoth-BBBB"]).map(\.name)
                == ["Azathoth-BBBB", "Azathoth-CCCC", "Azathoth-AAAA"])
    }

    @Test func resultsAreOnlyYSEServicesInLocalDomain() {
        guard case .bonjour(let type, let domain) = MacBrowser.descriptor else { Issue.record("not bonjour"); return }
        #expect(type == "_yse._tcp" && domain == "local.")
    }
}

// S3 T14／S2 延後 LOW-6（sprint-3-detail.md §4.12）：Bonjour 結果分批到達時，收集整個時窗；
// 看到想要的 Mac 就提早返回（避免每次重連都多等滿時窗）
struct MacBrowserGatherTests {
    private func mac(_ name: String) -> DiscoveredMac {
        DiscoveredMac(name: name, endpoint: .service(name: name, type: "_yse._tcp", domain: "local.", interface: nil))
    }

    @Test func laterBatchWithinWindowIsNotLost() async {
        let (stream, continuation) = AsyncStream<[DiscoveredMac]>.makeStream()
        Task {
            continuation.yield([mac("A")])
            try? await Task.sleep(for: .milliseconds(100))
            continuation.yield([mac("A"), mac("B")])
        }
        let found = await MacBrowser.gather(stream, window: .milliseconds(400)) { _ in false }
        #expect(found.map(\.name) == ["A", "B"])
    }

    @Test func returnsEarlyWhenWantedMacAppears() async {
        let (stream, continuation) = AsyncStream<[DiscoveredMac]>.makeStream()
        Task {
            continuation.yield([mac("A")])
            try? await Task.sleep(for: .milliseconds(50))
            continuation.yield([mac("A"), mac("B")])
        }
        let started = ContinuousClock.now
        let found = await MacBrowser.gather(stream, window: .seconds(3)) { $0.contains { $0.name == "B" } }
        #expect(found.map(\.name) == ["A", "B"])
        #expect(ContinuousClock.now - started < .seconds(1))
    }

    /// 偏好的 Mac 沒出現：第一批非空之後只再等 settle，不等滿時窗（simplify 效率 #6）
    @Test func withoutWantedMacReturnsSoonAfterFirstBatch() async {
        let (stream, continuation) = AsyncStream<[DiscoveredMac]>.makeStream()
        continuation.yield([mac("A")])
        let started = ContinuousClock.now
        let found = await MacBrowser.gather(stream, window: .seconds(4), settle: .milliseconds(200)) { _ in false }
        #expect(found.map(\.name) == ["A"])
        #expect(ContinuousClock.now - started < .seconds(1))
    }

    /// 看到偏好名後再收一小段（security review LOW-3：冒名者先廣播同名時，真的那台仍來得及進清單）
    @Test func keepsCollectingBrieflyAfterWantedMacAppears() async {
        let (stream, continuation) = AsyncStream<[DiscoveredMac]>.makeStream()
        Task {
            continuation.yield([mac("B")])                    // 冒名者
            try? await Task.sleep(for: .milliseconds(80))
            continuation.yield([mac("B"), mac("B (2)")])      // 真的那台晚一點到
        }
        let found = await MacBrowser.gather(stream, window: .seconds(3), grace: .milliseconds(250)) { $0.contains { $0.name == "B" } }
        #expect(found.count == 2)
    }

    @Test func endedStreamReturnsLastSnapshot() async {
        let (stream, continuation) = AsyncStream<[DiscoveredMac]>.makeStream()
        continuation.yield([mac("A")])
        continuation.finish()
        #expect(await MacBrowser.gather(stream, window: .seconds(3)) { _ in false }.map(\.name) == ["A"])
    }

    @Test func nothingFoundIsEmptyAfterWindow() async {
        let (stream, _) = AsyncStream<[DiscoveredMac]>.makeStream()
        #expect(await MacBrowser.gather(stream, window: .milliseconds(100)) { _ in false }.isEmpty)
    }
}
