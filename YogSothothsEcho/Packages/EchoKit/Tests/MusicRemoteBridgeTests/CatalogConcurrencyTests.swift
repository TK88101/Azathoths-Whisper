#if os(macOS)
import Foundation
import Testing
import RemoteProtocol
@testable import MusicRemoteBridge

// T6：分頁、搜尋、封面與週期重建同時進行（以 --sanitize=thread 跑一次，sprint-3-detail.md §7）
struct CatalogConcurrencyTests {
    @Test func concurrentRequestsDuringRebuildsStayConsistent() async throws {
        let songs = (1...300).map { rawTrack(UInt64($0), album: UInt64($0), title: "Song \($0)", albumTitle: "Album \($0)") }
        let source = FakeCatalogSource(songs: songs)
        await source.set(artwork: Dictionary(uniqueKeysWithValues: (1...20).map { (UInt64($0), TestImage.noisePNG(width: 64, height: 64, seed: UInt64($0))) }))
        let clock = FakeCatalogClock()
        let service = CatalogService(source: source, clock: clock, onChange: { _ in })
        let first = try await service.page(CatalogPageRequest(cursor: nil, limit: 200)).get()
        await service.startWatching()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<120 {
                group.addTask {
                    switch i % 3 {
                    case 0:
                        let page = try await service.page(CatalogPageRequest(cursor: nil, limit: 50)).get()
                        #expect(!page.albums.isEmpty)
                    case 1:
                        _ = try await service.search(CatalogSearchRequest(query: "song", limit: 10)).get()
                    default:
                        let album = first.albums[i % first.albums.count]
                        if let token = album.artworkToken {
                            let response = try await service.artwork(ArtworkRequest(albumID: album.id, size: .spine, artworkToken: token)).get()
                            #expect(response.isValid)
                        }
                    }
                }
            }
            group.addTask {
                for n in 0..<10 {
                    await source.set(songs: songs + [rawTrack(UInt64(1000 + n), album: UInt64(1000 + n))])
                    await clock.tick()
                    try? await Task.sleep(for: .milliseconds(2))
                }
            }
            try await group.waitForAll()
        }
        await service.stopWatching()
        await clock.tick()
    }
}
#endif
