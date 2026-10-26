import Foundation
import Network
import RemoteProtocol
import Testing
@testable import RemoteTransport

// S7 T6 E1a（sprint-7-detail.md §4.5）：中繼端連線清理的長跑。只證「連線資源有清掉」，不宣稱記憶體耐久。
// 判定抽成純函式 `EnduranceSnapshot.leaks`，另有負向單測（不靠改正式清理碼讓測試變紅）

#if os(macOS)
/// 伺服器端可觀測的連線資源（皆為 TransportServer 既有的 internal 計數）
struct EnduranceSnapshot: Equatable {
    var peers: Int
    var unclassified: Int
    var pendingSendBytes: Int
    var artworkInFlight: Int

    /// 沒有任何客戶端在線時應全部歸零；回傳殘留項目（空＝乾淨）
    func leaks() -> [String] {
        [("peers", peers), ("unclassified", unclassified), ("pendingSendBytes", pendingSendBytes), ("artworkInFlight", artworkInFlight)]
            .filter { $0.1 != 0 }
            .map { "\($0.0)=\($0.1)" }
    }
}

extension EnduranceSnapshot {
    init(_ server: TransportServer) {
        self.init(peers: server.connectedPeers.count, unclassified: server.unclassifiedCount,
                  pendingSendBytes: server.pendingSendBytesTotal, artworkInFlight: server.artworkInFlightTotal)
    }
}

private func waitFor(_ timeout: TimeInterval = 3, _ condition: @Sendable () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

private func session(_ h: Harness, port: NWEndpoint.Port? = nil) async throws -> (TestPeer, Data) {
    let peer = try #require(await TestPeer.tls(port: port ?? h.port, identity: h.ipadIdentity, serverPin: h.macIdentity.fingerprint))
    let hello = try #require(await peer.nextKind())
    let object = try #require(try JSONSerialization.jsonObject(with: hello.data) as? [String: Any])
    let body = try #require(object["body"] as? [String: Any])
    let encoded = try #require(body["sessionNonce"] as? String)
    return (peer, try #require(Data(base64Encoded: encoded)))
}

private var pageBody: [String: Any] { ["cursor": NSNull(), "limit": 10] }
private var artworkBody: [String: Any] { ["albumID": "0123456789abcdef", "size": "spine", "artworkToken": "0123456789abcdef"] }

/// 等伺服器把剛關掉的連線清乾淨；失敗時把殘留項目印進斷言訊息
private func expectClean(_ server: TransportServer, round: Int, _ scenario: String) async {
    let clean = await waitFor { EnduranceSnapshot(server).leaks().isEmpty }
    #expect(clean, "\(scenario) 第 \(round) 輪殘留：\(EnduranceSnapshot(server).leaks())")
}

struct EnduranceSnapshotTests {
    @Test func cleanSnapshotHasNoLeaks() {
        #expect(EnduranceSnapshot(peers: 0, unclassified: 0, pendingSendBytes: 0, artworkInFlight: 0).leaks().isEmpty)
    }

    @Test func everyKindOfResidueIsReported() {
        #expect(EnduranceSnapshot(peers: 1, unclassified: 0, pendingSendBytes: 0, artworkInFlight: 0).leaks() == ["peers=1"])
        #expect(EnduranceSnapshot(peers: 0, unclassified: 2, pendingSendBytes: 0, artworkInFlight: 0).leaks() == ["unclassified=2"])
        #expect(EnduranceSnapshot(peers: 0, unclassified: 0, pendingSendBytes: 512, artworkInFlight: 0).leaks() == ["pendingSendBytes=512"])
        #expect(EnduranceSnapshot(peers: 0, unclassified: 0, pendingSendBytes: 0, artworkInFlight: 3).leaks() == ["artworkInFlight=3"])
        #expect(EnduranceSnapshot(peers: 1, unclassified: 1, pendingSendBytes: 1, artworkInFlight: 1).leaks().count == 4)
    }
}

@Suite(.serialized, .timeLimit(.minutes(2))) struct RelayEnduranceTests {
    private func pairedHarness(handler: ScriptedHandler) async throws -> Harness {
        let h = try await Harness(handler: handler)
        guard case .approved = await h.pair() else { throw CancellationError() }
        return h
    }

    /// 情境 1：連上 → 一次往返 → 客戶端關閉 → 伺服器歸零，200 輪
    @Test func normalSessionsAreCleanedUpEveryRound() async throws {
        let h = try await pairedHarness(handler: ScriptedHandler())
        for round in 1...200 {
            let (peer, nonce) = try await session(h)
            peer.send(envelope(kind: "catalog.page", body: pageBody, seq: 1, nonce: nonce))
            #expect(await peer.nextKind()?.kind == "catalog.page", "第 \(round) 輪沒有回覆")
            peer.cancel()
            await expectClean(h.server, round: round, "正常")
        }
    }

    /// 情境 2：素材請求還在處理時客戶端斷線——名額在工作結束時才歸還（既有語義），放行後歸零，50 輪
    @Test func artworkInFlightAtDisconnectIsReturnedWhenWorkFinishes() async throws {
        let handler = ScriptedHandler()
        let h = try await pairedHarness(handler: handler)
        for round in 1...50 {
            handler.block()
            let (peer, nonce) = try await session(h)
            peer.send(envelope(kind: "artwork.get", body: artworkBody, seq: 1, nonce: nonce))
            #expect(await waitFor { h.server.artworkInFlightTotal == 1 }, "第 \(round) 輪素材請求沒有進到處理")
            peer.cancel()
            #expect(await waitFor { h.server.connectedPeers.isEmpty })
            handler.releaseAll()
            await expectClean(h.server, round: round, "素材在途")
        }
    }

    /// 情境 3：網路 queue 被佔住、推播還在待送時客戶端斷線——放開後待送帳歸零，20 輪
    @Test func pendingSendsAtDisconnectAreReleased() async throws {
        let h = try await pairedHarness(handler: ScriptedHandler())
        for round in 1...20 {
            let (peer, _) = try await session(h)
            #expect(await waitFor { h.server.connectedPeers.count == 1 })
            let released = Locked(false)
            h.server.occupyNetworkQueue(for: 0.3) { released.withLock { $0 = true } }
            h.server.broadcast(.eventCatalogChanged, CatalogChangedEvent(version: "0123456789abcdef"))
            #expect(h.server.pendingSendBytesTotal > 0, "第 \(round) 輪推播沒有進待送帳")
            peer.cancel()
            #expect(await waitFor { released.withLock { $0 } })
            await expectClean(h.server, round: round, "待送中斷")
        }
    }

    /// 伺服器 stop()／start() 20 輪：每次 start() 回傳新 port（以 .any 監聽），客戶端連新 port 並完成往返
    @Test func restartingTheServerLeavesNothingBehind() async throws {
        let h = try await pairedHarness(handler: ScriptedHandler())
        var port = h.port
        for round in 1...20 {
            let (peer, nonce) = try await session(h, port: port)
            peer.send(envelope(kind: "catalog.page", body: pageBody, seq: 1, nonce: nonce))
            #expect(await peer.nextKind()?.kind == "catalog.page", "第 \(round) 輪沒有回覆")
            h.server.stop()
            #expect(await peer.waitClosed(), "第 \(round) 輪 stop 後客戶端沒有看到關閉")
            await expectClean(h.server, round: round, "重啟")
            port = try await h.server.start()
        }
    }
}
#endif
