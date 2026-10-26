#if os(macOS)
import Foundation
import Testing
import RemoteProtocol
@testable import MusicRemoteBridge

// T4（sprint-3-detail.md §4.5）：CatalogService 以替身來源與假時鐘測

actor FakeCatalogSource: CatalogSource {
    var songs: [RawTrack]
    var failure: CatalogSourceError?
    private(set) var loadCount = 0
    private(set) var artworkCalls = 0
    var artwork: [UInt64: Data] = [:]
    private var gate: CheckedContinuation<Void, Never>?
    var holdLoads = false

    init(songs: [RawTrack]) { self.songs = songs }

    func set(songs: [RawTrack]) { self.songs = songs }
    func set(failure: CatalogSourceError?) { self.failure = failure }
    func set(artwork: [UInt64: Data]) { self.artwork = artwork }
    func hold(_ value: Bool) { holdLoads = value }
    func release() { gate?.resume(); gate = nil }
    var isHolding: Bool { gate != nil }

    func load() async throws(CatalogSourceError) -> CatalogLoad {
        loadCount += 1
        if holdLoads { await withCheckedContinuation { gate = $0 } }
        if let failure { throw failure }
        return CatalogLoad(songs: songs, skipped: [:])
    }

    func artworkData(trackID: UInt64) async -> Data? {
        artworkCalls += 1
        return artwork[trackID]
    }
}

actor FakeCatalogClock: CatalogClock {
    private var current = Date(timeIntervalSince1970: 1_000_000)
    private var sleepers: [CheckedContinuation<Void, Never>] = []

    nonisolated func now() async -> Date { await current }
    func sleep(seconds: TimeInterval) async throws {
        await withCheckedContinuation { sleepers.append($0) }
        try Task.checkCancellation()
    }
    func advance(_ seconds: TimeInterval) { current += seconds }
    /// 喚醒所有在睡的 watcher
    func tick() { sleepers.forEach { $0.resume() }; sleepers.removeAll() }
    var sleeperCount: Int { sleepers.count }
}

final class ChangeLog: @unchecked Sendable {
    private let lock = NSLock()
    private var versions: [String] = []
    func append(_ v: String) { lock.lock(); versions.append(v); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return versions }
}

private func albums(_ count: Int) -> [RawTrack] {
    (1...count).map { rawTrack(UInt64($0), album: UInt64($0), title: "Song \($0)", albumTitle: "Album \($0)",
                               albumArtist: String(format: "Artist %04d", $0)) }
}

struct CatalogServiceTests {
    let source: FakeCatalogSource
    let clock = FakeCatalogClock()
    let changes = ChangeLog()
    let service: CatalogService

    init() {
        source = FakeCatalogSource(songs: albums(450))
        let changes = self.changes
        service = CatalogService(source: source, clock: clock, onChange: { changes.append($0) })
    }

    // MARK: 懶載入

    @Test func doesNotLoadBeforeFirstRequest() async {
        await service.startWatching()
        #expect(await eventually { await clock.sleeperCount == 1 })
        await clock.tick()
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await source.loadCount == 0)
        await service.stopWatching()
    }

    @Test func concurrentFirstRequestsShareOneLoad() async {
        await source.hold(true)
        async let a = service.page(CatalogPageRequest(cursor: nil, limit: 10))
        async let b = service.search(CatalogSearchRequest(query: "album", limit: 5))
        #expect(await eventually { await source.isHolding })
        await source.release()
        _ = await (a, b)
        #expect(await source.loadCount == 1)
    }

    // MARK: 分頁

    @Test func pagingReturnsEveryAlbumExactlyOnce() async throws {
        var cursor: String?
        var seen: [String] = []
        var version: String?
        repeat {
            let page = try await service.page(CatalogPageRequest(cursor: cursor, limit: 200)).get()
            version = version ?? page.version
            #expect(page.version == version && page.total == 450)
            seen += page.albums.map(\.id)
            cursor = page.nextCursor
        } while cursor != nil
        #expect(seen.count == 450 && Set(seen).count == 450)
    }

    @Test func offsetPastEndIsEmptyFinalPage() async throws {
        let first = try await service.page(CatalogPageRequest(cursor: nil, limit: 1)).get()
        let past = CatalogCursor(version: first.version, offset: 999).encoded()
        let page = try await service.page(CatalogPageRequest(cursor: past, limit: 10)).get()
        #expect(page.albums.isEmpty && page.nextCursor == nil)
    }

    @Test func invalidRequestsAreRejectedWithoutLoading() async {
        #expect(await service.page(CatalogPageRequest(cursor: nil, limit: 0)).failure == .invalidRequest)
        #expect(await service.search(CatalogSearchRequest(query: " ", limit: 5)).failure == .invalidRequest)
        #expect(await service.artwork(ArtworkRequest(albumID: "x", size: .spine, artworkToken: "y"), peer: UUID()).failure == .invalidRequest)
        #expect(await source.loadCount == 0)
    }

    /// CR-018：detail 必須帶 part 與 generation（缺＝不合法）；full 一律不合法
    @Test func detailWithoutPartAndFullAreInvalid() async {
        let detail = ArtworkRequest(albumID: "0000000000000001", size: .detail, artworkToken: "0000000000000001")
        let full = ArtworkRequest(albumID: "0000000000000001", size: .full, artworkToken: "0000000000000001")
        #expect(await service.artwork(detail, peer: UUID()).failure == .invalidRequest)
        #expect(await service.artwork(full, peer: UUID()).failure == .invalidRequest)
    }

    // MARK: 曲庫不可讀

    @Test func unavailableLibraryReportsLibraryUnavailableAndThrottlesRetries() async {
        await source.set(failure: .unavailable(code: 4097))
        #expect(await service.page(CatalogPageRequest(cursor: nil, limit: 10)).failure == .libraryUnavailable)
        #expect(await service.state == .unavailable(code: 4097))
        #expect(await service.page(CatalogPageRequest(cursor: nil, limit: 10)).failure == .libraryUnavailable)
        #expect(await source.loadCount == 1)                    // 10 s 內不再碰來源
        await source.set(failure: nil)
        await clock.advance(CatalogService.retryInterval)
        #expect((try? await service.page(CatalogPageRequest(cursor: nil, limit: 10)).get()) != nil)
        #expect(await source.loadCount == 2)
    }

    /// 可讀與否只在翻轉時通知一次（simplify altitude P1-3：不再每個回覆通知）
    @Test func availabilityIsReportedOnlyOnChange() async {
        let log = ChangeLog()
        let source = FakeCatalogSource(songs: albums(5))
        await source.set(failure: .unavailable(code: 4097))
        let clock = FakeCatalogClock()
        let service = CatalogService(source: source, clock: clock, onChange: { _ in },
                                     onAvailability: { log.append($0 ? "up" : "down") })
        _ = await service.page(CatalogPageRequest(cursor: nil, limit: 1))
        _ = await service.page(CatalogPageRequest(cursor: nil, limit: 1))
        await source.set(failure: nil)
        await clock.advance(CatalogService.retryInterval)
        _ = await service.page(CatalogPageRequest(cursor: nil, limit: 1))
        _ = await service.search(CatalogSearchRequest(query: "album", limit: 5))
        #expect(log.all == ["down", "up"])
    }

    /// Codex 第 2 輪 P2：已載入後重建失敗（權限被收回、reloadData 失敗）不得繼續供應舊資料——轉為讀不到並通知
    @Test func rebuildFailureAfterLoadBecomesUnavailable() async throws {
        let log = ChangeLog()
        let source = FakeCatalogSource(songs: albums(5))
        let clock = FakeCatalogClock()
        let service = CatalogService(source: source, clock: clock, onChange: { _ in },
                                     onAvailability: { log.append($0 ? "up" : "down") })
        _ = try await service.page(CatalogPageRequest(cursor: nil, limit: 1)).get()
        await service.startWatching()
        #expect(await eventually { await clock.sleeperCount == 1 })
        await source.set(failure: .unavailable(code: 4097))
        await clock.tick()
        #expect(await eventually { log.all == ["up", "down"] })
        #expect(await service.page(CatalogPageRequest(cursor: nil, limit: 1)).failure == .libraryUnavailable)
        await source.set(failure: nil)
        await clock.advance(CatalogService.retryInterval)
        #expect((try? await service.page(CatalogPageRequest(cursor: nil, limit: 1)).get()) != nil)
        #expect(log.all == ["up", "down", "up"])
        await service.stopWatching()
    }

    // MARK: 搜尋

    @Test func searchMatchesTrackTitlesFoldedAndRespectsLimit() async throws {
        let hit = try await service.search(CatalogSearchRequest(query: "ＳＯＮＧ 42", limit: 5)).get()
        #expect(hit.albums.contains { $0.id == "000000000000002a" })
        let many = try await service.search(CatalogSearchRequest(query: "album", limit: 5)).get()
        #expect(many.albums.count == 5)
        let none = try await service.search(CatalogSearchRequest(query: "zzzz", limit: 5)).get()
        #expect(none.albums.isEmpty)
    }

    // MARK: 封面

    private func firstAlbum() async throws -> AlbumSummary {
        try #require(try await service.page(CatalogPageRequest(cursor: nil, limit: 1)).get().albums.first)
    }

    @Test func artworkReturnsImageAndCaches() async throws {
        await source.set(artwork: [1: TestImage.noisePNG(width: 300, height: 300)])
        let album = try await firstAlbum()
        let request = ArtworkRequest(albumID: album.id, size: .spine, artworkToken: try #require(album.artworkToken))
        let first = try await service.artwork(request, peer: UUID()).get()
        #expect(first.outcome == .image && first.jpeg != nil && first.isValid)
        _ = try await service.artwork(request, peer: UUID()).get()
        #expect(await source.artworkCalls == 1)
    }

    @Test func wrongTokenIsStaleWithCurrentToken() async throws {
        let album = try await firstAlbum()
        let response = try await service.artwork(ArtworkRequest(albumID: album.id, size: .spine, artworkToken: "ffffffffffffffff"), peer: UUID()).get()
        #expect(response.outcome == .stale && response.artworkToken == album.artworkToken && response.jpeg == nil)
        #expect(await source.artworkCalls == 0)
    }

    @Test func unknownAlbumIsStale() async throws {
        _ = try await firstAlbum()
        let response = try await service.artwork(ArtworkRequest(albumID: "00000000deadbeef", size: .spine,
                                                                artworkToken: "ffffffffffffffff"), peer: UUID()).get()
        #expect(response.outcome == .stale && response.artworkToken == nil)
    }

    @Test func unreadableArtworkIsNone() async throws {
        let album = try await firstAlbum()
        let response = try await service.artwork(ArtworkRequest(albumID: album.id, size: .spine,
                                                                artworkToken: try #require(album.artworkToken)), peer: UUID()).get()
        #expect(response.outcome == ArtworkOutcome.none && response.jpeg == nil)
    }

    // MARK: 週期重建

    private func loadOnce() async throws -> String {
        try await service.page(CatalogPageRequest(cursor: nil, limit: 1)).get().version
    }

    @Test func rebuildReplacesIndexAndNotifiesOnlyOnChange() async throws {
        let v1 = try await loadOnce()
        await service.startWatching()
        #expect(await eventually { await clock.sleeperCount == 1 })
        await clock.tick()                                       // 內容未變
        #expect(await eventually { await source.loadCount == 2 })
        #expect(await eventually { await clock.sleeperCount == 1 })
        #expect(changes.all.isEmpty)
        await source.set(songs: albums(451))
        await clock.tick()
        #expect(await eventually { changes.all.count == 1 })
        let v2 = try await loadOnce()
        #expect(v2 != v1 && changes.all == [v2])
        await service.stopWatching()
    }

    @Test func startingTwiceKeepsOneWatcher() async throws {
        _ = try await loadOnce()
        await service.startWatching()
        await service.startWatching()
        #expect(await eventually { await clock.sleeperCount == 1 })
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await clock.sleeperCount == 1)
        await service.stopWatching()
    }

    @Test func rebuildFinishingAfterStopIsDiscarded() async throws {
        let v1 = try await loadOnce()
        await service.startWatching()
        #expect(await eventually { await clock.sleeperCount == 1 })
        await source.set(songs: albums(460))
        await source.hold(true)
        await clock.tick()
        #expect(await eventually { await source.isHolding })
        await service.stopWatching()
        await source.release()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(changes.all.isEmpty)
        #expect(try await loadOnce() == v1)
    }

    @Test func changedArtworkMakesOldTokenStale() async throws {
        let before = try await firstAlbum()
        await service.startWatching()
        #expect(await eventually { await clock.sleeperCount == 1 })
        var songs = albums(450)
        songs[0] = rawTrack(1, album: 1, title: "Song 1", albumTitle: "Album 1", albumArtist: "Artist 0001",
                             modified: Date(timeIntervalSince1970: 1_900_000_000))
        await source.set(songs: songs)
        await clock.tick()
        #expect(await eventually { changes.all.count == 1 })
        let response = try await service.artwork(ArtworkRequest(albumID: before.id, size: .spine,
                                                                artworkToken: try #require(before.artworkToken))).get()
        #expect(response.outcome == .stale && response.artworkToken != before.artworkToken)
        await service.stopWatching()
    }
}

extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
#endif
