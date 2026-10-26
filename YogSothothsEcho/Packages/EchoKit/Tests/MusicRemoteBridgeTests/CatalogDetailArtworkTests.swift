import CryptoKit
import Foundation
import Testing

@testable import MusicRemoteBridge
import RemoteProtocol

// CR-018（sprint-5-detail.md §11）：CatalogService 的 detail＝原檔原樣分塊。token 每塊都核；原檔不進共用封面 LRU（simcodex R1：最大 6 MiB 會擠掉縮圖）；
// 傳輸生命週期由 DetailTransferBook 管；斷線清除

private func jpegLike(_ count: Int) -> Data {
    var data = Data([0xFF, 0xD8, 0xFF, 0xE0])
    data.append(Data((0..<(count - 4)).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }))
    return data
}

private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

struct CatalogDetailArtworkTests {
    let source = FakeCatalogSource(songs: [rawTrack(1, album: 1, title: "Song 1", albumTitle: "Album 1")])
    let clock = FakeCatalogClock()
    let service: CatalogService
    let peer = UUID()

    init() {
        service = CatalogService(source: source, clock: clock, onChange: { _ in })
    }

    private func album() async throws -> AlbumSummary {
        try #require(try await service.page(CatalogPageRequest(cursor: nil, limit: 1)).get().albums.first)
    }

    private func request(_ album: AlbumSummary, part: Int, digest: String? = nil, generation: UInt64 = 1,
                         token: String? = nil) -> ArtworkRequest {
        ArtworkRequest(albumID: album.id, size: .detail, artworkToken: token ?? album.artworkToken!, part: part, digest: digest,
                       generation: generation)
    }

    /// 原檔原樣：所有塊拼回＝原檔位元組，SHA-256 相符；原檔只讀一次
    @Test func partsReassembleToTheOriginalBytes() async throws {
        let original = jpegLike(100_000)
        await source.set(artwork: [1: original])
        let summary = try await album()
        let first = try await service.artwork(request(summary, part: 0), peer: peer).get()
        let head = try #require(first.detail)
        #expect(first.outcome == .image && first.isValid && head.partCount == 3 && head.mime == .jpeg && head.digest == sha(original))
        var assembled = head.chunk
        for index in 1..<head.partCount {
            let next = try await service.artwork(request(summary, part: index, digest: head.digest), peer: peer).get()
            assembled.append(try #require(next.detail).chunk)
        }
        #expect(assembled == original)
        #expect(await source.artworkCalls == 1)
    }

    @Test func pngIsAcceptedAndOtherFormatsAreNone() async throws {
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        png.append(Data(count: 20))
        await source.set(artwork: [1: png])
        let summary = try await album()
        #expect(try await service.artwork(request(summary, part: 0), peer: peer).get().detail?.mime == .png)
        await source.set(artwork: [1: Data([0x47, 0x49, 0x46, 0x38, 0, 0])])
        let other = CatalogService(source: source, clock: clock, onChange: { _ in })
        let response = try await other.artwork(request(summary, part: 0), peer: peer).get()
        #expect(response.outcome == ArtworkOutcome.none && response.detail == nil)
    }

    @Test func oversizedOriginalIsTooLarge() async throws {
        await source.set(artwork: [1: jpegLike(DetailArtworkLimits.maxTotalBytes + 1)])
        let summary = try await album()
        let response = try await service.artwork(request(summary, part: 0), peer: peer).get()
        #expect(response.outcome == .tooLarge && response.detail == nil && response.isValid)
    }

    /// 原檔不進共用封面 LRU：每次新傳輸的 part 0 都重讀（過大的也不留在記憶體裡），縮圖快取不被擠掉
    @Test func originalsAreNotKeptInTheSharedCache() async throws {
        await source.set(artwork: [1: jpegLike(DetailArtworkLimits.maxTotalBytes + 1)])
        let summary = try await album()
        _ = try await service.artwork(request(summary, part: 0, generation: 1), peer: peer).get()
        _ = try await service.artwork(request(summary, part: 0, generation: 2), peer: peer).get()
        #expect(await source.artworkCalls == 2)
    }

    @Test func exactlyMaxSizeIsSent() async throws {
        await source.set(artwork: [1: jpegLike(DetailArtworkLimits.maxTotalBytes)])
        let summary = try await album()
        #expect(try await service.artwork(request(summary, part: 0), peer: peer).get().detail?.partCount == DetailArtworkLimits.maxParts)
    }

    /// 每塊都核 token：中途換版＝stale（帶目前 token）
    @Test func tokenIsCheckedOnEveryPart() async throws {
        await source.set(artwork: [1: jpegLike(100_000)])
        let summary = try await album()
        let head = try #require(try await service.artwork(request(summary, part: 0), peer: peer).get().detail)
        let stale = try await service.artwork(request(summary, part: 1, digest: head.digest, token: "ffffffffffffffff"), peer: peer).get()
        #expect(stale.outcome == .stale && stale.artworkToken == summary.artworkToken)
    }

    /// 同 peer 重新連線（App 重開、世代從頭算）：釋放後較小的世代也能開始新傳輸
    @Test func releasedPeerAcceptsRestartedGenerations() async throws {
        await source.set(artwork: [1: jpegLike(100_000)])
        let summary = try await album()
        _ = try await service.artwork(request(summary, part: 0, generation: 57), peer: peer).get()
        let before = try await service.artwork(request(summary, part: 0, generation: 1), peer: peer).get()
        #expect(before.outcome == .restart)
        await service.releasePeer(peer)
        let after = try await service.artwork(request(summary, part: 0, generation: 1), peer: peer).get()
        #expect(after.outcome == .image)
    }

    /// 被取代或不符的後續塊＝restart；斷線後同 peer 的後續塊也 restart
    @Test func supersededAndDisconnectedTransfersRestart() async throws {
        await source.set(artwork: [1: jpegLike(100_000)])
        let summary = try await album()
        let head = try #require(try await service.artwork(request(summary, part: 0, generation: 1), peer: peer).get().detail)
        _ = try await service.artwork(request(summary, part: 0, generation: 2), peer: peer).get()
        #expect(try await service.artwork(request(summary, part: 1, digest: head.digest, generation: 1), peer: peer).get().outcome == .restart)
        await service.releasePeer(peer)
        #expect(try await service.artwork(request(summary, part: 1, digest: head.digest, generation: 2), peer: peer).get().outcome == .restart)
    }

    /// 過舊的 part 0＝restart；全域名額滿（其他 peer）＝busy
    @Test func staleGenerationRestartsAndGlobalLimitIsBusy() async throws {
        await source.set(artwork: [1: jpegLike(100_000)])
        let summary = try await album()
        _ = try await service.artwork(request(summary, part: 0, generation: 5), peer: peer).get()
        #expect(try await service.artwork(request(summary, part: 0, generation: 4), peer: peer).get().outcome == .restart)
        _ = try await service.artwork(request(summary, part: 0), peer: UUID()).get()
        #expect(await service.artwork(request(summary, part: 0), peer: UUID()).failure == .busy)
    }

    /// 閒置 30 s 回收（以注入的時鐘）
    @Test func idleTransferIsReclaimed() async throws {
        await source.set(artwork: [1: jpegLike(100_000)])
        let summary = try await album()
        let head = try #require(try await service.artwork(request(summary, part: 0), peer: peer).get().detail)
        await clock.advance(31)
        #expect(try await service.artwork(request(summary, part: 1, digest: head.digest), peer: peer).get().outcome == .restart)
    }

    /// spine 路徑不受影響（仍是縮圖 JPEG、走 jpeg 欄位）
    @Test func spineStillReturnsThumbnail() async throws {
        await source.set(artwork: [1: TestImage.noisePNG(width: 300, height: 300)])
        let summary = try await album()
        let spine = try await service.artwork(ArtworkRequest(albumID: summary.id, size: .spine, artworkToken: summary.artworkToken!),
                                              peer: peer).get()
        #expect(spine.outcome == .image && spine.jpeg != nil && spine.detail == nil && spine.isValid)
    }
}
