#if os(macOS)
import Foundation
import Network
import RemoteProtocol
import Testing
@testable import MusicRemoteBridge
@testable import RemoteTransport

// S3 T13（F-L-05；sprint-3-detail.md §4.7）：替身曲庫改內容 → 週期重建換版 → broadcast → iPad 收到事件 → 重取頁看到新清單

private actor MutableSource: CatalogSource {
    var count: Int
    init(count: Int) { self.count = count }
    func set(count: Int) { self.count = count }
    func load() async throws(CatalogSourceError) -> CatalogLoad {
        CatalogLoad(songs: (1...count).map {
            RawTrack(trackID: UInt64($0), albumID: UInt64($0), albumTitle: "Album \($0)", sortAlbumTitle: nil, albumArtist: "Artist",
                     sortAlbumArtist: nil, artist: "Artist", title: "Song \($0)", discNumber: 1, trackNumber: 1, modifiedAt: nil,
                     hasArtwork: false)
        }, skipped: [:])
    }
    func artworkData(trackID: UInt64) async -> Data? { nil }
}

private actor TickClock: CatalogClock {
    private var sleepers: [CheckedContinuation<Void, Never>] = []
    nonisolated func now() async -> Date { Date() }
    func sleep(seconds: TimeInterval) async throws {
        await withCheckedContinuation { sleepers.append($0) }
        try Task.checkCancellation()
    }
    func tick() { sleepers.forEach { $0.resume() }; sleepers.removeAll() }
    var sleeping: Int { sleepers.count }
}

/// 測試用的最小轉接（正式版是 Azathoth 的 RelayRequestRouter）
private struct PageOnlyHandler: RequestHandling {
    let service: CatalogService
    func handle(_ request: InboundRequest) async -> OutboundReply {
        guard request.kind == .catalogPage, let body = request.body(as: CatalogPageRequest.self) else { return .error(.invalidRequest) }
        switch await service.page(body) {
        case .success(let page): return request.reply(page)
        case .failure(let code): return .error(code)
        }
    }
}

private final class ServerBox: @unchecked Sendable {
    var server: TransportServer?
}

@Suite(.serialized) struct CatalogChangeEndToEndTests {
    @Test func libraryChangeReachesIPadAndResyncShowsNewList() async throws {
        let source = MutableSource(count: 30)
        let clock = TickClock()
        let box = ServerBox()
        let service = CatalogService(source: source, clock: clock, onChange: { version in
            box.server?.broadcast(.eventCatalogChanged, CatalogChangedEvent(version: version))
        })
        let h = try await Harness(handler: PageOnlyHandler(service: service))
        box.server = h.server
        guard case .approved = await h.pair() else { Issue.record("pair"); return }
        let session = try await h.client().connect(endpoint: h.endpoint).get()

        let first = try await session.request(.catalogPage, CatalogPageRequest(cursor: nil, limit: 200), as: CatalogPageResponse.self)
        #expect(first.total == 30)

        await service.startWatching()
        #expect(await waitAsync { await clock.sleeping == 1 })
        await source.set(count: 35)
        await clock.tick()

        var events = session.events.makeAsyncIterator()
        let event = await events.next()
        let version = try #require(event?.body(as: CatalogChangedEvent.self)?.version)
        #expect(version != first.version)

        let again = try await session.request(.catalogPage, CatalogPageRequest(cursor: nil, limit: 200), as: CatalogPageResponse.self)
        #expect(again.total == 35 && again.version == version)
        await service.stopWatching()
        session.close()
    }

    private func waitAsync(_ condition: @escaping @Sendable () async -> Bool) async -> Bool {
        for _ in 0..<300 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }
}
#endif
